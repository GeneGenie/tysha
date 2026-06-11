import Foundation
import Observation
import QuartzCore
import AVFoundation
import UIKit

// MARK: - CADisplayLink proxy

/// CADisplayLink needs an @objc target. The engine itself is a plain `@Observable`
/// class, so this small NSObject forwards ticks to a closure.
private final class DisplayLinkProxy: NSObject {
    private var link: CADisplayLink?
    private let onTick: () -> Void

    init(onTick: @escaping () -> Void) {
        self.onTick = onTick
        super.init()
    }

    func start() {
        stop()
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step() { onTick() }
}

// MARK: - Haptics

private final class HapticManager {
    private let heavy  = UIImpactFeedbackGenerator(style: .heavy)
    private let soft   = UIImpactFeedbackGenerator(style: .medium)
    private let notify = UINotificationFeedbackGenerator()
    var enabled = true

    func prepare() {
        guard enabled else { return }
        heavy.prepare(); soft.prepare(); notify.prepare()
    }

    /// Fired on every phase change.
    func phaseChange() {
        guard enabled else { return }
        heavy.impactOccurred()
        heavy.prepare()
    }

    /// Softer pulse at the start and end of the long exhale hold.
    func softPulse() {
        guard enabled else { return }
        soft.impactOccurred()
        soft.prepare()
    }

    /// Success notification at the end of each round and the whole session.
    func success() {
        guard enabled else { return }
        notify.notificationOccurred(.success)
        notify.prepare()
    }
}

// MARK: - Audio

private final class AudioManager: NSObject, AVAudioPlayerDelegate {
    private var phasePlayers: [BreathPhase: AVAudioPlayer] = [:]
    private var bgPlayer: AVAudioPlayer?
    var enabled = true

    func configureSession() {
        guard enabled else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    func preload() {
        phasePlayers.removeAll()
        guard enabled else { return }

        for phase in [BreathPhase.inhale, .holdIn, .exhale, .holdOut] {
            guard let url = Bundle.main.url(forResource: phase.audioFile, withExtension: "mp3"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue } // missing → silent
            player.prepareToPlay()
            phasePlayers[phase] = player
        }

        if let url = Bundle.main.url(forResource: AudioConfig.backgroundMusicFile, withExtension: "mp3"),
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.delegate = self
            player.volume = AudioConfig.backgroundMusicVolume
            player.prepareToPlay()
            bgPlayer = player
        }
    }

    func startBackgroundMusic() {
        guard enabled, let player = bgPlayer else { return }
        player.currentTime = bgStartOffset(for: player)
        player.play()
    }

    func play(_ phase: BreathPhase) {
        guard enabled, let player = phasePlayers[phase] else { return }
        player.currentTime = 0
        player.play()
    }

    func stopAll() {
        bgPlayer?.stop()
        phasePlayers.values.forEach { $0.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func bgStartOffset(for player: AVAudioPlayer) -> TimeInterval {
        min(AudioConfig.backgroundMusicStartSec, max(0, player.duration - 0.1))
    }

    // Loop the background bed from the configured offset (keep the "good part").
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard enabled, player === bgPlayer else { return }
        player.currentTime = bgStartOffset(for: player)
        player.play()
    }
}

// MARK: - Engine

@Observable
final class BreathEngine {
    // Observed state consumed by the views and the shader.
    private(set) var phase: BreathPhase = .inhale
    private(set) var prevPhase: BreathPhase = .inhale
    private(set) var phaseProgress: Double = 0      // 0...1 within the current phase
    private(set) var transition: Double = 1         // 0...1 crossfade ramp into the current phase
    private(set) var secondsText: String = ""
    private(set) var currentRound: Int = 0
    private(set) var totalRounds: Int = 0
    private(set) var breathIndex: Int = 0
    private(set) var breathsPerRound: Int = 0
    private(set) var isBreathSeries: Bool = false
    private(set) var isFinished: Bool = false
    private(set) var isRunning: Bool = false
    private(set) var shaderTime: Double = 0         // continuous seconds, drives noise animation

    // Internals — excluded from observation so they don't trigger view updates.
    @ObservationIgnored private var queue: [PhaseStep] = []
    @ObservationIgnored private var index = 0
    @ObservationIgnored private var stepStart: CFTimeInterval = 0
    @ObservationIgnored private var sessionStart: CFTimeInterval = 0
    @ObservationIgnored private var settings = BreathSettings()
    @ObservationIgnored private var proxy: DisplayLinkProxy?
    @ObservationIgnored private let haptics = HapticManager()
    @ObservationIgnored private let audio = AudioManager()

    private static let crossfadeSec = 0.5

    // MARK: Lifecycle

    func start(settings: BreathSettings) {
        stop() // clean restart

        let s = settings.normalized()
        self.settings = s
        queue = s.buildQueue()
        guard !queue.isEmpty else { return }

        totalRounds = s.rounds
        breathsPerRound = s.breathsPerRound
        breathIndex = 0
        index = 0
        isFinished = false
        isRunning = true

        haptics.enabled = s.hapticsEnabled
        haptics.prepare()

        audio.enabled = s.soundEnabled
        audio.configureSession()
        audio.preload()
        audio.startBackgroundMusic()

        UIApplication.shared.isIdleTimerDisabled = true

        sessionStart = CACurrentMediaTime()
        beginStep(at: 0, now: sessionStart, isFirst: true)

        let proxy = DisplayLinkProxy { [weak self] in self?.tick() }
        proxy.start()
        self.proxy = proxy
    }

    func restart() {
        start(settings: settings)
    }

    /// Manual exit (Выход button) or teardown.
    func stop() {
        guard isRunning || proxy != nil else { return }
        isRunning = false
        proxy?.stop()
        proxy = nil
        audio.stopAll()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Stepping

    private func beginStep(at i: Int, now: CFTimeInterval, isFirst: Bool) {
        let step = queue[i]
        prevPhase = isFirst ? step.phase : phase
        phase = step.phase
        stepStart = now
        currentRound = step.round
        if let b = step.breathIndex { breathIndex = b }
        isBreathSeries = (step.breathIndex != nil)
        // Inhale flash is intentionally sharp (no crossfade); other phases ease in.
        transition = (step.phase == .inhale) ? 1 : 0

        haptics.phaseChange()
        audio.play(step.phase)
        if step.phase == .holdOut { haptics.softPulse() } // start of the long hold

        updateDisplay(elapsed: 0, step: step)
    }

    private func tick() {
        guard isRunning, index < queue.count else { return }
        let now = CACurrentMediaTime()
        shaderTime = now - sessionStart

        let step = queue[index]
        let elapsed = now - stepStart

        transition = (step.phase == .inhale) ? 1 : min(1, elapsed / Self.crossfadeSec)

        if elapsed >= step.duration {
            advance(now: now)
        } else {
            updateDisplay(elapsed: elapsed, step: step)
        }
    }

    private func advance(now: CFTimeInterval) {
        let finishing = queue[index]
        if finishing.phase == .holdOut { haptics.softPulse() } // end of the long hold

        let next = index + 1
        if next >= queue.count {
            finishSession()
            return
        }

        if queue[next].round != finishing.round { haptics.success() } // round complete

        index = next
        beginStep(at: next, now: now, isFirst: false)
    }

    private func finishSession() {
        haptics.success() // whole session complete
        isRunning = false
        isFinished = true
        phaseProgress = 1
        proxy?.stop()
        proxy = nil
        audio.stopAll()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Display

    private func updateDisplay(elapsed: Double, step: PhaseStep) {
        let duration = max(0.0001, step.duration)
        phaseProgress = min(1, max(0, elapsed / duration))

        if step.phase.countsUp {
            // Long exhale hold: count up mm:ss from 00:00.
            secondsText = Self.mmss(elapsed)
        } else {
            // Everything else: integer countdown to the end of the phase.
            let remaining = max(0, ceil(step.duration - elapsed))
            secondsText = String(Int(remaining))
        }
    }

    private static func mmss(_ t: Double) -> String {
        let total = Int(t)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

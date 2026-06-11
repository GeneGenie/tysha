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
    private let light  = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()
    var enabled = true

    func prepare() {
        guard enabled else { return }
        heavy.prepare(); soft.prepare(); light.prepare(); notify.prepare()
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

    /// Four medium taps — the 15-second marker during the long hold.
    func holdMarker() {
        burst(soft, count: 4, intensity: 1.0, interval: 0.13)
    }

    /// Four light taps — final-countdown tick (each of the last 3 seconds).
    func countdownTick() {
        burst(light, count: 4, intensity: 1.0, interval: 0.10)
    }

    private func burst(_ gen: UIImpactFeedbackGenerator, count: Int, intensity: CGFloat, interval: TimeInterval) {
        guard enabled else { return }
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) { [weak self] in
                guard let self, self.enabled else { return }
                gen.impactOccurred(intensity: intensity)
                gen.prepare()
            }
        }
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
    private var longExhalePlayer: AVAudioPlayer?
    private var bgPlayer: AVAudioPlayer?
    var enabled = true
    var breathVolume: Float = AudioConfig.breathVolume          // overridden from settings
    var musicVolume: Float = AudioConfig.backgroundMusicVolume  // overridden from settings

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
            player.enableRate = true
            player.volume = breathVolume
            player.prepareToPlay()
            phasePlayers[phase] = player
        }

        // Pre-stretched ~4s clip for the round-closing slow exhale.
        if let url = Bundle.main.url(forResource: "exhale_long", withExtension: "mp3"),
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.volume = breathVolume
            player.prepareToPlay()
            longExhalePlayer = player
        }

        if let url = Bundle.main.url(forResource: AudioConfig.backgroundMusicFile, withExtension: "mp3"),
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.delegate = self
            player.volume = musicVolume
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
        player.rate = 1.0
        player.currentTime = 0
        player.play()
    }

    /// Round-closing slow exhale: dedicated pre-stretched clip if bundled,
    /// otherwise the normal exhale slowed down (AVAudioPlayer rate floor is 0.5).
    func playLongExhale(targetSec: Double) {
        guard enabled else { return }
        if let player = longExhalePlayer {
            player.currentTime = 0
            player.play()
        } else if let player = phasePlayers[.exhale], player.duration > 0, targetSec > 0 {
            player.rate = Float(min(2.0, max(0.5, player.duration / targetSec)))
            player.currentTime = 0
            player.play()
        }
    }

    func stopAll() {
        bgPlayer?.stop()
        longExhalePlayer?.stop()
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
    private(set) var shaderPhase: Int = BreathPhase.exhale.shaderIndex      // visual, not 1:1 with `phase`
    private(set) var shaderPrevPhase: Int = BreathPhase.exhale.shaderIndex
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
    @ObservationIgnored private var transitionInstant = true
    @ObservationIgnored private var holdOutMark15 = 0
    @ObservationIgnored private var holdOutCountdownSec = Int.max
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
        audio.breathVolume = Float(s.breathVolume)
        audio.musicVolume = Float(s.musicVolume)
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

    /// Visual (shader) phase for a step. The whole breath series keeps one steady
    /// fractal background — no per-breath flash/switching; the flash is reserved
    /// for the recovery inhale after the long hold.
    private static func shaderIndex(for step: PhaseStep) -> Int {
        if step.breathIndex != nil { return BreathPhase.exhale.shaderIndex }
        return step.phase.shaderIndex
    }

    private func beginStep(at i: Int, now: CFTimeInterval, isFirst: Bool) {
        let step = queue[i]
        phase = step.phase
        stepStart = now
        currentRound = step.round
        if let b = step.breathIndex { breathIndex = b }
        isBreathSeries = (step.breathIndex != nil)

        let newIdx = Self.shaderIndex(for: step)
        shaderPrevPhase = isFirst ? newIdx : shaderPhase
        shaderPhase = newIdx
        // No crossfade when the visual doesn't change, for the sharp recovery
        // flash, and for the hold-out blackout (its darkening starts immediately;
        // its base fractal continues the exhale one seamlessly).
        transitionInstant = (newIdx == shaderPrevPhase)
            || step.phase == .holdOut
            || (step.phase == .inhale && step.breathIndex == nil)
        transition = transitionInstant ? 1 : 0

        holdOutMark15 = 0
        holdOutCountdownSec = Int.max

        haptics.phaseChange()
        if step.phase == .exhale && step.breathIndex == nil {
            audio.playLongExhale(targetSec: step.duration) // round-closing slow exhale
        } else {
            audio.play(step.phase)
        }
        if step.phase == .holdOut { haptics.softPulse() } // start of the long hold

        updateDisplay(elapsed: 0, step: step)
    }

    private func tick() {
        guard isRunning, index < queue.count else { return }
        let now = CACurrentMediaTime()
        shaderTime = now - sessionStart

        let step = queue[index]
        let elapsed = now - stepStart

        transition = transitionInstant ? 1 : min(1, elapsed / Self.crossfadeSec)

        if elapsed >= step.duration {
            advance(now: now)
        } else {
            if step.phase == .holdOut { holdOutHaptics(elapsed: elapsed, duration: step.duration) }
            updateDisplay(elapsed: elapsed, step: step)
        }
    }

    /// Extra hold-out haptics: a light double pulse every 15 s, and a small
    /// double pulse at 3/2/1 seconds before the hold ends.
    private func holdOutHaptics(elapsed: Double, duration: Double) {
        let remaining = duration - elapsed

        let mark = Int(elapsed / 15)
        if mark > holdOutMark15 && remaining > 3 {
            holdOutMark15 = mark
            haptics.holdMarker()
        }

        let sec = Int(ceil(remaining))
        if sec >= 1 && sec <= 3 && sec != holdOutCountdownSec {
            holdOutCountdownSec = sec
            haptics.countdownTick()
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

import Foundation

// MARK: - Phases

/// The four breathing phases. Raw value doubles as the index passed to the Metal shader
/// (0 = inhale, 1 = hold-in, 2 = exhale, 3 = hold-out) — see the spec's phase table.
enum BreathPhase: Int, Codable {
    case inhale  = 0   // вдох в серии; восстановительный вдох
    case holdIn  = 1   // восстановительная задержка на вдохе
    case exhale  = 2   // выдох в серии
    case holdOut = 3   // длинная задержка на выдохе

    var shaderIndex: Int { rawValue }

    /// Bundle resource name (without extension) for this phase's sound.
    /// Missing files are tolerated by the engine — the phase simply plays silently.
    var audioFile: String {
        switch self {
        case .inhale:  return "inhale"
        case .holdIn:  return "hold_in"
        case .exhale:  return "exhale"
        case .holdOut: return "hold_out"
        }
    }

    /// Russian label shown on the session screen.
    var title: String {
        switch self {
        case .inhale:  return "Вдох"
        case .holdIn:  return "Задержка на вдохе"
        case .exhale:  return "Выдох"
        case .holdOut: return "Задержка на выдохе"
        }
    }

    /// The long exhale hold counts *up* (how long you held); every other phase counts down.
    var countsUp: Bool { self == .holdOut }
}

// MARK: - Settings

struct BreathSettings: Codable, Equatable {
    var inhaleSec: Double = 2.0          // 0.5...5, step 0.1
    var exhaleSec: Double = 1.6          // 0.5...5, step 0.1
    var breathsPerRound: Int = 30        // 20...40
    var recoveryHoldSec: Double = 10     // 5...30 — задержка на вдохе после гипоксии
    var rounds: Int = 5                  // 1...8
    var holdOutByRound: [Double] = [60, 90, 120, 150, 180] // length == rounds
    var soundEnabled: Bool = true
    var hapticsEnabled: Bool = true

    // MARK: Constants / ranges

    static let inhaleRange: ClosedRange<Double> = 0.5...5
    static let exhaleRange: ClosedRange<Double> = 0.5...5
    static let breathsRange: ClosedRange<Int> = 20...40
    static let recoveryRange: ClosedRange<Double> = 5...30
    static let roundsRange: ClosedRange<Int> = 1...8
    static let holdOutRange: ClosedRange<Double> = 15...300
    static let holdOutStep: Double = 5
    static let defaultHoldOut: [Double] = [60, 90, 120, 150, 180]

    /// Persistent warning text, shown on both screens (spec requirement).
    static let warning = "Выполняйте лёжа. Не в воде, не за рулём, не в одиночку в первый раз. При сжатии в груди, потемнении в глазах или онемении — немедленно прекратите."

    // MARK: Persistence

    static let storageKey = "BreathSettings.v1"

    static func load() -> BreathSettings {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(BreathSettings.self, from: data)
        else { return BreathSettings() }
        return decoded.normalized()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: BreathSettings.storageKey)
        }
    }

    // MARK: Normalisation

    /// Clamp the rounds count and make `holdOutByRound` consistent with it.
    func normalized() -> BreathSettings {
        var copy = self
        copy.rounds = min(max(rounds, BreathSettings.roundsRange.lowerBound), BreathSettings.roundsRange.upperBound)
        copy.breathsPerRound = min(max(breathsPerRound, BreathSettings.breathsRange.lowerBound), BreathSettings.breathsRange.upperBound)
        copy.holdOutByRound = BreathSettings.adjustedHoldOut(holdOutByRound, to: copy.rounds)
        return copy
    }

    /// Resize the per-round hold list to `rounds` and clamp each value.
    /// - Grow: repeat the last value (defaults to 180).
    /// - Shrink: keep the first N values.
    static func adjustedHoldOut(_ arr: [Double], to rounds: Int) -> [Double] {
        let n = min(max(rounds, roundsRange.lowerBound), roundsRange.upperBound)
        var result = arr.isEmpty ? defaultHoldOut : arr
        if result.count < n {
            let fill = result.last ?? defaultHoldOut.last ?? 180
            result.append(contentsOf: Array(repeating: fill, count: n - result.count))
        } else if result.count > n {
            result = Array(result.prefix(n))
        }
        return result.map(clampHoldOut)
    }

    static func clampHoldOut(_ v: Double) -> Double {
        let stepped = (v / holdOutStep).rounded() * holdOutStep
        return min(max(stepped, holdOutRange.lowerBound), holdOutRange.upperBound)
    }
}

// MARK: - Phase queue

/// One scheduled phase. The engine plays these back in order off a `CADisplayLink`.
struct PhaseStep: Equatable {
    let phase: BreathPhase
    let duration: Double
    let round: Int          // 1-based
    let breathIndex: Int?   // 1-based position in the breath series; nil outside the series
}

extension BreathSettings {
    /// Flatten settings into a linear queue of phases (spec: "движок раскладывает
    /// настройки в плоскую очередь фаз"). Phases with duration 0 are skipped.
    func buildQueue() -> [PhaseStep] {
        let s = normalized()
        var steps: [PhaseStep] = []

        func append(_ phase: BreathPhase, _ duration: Double, round: Int, breathIndex: Int? = nil) {
            guard duration > 0 else { return }          // skip zero-duration phases
            steps.append(PhaseStep(phase: phase, duration: duration, round: round, breathIndex: breathIndex))
        }

        for r in 1...s.rounds {
            // 1. Breath series — inhale → exhale, no holds between breaths.
            for b in 1...s.breathsPerRound {
                append(.inhale, s.inhaleSec, round: r, breathIndex: b)
                append(.exhale, s.exhaleSec, round: r, breathIndex: b)
            }
            // 2. Long exhale hold (duration depends on the round).
            append(.holdOut, s.holdOutByRound[r - 1], round: r)
            // 3. Recovery inhale, then hold on the inhale.
            append(.inhale, s.inhaleSec, round: r)
            append(.holdIn, s.recoveryHoldSec, round: r)
        }
        return steps
    }
}

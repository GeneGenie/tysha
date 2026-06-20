import SwiftUI

/// Screen 2 — the session. Full-screen shader background with readable overlays.
struct SessionView: View {
    let settings: BreathSettings
    let onExit: () -> Void

    @State private var engine = BreathEngine()

    var body: some View {
        ZStack {
            BreathShaderView(engine: engine)

            if engine.isFinished {
                finishedOverlay
            } else {
                sessionOverlay
            }
        }
        .statusBarHidden(true)
        .onAppear { engine.start(settings: settings) }
        .onDisappear { engine.stop() }
    }

    // MARK: Running overlay

    /// White breathing field scale: grows on inhale, shrinks on exhale during the
    /// breath series (continuous across phase boundaries: 0.7 ↔ 1.4).
    private var breathFieldScale: CGFloat {
        guard engine.isBreathSeries else { return 0.7 }
        switch engine.phase {
        case .inhale: return 0.7 + 0.7 * CGFloat(engine.phaseProgress)
        case .exhale: return 1.4 - 0.7 * CGFloat(engine.phaseProgress)
        default:      return 0.7
        }
    }

    private var sessionOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "\(L("session.round")) \(max(1, engine.currentRound))/\(engine.totalRounds)")
                        .font(.system(size: 26, weight: .semibold))
                    if engine.isBreathSeries {
                        Text(verbatim: "\(L("session.breath")) \(engine.breathIndex)/\(engine.breathsPerRound)")
                            .font(.system(size: 22))
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

                Spacer()

                Button(action: onExit) {
                    Text(L("session.exit"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .background(.ultraThinMaterial, in: Capsule())
            }
            .padding()

            Spacer()

            // Phase name + big "часики". Behind it, a soft white field breathes with the
            // session — expanding on inhale, contracting on exhale (during the series).
            ZStack {
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 240, height: 240)
                    .scaleEffect(breathFieldScale)
                    .blur(radius: 6)
                    .opacity(engine.isBreathSeries ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: engine.isBreathSeries)
                    .allowsHitTesting(false)

                VStack(spacing: 8) {
                    Text(engine.phase.title)
                        .font(.title2)
                        .fontWeight(.medium)
                    Text(engine.secondsText)
                        .font(.system(size: 76, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .padding(.vertical, 20)
                .containerRelativeFrame(.horizontal) { length, _ in length * 0.8 }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                .shadow(color: .black.opacity(0.4), radius: 10)
            }

            Spacer()

            Text(BreathSettings.warning)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .padding(10)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.bottom, 6)
        }
        .foregroundStyle(.white)
    }

    // MARK: Finished overlay

    private var finishedOverlay: some View {
        VStack(spacing: 24) {
            Text(L("session.done"))
                .font(.largeTitle)
                .fontWeight(.bold)

            Button(action: { engine.restart() }) {
                Text(L("session.again"))
                    .fontWeight(.semibold)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)

            Button(L("session.exit"), action: onExit)
                .buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
        .padding(40)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 24))
    }
}

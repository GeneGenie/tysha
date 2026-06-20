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

    private var sessionOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "\(L("session.round")) \(max(1, engine.currentRound))/\(engine.totalRounds)")
                        .font(.headline)
                    if engine.isBreathSeries {
                        Text(verbatim: "\(L("session.breath")) \(engine.breathIndex)/\(engine.breathsPerRound)")
                            .font(.subheadline)
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

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

            // Phase name + big "часики". Material backing + shadow keep it readable
            // even on the bright inhale flash. Width is fixed at 80% of the screen
            // so the capsule doesn't jump as the text changes.
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

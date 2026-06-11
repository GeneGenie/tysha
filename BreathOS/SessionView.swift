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
                    Text("Раунд \(max(1, engine.currentRound))/\(engine.totalRounds)")
                        .font(.headline)
                    if engine.isBreathSeries {
                        Text("Дыхание \(engine.breathIndex)/\(engine.breathsPerRound)")
                            .font(.subheadline)
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

                Spacer()

                Button(action: onExit) {
                    Text("Выход")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .background(.ultraThinMaterial, in: Capsule())
            }
            .padding()

            Spacer()

            // Phase name + big "часики". Material backing + shadow keep it readable
            // even on the bright inhale flash.
            VStack(spacing: 8) {
                Text(engine.phase.title)
                    .font(.title2)
                    .fontWeight(.medium)
                Text(engine.secondsText)
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
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
            Text("Готово")
                .font(.largeTitle)
                .fontWeight(.bold)

            Button(action: { engine.restart() }) {
                Text("Ещё раз")
                    .fontWeight(.semibold)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)

            Button("Выход", action: onExit)
                .buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
        .padding(40)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 24))
    }
}

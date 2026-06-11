import SwiftUI

/// Screen 1 — settings. All values persist between launches (handled by RootView).
struct SettingsView: View {
    @Binding var settings: BreathSettings
    let onStart: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Дыхание") {
                    sliderRow("Вдох (серия)",
                              value: $settings.inhaleSec,
                              range: BreathSettings.inhaleRange, step: 0.1, decimals: 1)
                    sliderRow("Выдох (серия)",
                              value: $settings.exhaleSec,
                              range: BreathSettings.exhaleRange, step: 0.1, decimals: 1)
                    Stepper(value: $settings.breathsPerRound,
                            in: BreathSettings.breathsRange, step: 1) {
                        valueLabel("Дыханий в раунде", "\(settings.breathsPerRound)")
                    }
                    sliderRow("Восстановительная задержка на вдохе",
                              value: $settings.recoveryHoldSec,
                              range: BreathSettings.recoveryRange, step: 1, decimals: 0, unit: "с")
                }

                Section("Раунды") {
                    Stepper(value: $settings.rounds,
                            in: BreathSettings.roundsRange, step: 1) {
                        valueLabel("Количество раундов", "\(settings.rounds)")
                    }
                    .onChange(of: settings.rounds) { _, newValue in
                        settings.holdOutByRound = BreathSettings.adjustedHoldOut(settings.holdOutByRound, to: newValue)
                    }
                }

                Section("Задержки на выдохе по раундам") {
                    ForEach(settings.holdOutByRound.indices, id: \.self) { i in
                        Stepper(value: $settings.holdOutByRound[i],
                                in: BreathSettings.holdOutRange, step: BreathSettings.holdOutStep) {
                            valueLabel("Раунд \(i + 1)", "\(Int(settings.holdOutByRound[i])) с")
                        }
                    }
                }

                Section {
                    Toggle("Звук", isOn: $settings.soundEnabled)
                    Toggle("Вибрация", isOn: $settings.hapticsEnabled)
                }

                Section {
                    Text(BreathSettings.warning)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Section {
                    Button(action: onStart) {
                        Text("Начать")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("BreathOS")
        }
    }

    // MARK: Row helpers

    @ViewBuilder
    private func sliderRow(_ title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           step: Double,
                           decimals: Int,
                           unit: String = "с") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            valueLabel(title, String(format: "%.\(decimals)f %@", value.wrappedValue, unit))
            Slider(value: value, in: range, step: step)
        }
    }

    private func valueLabel(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

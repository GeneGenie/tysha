import SwiftUI

/// Screen 1 — settings. All values persist between launches (handled by RootView).
struct SettingsView: View {
    @Binding var settings: BreathSettings
    let onStart: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(L("settings.section.breathing")) {
                    sliderRow(L("settings.inhale"),
                              value: $settings.inhaleSec,
                              range: BreathSettings.inhaleRange, step: 0.1, decimals: 1)
                    sliderRow(L("settings.exhale"),
                              value: $settings.exhaleSec,
                              range: BreathSettings.exhaleRange, step: 0.1, decimals: 1)
                    VStack(alignment: .leading, spacing: 4) {
                        valueLabel(L("settings.breathsPerRound"), "\(settings.breathsPerRound)")
                        Slider(
                            value: Binding(
                                get: { Double(settings.breathsPerRound) },
                                set: { settings.breathsPerRound = Int($0.rounded()) }
                            ),
                            in: Double(BreathSettings.breathsRange.lowerBound)...Double(BreathSettings.breathsRange.upperBound),
                            step: 1
                        )
                    }
                    sliderRow(L("settings.recoveryHold"),
                              value: $settings.recoveryHoldSec,
                              range: BreathSettings.recoveryRange, step: 1, decimals: 0)
                }

                Section(L("settings.section.rounds")) {
                    Stepper(value: $settings.rounds,
                            in: BreathSettings.roundsRange, step: 1) {
                        valueLabel(L("settings.rounds"), "\(settings.rounds)")
                    }
                    .onChange(of: settings.rounds) { _, newValue in
                        settings.holdOutByRound = BreathSettings.adjustedHoldOut(settings.holdOutByRound, to: newValue)
                    }
                }

                Section(L("settings.section.holdOut")) {
                    ForEach(settings.holdOutByRound.indices, id: \.self) { i in
                        Stepper(value: $settings.holdOutByRound[i],
                                in: BreathSettings.holdOutRange, step: BreathSettings.holdOutStep) {
                            valueLabel("\(L("settings.round")) \(i + 1)", "\(Int(settings.holdOutByRound[i])) \(L("unit.seconds"))")
                        }
                    }
                }

                Section {
                    Toggle(L("settings.sound"), isOn: $settings.soundEnabled)
                    VStack(alignment: .leading, spacing: 4) {
                        valueLabel(L("settings.breathVolume"), "\(Int((settings.breathVolume * 100).rounded())) %")
                        Slider(value: $settings.breathVolume, in: 0...1, step: 0.05)
                    }
                    .disabled(!settings.soundEnabled)
                    VStack(alignment: .leading, spacing: 4) {
                        valueLabel(L("settings.musicVolume"), "\(Int((settings.musicVolume * 100).rounded())) %")
                        Slider(value: $settings.musicVolume, in: 0...1, step: 0.05)
                    }
                    .disabled(!settings.soundEnabled)
                    Toggle(L("settings.haptics"), isOn: $settings.hapticsEnabled)
                }

                Section {
                    Text(BreathSettings.warning)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Section {
                    Button(action: onStart) {
                        Text(L("settings.start"))
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle(Text(verbatim: "Тиша"))
        }
    }

    // MARK: Row helpers

    @ViewBuilder
    private func sliderRow(_ title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           step: Double,
                           decimals: Int,
                           unit: String = L("unit.seconds")) -> some View {
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

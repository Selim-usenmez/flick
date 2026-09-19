import SwiftUI

struct GestureSettingsTab: View {
    let settings: GestureSettings

    var body: some View {
        Form {
            Section("Sensibilité") {
                sliderRow(
                    "Distance minimale de balayage",
                    value: Binding(get: { settings.minimumSwipeDistance }, set: { settings.minimumSwipeDistance = $0 }),
                    range: 20...150, step: 5, suffix: "pt"
                )
                sliderRow(
                    "Tolérance diagonale",
                    value: Binding(get: { settings.diagonalRatio }, set: { settings.diagonalRatio = $0 }),
                    range: 0.3...0.9, step: 0.05, suffix: ""
                )
                sliderRow(
                    "Seuil de pincement",
                    value: Binding(get: { settings.pinchThreshold }, set: { settings.pinchThreshold = $0 }),
                    range: 0.02...0.2, step: 0.01, suffix: ""
                )
            }

            Section("Orientation") {
                Toggle("Inverser horizontal", isOn: Binding(
                    get: { settings.invertHorizontal }, set: { settings.invertHorizontal = $0 }
                ))
                Toggle("Inverser vertical", isOn: Binding(
                    get: { settings.invertVertical }, set: { settings.invertVertical = $0 }
                ))
                Toggle("Inverser le pincement", isOn: Binding(
                    get: { settings.invertPinch }, set: { settings.invertPinch = $0 }
                ))
                Text("Inverse le sens des gestes si les directions te semblent à l'envers — ça dépend du réglage \"Défilement naturel\" du trackpad.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func sliderRow(
        _ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, step: CGFloat, suffix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(suffix.isEmpty ? String(format: "%.2f", value.wrappedValue) : "\(Int(value.wrappedValue)) \(suffix)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

#Preview {
    GestureSettingsTab(settings: GestureSettings())
        .frame(width: 460, height: 420)
}

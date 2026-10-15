import SwiftUI

struct GestureSettingsTab: View {
    let settings: GestureSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Gestes")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(FlickTheme.textPrimary)

                SettingsSection(title: "Sensibilité") {
                    sliderRow(
                        "Distance minimale de balayage",
                        value: Binding(get: { settings.minimumSwipeDistance }, set: { settings.minimumSwipeDistance = $0 }),
                        range: 20...150, step: 5, suffix: "pt",
                        showsDivider: true
                    )
                    sliderRow(
                        "Tolérance diagonale",
                        value: Binding(get: { settings.diagonalRatio }, set: { settings.diagonalRatio = $0 }),
                        range: 0.3...0.9, step: 0.05, suffix: "",
                        showsDivider: true
                    )
                    sliderRow(
                        "Seuil de pincement",
                        value: Binding(get: { settings.pinchThreshold }, set: { settings.pinchThreshold = $0 }),
                        range: 0.02...0.2, step: 0.01, suffix: "",
                        showsDivider: false
                    )
                }

                SettingsSection(title: "Zones de snap") {
                    sliderRow(
                        "Division gauche/droite",
                        value: Binding(get: { settings.horizontalSplitRatio }, set: { settings.horizontalSplitRatio = $0 }),
                        range: 0.25...0.75, step: 0.05, suffix: "",
                        showsDivider: true
                    )
                    sliderRow(
                        "Division haut/bas",
                        value: Binding(get: { settings.verticalSplitRatio }, set: { settings.verticalSplitRatio = $0 }),
                        range: 0.25...0.75, step: 0.05, suffix: "",
                        showsDivider: true
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Flick ajuste automatiquement ces proportions par app si tu corriges une fenêtre juste après un snap, plusieurs fois de suite.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(FlickTheme.textTertiary)
                        Button("Réinitialiser l'apprentissage par app") {
                            AdaptiveSnapZones.shared.resetAll()
                        }
                        .buttonStyle(.flickSecondary)
                    }
                    .cardRowPadding()
                }

                SettingsSection(title: "Orientation") {
                    orientationRow("Inverser horizontal", isOn: Binding(
                        get: { settings.invertHorizontal }, set: { settings.invertHorizontal = $0 }
                    ))
                    CardDivider()
                    orientationRow("Inverser vertical", isOn: Binding(
                        get: { settings.invertVertical }, set: { settings.invertVertical = $0 }
                    ))
                    CardDivider()
                    orientationRow("Inverser le pincement", isOn: Binding(
                        get: { settings.invertPinch }, set: { settings.invertPinch = $0 }
                    ))
                }
                Text("Inverse le sens des gestes si les directions te semblent à l'envers — ça dépend du réglage « Défilement naturel » du trackpad.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(FlickTheme.textTertiary)
                    .padding(.leading, 4)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private func sliderRow(
        _ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, step: CGFloat, suffix: String,
        showsDivider: Bool
    ) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.system(size: 13)).foregroundStyle(FlickTheme.textPrimary)
                    Spacer()
                    Text(suffix.isEmpty ? String(format: "%.2f", value.wrappedValue) : "\(Int(value.wrappedValue)) \(suffix)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FlickTheme.accent)
                        .monospacedDigit()
                }
                Slider(value: value, in: range, step: step)
                    .tint(FlickTheme.accent)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)
            if showsDivider { CardDivider() }
        }
    }

    private func orientationRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundStyle(FlickTheme.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.flick)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

#Preview {
    GestureSettingsTab(settings: GestureSettings())
        .frame(width: 460, height: 420)
        .background(FlickTheme.windowBackground)
}

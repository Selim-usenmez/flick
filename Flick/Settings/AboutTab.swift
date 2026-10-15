import AppKit
import Sparkle
import SwiftUI

struct AboutTab: View {
    let controller: FlickController

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: FlickTheme.accent.opacity(0.25), radius: 20, y: 14)
            VStack(spacing: 4) {
                Text("Flick")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(FlickTheme.textPrimary)
                Text("Version \(version) (\(build))")
                    .font(.system(size: 12))
                    .foregroundStyle(FlickTheme.textTertiary)
                    .monospacedDigit()
            }
            Text("Fenêtres et Dock au bout des doigts — des gestes trackpad pour ranger tes fenêtres et contrôler tes apps sans toucher la souris.")
                .font(.system(size: 13))
                .foregroundStyle(FlickTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            HStack(spacing: 8) {
                Button("Rechercher les mises à jour…") {
                    controller.updaterController.checkForUpdates(nil)
                }
                .buttonStyle(.flickSecondary)
                Button("Code source") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Selim-usenmez/flick")!)
                }
                .buttonStyle(.flickSecondary)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
    }
}

#Preview {
    AboutTab(controller: FlickController())
        .frame(width: 460, height: 420)
        .background(FlickTheme.windowBackground)
}

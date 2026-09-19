import SwiftUI

/// First-launch welcome tour: what Flick does, the gesture map, and the two things it needs
/// from the user (launch at login, Accessibility) to actually work.
struct OnboardingView: View {
    let controller: FlickController
    let onFinish: () -> Void

    @State private var pageIndex = 0
    private let lastPageIndex = 3

    var body: some View {
        VStack(spacing: 20) {
            currentPage
                .id(pageIndex)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(32)
        .frame(width: 640, height: 460)
    }

    @ViewBuilder
    private var currentPage: some View {
        switch pageIndex {
        case 0: welcomePage
        case 1: gesturesPage
        case 2: launchAtLoginPage
        default: permissionPage
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Précédent") { withAnimation { pageIndex -= 1 } }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(pageIndex > 0 ? 1 : 0)
                .disabled(pageIndex == 0)

            Spacer()
            pageDots
            Spacer()

            Button(pageIndex == lastPageIndex ? "Commencer" : "Continuer") {
                if pageIndex == lastPageIndex {
                    onFinish()
                } else {
                    withAnimation { pageIndex += 1 }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0...lastPageIndex, id: \.self) { index in
                Circle()
                    .fill(index == pageIndex ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Bienvenue sur Flick")
                .font(.largeTitle.weight(.bold))
            Text("Range tes fenêtres, contrôle le Dock et pilote tes apps d'un geste sur le trackpad — sans lâcher le clavier.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
    }

    private var gesturesPage: some View {
        VStack(spacing: 8) {
            Text("Un geste, une action")
                .font(.title2.weight(.semibold))
            Text("Balaie depuis la barre de titre d'une fenêtre ou une icône du Dock.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                GestureCheatSheetView(compact: true)
                    .frame(maxWidth: 460)
            }
        }
    }

    private var launchAtLoginPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "power")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Toujours prêt")
                .font(.title.weight(.semibold))
            Text("Lance Flick automatiquement à chaque démarrage de ton Mac, pour ne plus avoir à y penser.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Toggle("Lancer Flick au démarrage du Mac", isOn: Binding(
                get: { controller.launchAtLogin.status != .disabled },
                set: { controller.launchAtLogin.setEnabled($0) }
            ))
            .toggleStyle(.switch)
        }
    }

    private var permissionPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Dernière étape")
                .font(.title.weight(.semibold))
            Text("Flick a besoin de l'accès Accessibilité pour lire tes gestes et déplacer tes fenêtres.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if controller.accessibilityPermission.isTrusted {
                Label("Accessibilité autorisée", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Autoriser l'accessibilité…") {
                    controller.accessibilityPermission.requestAuthorization()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

#Preview {
    OnboardingView(controller: FlickController()) {}
}

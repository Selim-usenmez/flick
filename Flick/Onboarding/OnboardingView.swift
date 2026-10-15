import AppKit
import SwiftUI

/// First-launch welcome tour: what Flick does, the gesture map, and the two things it needs
/// from the user (launch at login, Accessibility) to actually work.
struct OnboardingView: View {
    let controller: FlickController
    let onFinish: () -> Void

    @State private var pageIndex = 0
    private let lastPageIndex = 3

    var body: some View {
        VStack(spacing: 0) {
            currentPage
                .id(pageIndex)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 48)
            footer
        }
        .frame(width: 640, height: 460)
        .background(FlickTheme.windowBackground)
        .preferredColorScheme(.dark)
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
        Grid {
            GridRow {
                Button("Précédent") { withAnimation(FlickTheme.spring) { pageIndex -= 1 } }
                    .buttonStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(FlickTheme.textSecondary)
                    .opacity(pageIndex > 0 ? 1 : 0)
                    .disabled(pageIndex == 0)
                    .gridColumnAlignment(.leading)

                pageDots
                    .gridColumnAlignment(.center)

                HStack {
                    Spacer()
                    Button(pageIndex == lastPageIndex ? "Commencer" : "Continuer") {
                        if pageIndex == lastPageIndex {
                            onFinish()
                        } else {
                            withAnimation(FlickTheme.spring) { pageIndex += 1 }
                        }
                    }
                    .buttonStyle(.flickPrimary)
                    .keyboardShortcut(.defaultAction)
                }
                .gridColumnAlignment(.trailing)
            }
        }
        .frame(height: 68)
        .padding(.horizontal, 24)
        .overlay(alignment: .top) { CardDivider() }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0...lastPageIndex, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(index == pageIndex ? FlickTheme.accent : Color.white.opacity(0.18))
                    .frame(width: index == pageIndex ? 18 : 6, height: 6)
                    .animation(FlickTheme.spring, value: pageIndex)
            }
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 23))
                .shadow(color: FlickTheme.accent.opacity(0.3), radius: 25, y: 18)
            Text("Bienvenue sur Flick")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(FlickTheme.textPrimary)
            Text("Range tes fenêtres, contrôle le Dock et pilote tes apps d'un geste sur le trackpad — sans lâcher le clavier.")
                .font(.system(size: 16))
                .foregroundStyle(FlickTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(
                colors: [FlickTheme.accent.opacity(0.16), .clear],
                center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 260
            )
        )
    }

    private var gesturesPage: some View {
        VStack(spacing: 6) {
            Text("Un geste, une action")
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(FlickTheme.textPrimary)
            Text("Balaie depuis la barre de titre d'une fenêtre ou une icône du Dock.")
                .font(.system(size: 13))
                .foregroundStyle(FlickTheme.textSecondary)
                .padding(.bottom, 10)
            HStack(spacing: 24) {
                gestureColumn(title: "Barre de titre", grid: .title) {
                    Label {
                        Text("Pincer fermé")
                    } icon: {
                        Image("fermer").resizable().scaledToFit().frame(width: 10, height: 10)
                    }
                    Text("·").foregroundStyle(Color(hex: 0x55555B))
                    Label {
                        Text("Pincer ouvert")
                    } icon: {
                        Image("agrandir").resizable().scaledToFit().frame(width: 10, height: 10)
                    }
                }
                gestureColumn(title: "Icône du Dock", grid: .dock) {
                    Text("Pincer fermé = minimiser · ouvert = ⌘N")
                }
            }
        }
    }

    @ViewBuilder
    private func gestureColumn(
        title: String, grid: GestureGrid, @ViewBuilder caption: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(FlickTheme.textSecondary)
            GestureGridView(grid: grid, style: .large)
                .frame(width: 250)
            HStack(spacing: 6) {
                caption()
            }
            .font(.system(size: 11))
            .foregroundStyle(FlickTheme.textSecondary)
        }
    }

    private var launchAtLoginPage: some View {
        VStack(spacing: 12) {
            Text("ÉTAPE 3 SUR 4")
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(FlickTheme.accent)
            Text("Toujours prêt")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(FlickTheme.textPrimary)
            Text("Lance Flick automatiquement à chaque démarrage de ton Mac, pour ne plus avoir à y penser.")
                .font(.system(size: 15))
                .foregroundStyle(FlickTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .padding(.bottom, 2)

            SettingsCard {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lancer Flick au démarrage du Mac")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(FlickTheme.textPrimary)
                        Text("Ouverture à la connexion")
                            .font(.system(size: 12))
                            .foregroundStyle(FlickTheme.textTertiary)
                    }
                    Toggle("", isOn: Binding(
                        get: { controller.launchAtLogin.status != .disabled },
                        set: { controller.launchAtLogin.setEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.flick)
                }
                .cardRowPadding()
            }
            .frame(maxWidth: 400)
        }
    }

    private var permissionPage: some View {
        VStack(spacing: 12) {
            Text("DERNIÈRE ÉTAPE")
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(FlickTheme.accent)
            Text("Autorise l'accessibilité")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(FlickTheme.textPrimary)
            Text("Flick a besoin de l'accès Accessibilité pour lire tes gestes et déplacer tes fenêtres.")
                .font(.system(size: 15))
                .foregroundStyle(FlickTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.bottom, 2)

            if controller.accessibilityPermission.isTrusted {
                HStack(spacing: 10) {
                    Circle()
                        .fill(FlickTheme.success)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(FlickTheme.windowBackground)
                        )
                    Text("Accessibilité autorisée")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FlickTheme.success)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: 400)
                .background(FlickTheme.success.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(FlickTheme.success.opacity(0.3)))
            } else {
                VStack(spacing: 10) {
                    Button("Autoriser l'accessibilité…") {
                        controller.accessibilityPermission.requestAuthorization()
                    }
                    .buttonStyle(.flickPrimary)
                    // macOS only shows the system prompt once — if it was already dismissed
                    // or denied, this is the only way back in without hunting for the panel.
                    Button("Ouvrir Réglages Système…") {
                        controller.accessibilityPermission.openSystemSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(FlickTheme.textSecondary)
                }
            }
        }
    }
}

#Preview {
    OnboardingView(controller: FlickController()) {}
}

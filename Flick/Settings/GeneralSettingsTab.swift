import SwiftUI

struct GeneralSettingsTab: View {
    let controller: FlickController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Général")
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(FlickTheme.textPrimary)

            SettingsSection(title: "État") {
                HStack {
                    Text("Activé").font(.system(size: 13)).foregroundStyle(FlickTheme.textPrimary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { controller.isEnabled },
                        set: { controller.setEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.flick)
                    .disabled(!controller.accessibilityPermission.isTrusted)
                }
                .cardRowPadding()

                CardDivider()

                HStack {
                    Text("Relancer Flick").font(.system(size: 13)).foregroundStyle(FlickTheme.textPrimary)
                    Spacer()
                    Button("↻ Relancer") { AppRelauncher.relaunch() }
                        .buttonStyle(.flickSecondary)
                }
                .cardRowPadding()
            }

            SettingsSection(title: "Permissions") {
                if controller.accessibilityPermission.isTrusted {
                    HStack(spacing: 8) {
                        Circle().fill(FlickTheme.success).frame(width: 8, height: 8)
                        Text("Accessibilité autorisée")
                            .font(.system(size: 13))
                            .foregroundStyle(FlickTheme.textPrimary)
                        Spacer()
                    }
                    .cardRowPadding()
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            HStack(spacing: 8) {
                                Circle().fill(FlickTheme.warning).frame(width: 8, height: 8)
                                Text("Accessibilité non autorisée")
                                    .font(.system(size: 13))
                                    .foregroundStyle(FlickTheme.textPrimary)
                            }
                            Spacer()
                            Button("Autoriser…") {
                                controller.accessibilityPermission.requestAuthorization()
                            }
                            .buttonStyle(.flickPrimary)
                            .font(.system(size: 12, weight: .semibold))
                        }
                        .cardRowPadding()

                        Button("Ouvrir Réglages Système…") {
                            controller.accessibilityPermission.openSystemSettings()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(FlickTheme.accent)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            SettingsSection(title: "Démarrage") {
                VStack(spacing: 0) {
                    HStack {
                        Text("Lancer Flick au démarrage du Mac")
                            .font(.system(size: 13))
                            .foregroundStyle(FlickTheme.textPrimary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { controller.launchAtLogin.status != .disabled },
                            set: { controller.launchAtLogin.setEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.flick)
                    }
                    .cardRowPadding()

                    if controller.launchAtLogin.status == .requiresApproval {
                        CardDivider()
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Circle().fill(FlickTheme.warning).frame(width: 8, height: 8)
                                Text("Approbation requise dans Réglages Système")
                                    .font(.system(size: 12))
                                    .foregroundStyle(FlickTheme.textPrimary)
                            }
                            Button("Ouvrir Réglages Système…") {
                                controller.launchAtLogin.openSystemSettings()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(FlickTheme.accent)
                        }
                        .cardRowPadding()
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

#Preview {
    GeneralSettingsTab(controller: FlickController())
        .frame(width: 460, height: 420)
        .background(FlickTheme.windowBackground)
}

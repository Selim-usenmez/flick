import SwiftUI

/// Shared design tokens for the 2026 Flick restyle — one dark, single-accent visual
/// language reused by every window, panel, and menu. Values (colors, radii, spring) come
/// straight from the design handoff and are treated as fixed, not approximate.
enum FlickTheme {
    // MARK: - Surfaces
    static let windowBackground = Color(hex: 0x1C1C1F)
    static let sidebarBackground = Color(hex: 0x161618)
    static let cardBackground = Color(hex: 0x26262A)
    static let tileBackground = Color(hex: 0x28282C)

    // MARK: - Text
    static let textPrimary = Color(hex: 0xF2F2F3)
    static let textSecondary = Color(hex: 0x9A9AA1)
    static let textTertiary = Color(hex: 0x8A8A91)
    static let textQuaternary = Color(hex: 0x6B6B72)
    /// Muted label color used inside gesture-grid tiles (large/medium sizes only).
    static let gridLabel = Color(hex: 0xB8B8BE)

    // MARK: - Accent & status
    static let accent = Color(hex: 0x0A84FF)
    static let accentText = Color(hex: 0x5EB0FF)
    static let success = Color(hex: 0x30D158)
    static let warning = Color(hex: 0xFF9F0A)
    static let error = Color(hex: 0xFF453A)
    static let snap = Color(hex: 0x4AA3FF)

    // MARK: - Borders
    static let cardBorder = Color.white.opacity(0.06)
    static let windowBorder = Color.white.opacity(0.10)

    // MARK: - Motion
    static let spring = Animation.spring(response: 0.25, dampingFraction: 0.75)

    // MARK: - Radii
    static let windowCornerRadius: CGFloat = 12
    static let hudCornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 10
    static let buttonCornerRadius: CGFloat = 9
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Toggle

/// The pill switch used throughout the restyle: accent when on, white 16% when off, with
/// a white thumb that slides under a 0.15s linear transition — same recipe everywhere
/// (Onboarding, Réglages, menu bar), just two sizes.
struct FlickToggleStyle: ToggleStyle {
    enum Size: Equatable {
        case regular, small

        var width: CGFloat { self == .regular ? 38 : 34 }
        var height: CGFloat { self == .regular ? 22 : 20 }
        var thumbDiameter: CGFloat { self == .regular ? 18 : 16 }
    }

    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 8)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: size.height / 2)
                    .fill(configuration.isOn ? FlickTheme.accent : Color.white.opacity(0.16))
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    .padding(2)
                    .frame(width: size.thumbDiameter, height: size.thumbDiameter)
            }
            .frame(width: size.width, height: size.height)
            .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
        }
    }
}

extension ToggleStyle where Self == FlickToggleStyle {
    static var flick: FlickToggleStyle { FlickToggleStyle() }
    static func flick(_ size: FlickToggleStyle.Size) -> FlickToggleStyle { FlickToggleStyle(size: size) }
}

// MARK: - Buttons

/// Three button looks shared across every restyled screen: accent-filled primary, flat
/// gray secondary, and a translucent white "subtle" pill (HUD footer).
struct FlickButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, subtle }

    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: kind == .subtle ? .infinity : nil)
            .background(background, in: RoundedRectangle(cornerRadius: cornerRadius))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }

    private var font: Font {
        switch kind {
        case .primary: return .system(size: 14, weight: .semibold)
        case .secondary: return .system(size: 12, weight: .medium)
        case .subtle: return .system(size: 12, weight: .medium)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary, .subtle: return FlickTheme.textPrimary
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return FlickTheme.accent
        case .secondary: return Color(hex: 0x38383D)
        case .subtle: return Color.white.opacity(0.08)
        }
    }

    private var horizontalPadding: CGFloat {
        switch kind {
        case .primary: return 20
        case .secondary: return 12
        case .subtle: return 0
        }
    }

    private var verticalPadding: CGFloat {
        switch kind {
        case .primary: return 9
        case .secondary: return 6
        case .subtle: return 7
        }
    }

    private var cornerRadius: CGFloat {
        switch kind {
        case .primary: return FlickTheme.buttonCornerRadius
        case .secondary: return 7
        case .subtle: return 8
        }
    }
}

extension ButtonStyle where Self == FlickButtonStyle {
    static var flickPrimary: FlickButtonStyle { FlickButtonStyle(kind: .primary) }
    static var flickSecondary: FlickButtonStyle { FlickButtonStyle(kind: .secondary) }
    static var flickSubtle: FlickButtonStyle { FlickButtonStyle(kind: .subtle) }
}

// MARK: - Settings cards

/// A grouped-card container (rounded rect, `cardBackground`, 6% border) — the base unit
/// every Réglages section is built from.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(FlickTheme.cardBackground, in: RoundedRectangle(cornerRadius: FlickTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: FlickTheme.cardCornerRadius)
                    .strokeBorder(FlickTheme.cardBorder)
            )
    }
}

/// A tertiary, uppercase section label above a `SettingsCard` — "État", "Permissions", etc.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlickTheme.textTertiary)
                .padding(.leading, 4)
            SettingsCard { content }
        }
    }
}

/// A 1pt hairline matching the card's own border color, used between stacked rows inside
/// a `SettingsCard`.
struct CardDivider: View {
    var body: some View {
        Rectangle().fill(FlickTheme.cardBorder).frame(height: 1)
    }
}

extension View {
    /// Standard row padding inside a `SettingsCard` (11×14, per the handoff).
    func cardRowPadding() -> some View {
        padding(.horizontal, 14).padding(.vertical, 11)
    }
}

// MARK: - Status pill

/// A small colored capsule with a status dot — "Surveillance active", menu bar status,
/// etc. Fill is the status color at 14% opacity.
struct StatusPill: View {
    let isOn: Bool
    let onLabel: String
    let offLabel: String

    var body: some View {
        let color = isOn ? FlickTheme.success : FlickTheme.error
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(isOn ? onLabel : offLabel)
                .font(.system(size: 11.5, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.leading, 7)
        .padding(.trailing, 9)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }
}

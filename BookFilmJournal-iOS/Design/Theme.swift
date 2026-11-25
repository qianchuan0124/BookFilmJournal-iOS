import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { trait in
            UIColor(hexValue: trait.userInterfaceStyle == .dark ? dark : light)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hexValue: isDark ? dark : light)
        })
        #else
        return Color(hex: light)
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hexValue: UInt32) {
        self.init(
            red: CGFloat((hexValue >> 16) & 0xFF) / 255,
            green: CGFloat((hexValue >> 8) & 0xFF) / 255,
            blue: CGFloat(hexValue & 0xFF) / 255,
            alpha: 1
        )
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(hexValue: UInt32) {
        self.init(
            srgbRed: CGFloat((hexValue >> 16) & 0xFF) / 255,
            green: CGFloat((hexValue >> 8) & 0xFF) / 255,
            blue: CGFloat(hexValue & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

enum Theme {
    static let bg = Color.adaptive(light: 0xF7F3EA, dark: 0x12161F)
    static let surface = Color.adaptive(light: 0xFFFCF6, dark: 0x1A1F2A)
    static let surface2 = Color.adaptive(light: 0xFBF7EF, dark: 0x1F2430)
    static let subtle = Color.adaptive(light: 0xF2ECE1, dark: 0x232935)
    static let track = Color.adaptive(light: 0xEBE4D8, dark: 0x2C3341)
    static let border = Color.adaptive(light: 0xE7DFD2, dark: 0x2A3140)
    static let borderStrong = Color.adaptive(light: 0xD9CFBE, dark: 0x374055)

    static let text = Color.adaptive(light: 0x211E18, dark: 0xF2EBDD)
    static let text2 = Color.adaptive(light: 0x5E574A, dark: 0xC3BBA9)
    static let text3 = Color.adaptive(light: 0x8B8273, dark: 0x8E94A3)
    static let text4 = Color.adaptive(light: 0xB0A695, dark: 0x697080)

    static let gold = Color.adaptive(light: 0x9A6211, dark: 0xE9BE70)
    static let goldDeep = Color.adaptive(light: 0x7C4D08, dark: 0xF4D495)
    static let goldSoft = Color.adaptive(light: 0xF9ECD2, dark: 0x30291A)
    static let goldBorder = Color.adaptive(light: 0xE7CFA2, dark: 0x554727)
    static let goldBright = Color.adaptive(light: 0xE8B65C, dark: 0xE9BE70)

    static let teal = Color.adaptive(light: 0x2E8775, dark: 0x5CBBA7)
    static let read = Color.adaptive(light: 0x688A4A, dark: 0x94C477)
    static let readSoft = Color.adaptive(light: 0xEDF2E3, dark: 0x28321E)
    static let wish = Color.adaptive(light: 0xB86F30, dark: 0xE2A46C)
    static let wishSoft = Color.adaptive(light: 0xF9EEE3, dark: 0x392A1B)
    static let danger = Color.adaptive(light: 0xC54949, dark: 0xFF7F87)
    static let dangerSoft = Color.adaptive(light: 0xFBEDEC, dark: 0x39222A)
    static let star = Color.adaptive(light: 0xD89A2A, dark: 0xE9BE70)

    static let nav = Color.adaptive(light: 0xFDFAF3, dark: 0x171C26)
    static let sheet = Color.adaptive(light: 0xF8F4EC, dark: 0x1A1F29)
    static let tabBar = Color.adaptive(light: 0xFDFAF3, dark: 0x1A1F2A)

    static let reportBG = Color(hex: 0x0F1117)
    static let reportCard = Color(hex: 0x1A1C21)
    static let reportLine = Color(hex: 0x2D2B26)
    static let reportText = Color(hex: 0xF0E8D7)
    static let reportGold = Color(hex: 0xE9BE70)
    static let reportMuted = Color(hex: 0x8C8573)

    static let scrim = Color.black.opacity(0.45)
}

extension Font {
    static let appDisplay = Font.system(size: 30, weight: .bold)
    static let appH1 = Font.system(size: 21, weight: .semibold)
    static let appNav = Font.system(size: 17, weight: .semibold)
    static let appTitle = Font.system(size: 16, weight: .semibold)
    static let appBody = Font.system(size: 16, weight: .regular)
    static let appBodyMedium = Font.system(size: 16, weight: .medium)
    static let appBodySmall = Font.system(size: 14, weight: .regular)
    static let appCaption = Font.system(size: 12.5, weight: .regular)
    static let appCaptionMedium = Font.system(size: 12.5, weight: .semibold)
    static let appMicro = Font.system(size: 10.5, weight: .semibold)
    static let appButton = Font.system(size: 16, weight: .semibold)
    static let appButtonSmall = Font.system(size: 14, weight: .semibold)
    static let appSerifTitle = Font.system(size: 12.5, weight: .semibold, design: .serif)
    static let appSerifLarge = Font.system(size: 17, weight: .semibold, design: .serif)
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: L10n.Theme.system
        case .light: L10n.Theme.light
        case .dark: L10n.Theme.dark
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension View {
    func appScreen() -> some View {
        self
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .background(Theme.bg.ignoresSafeArea())
    }

    func cardSurface(radius: CGFloat = 14) -> some View {
        self
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

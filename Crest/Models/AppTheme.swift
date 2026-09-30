import SwiftUI

/// 用户可选择的应用外观模式。
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "app.theme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            AppLocalization.string("跟随系统")
        case .light:
            AppLocalization.string("浅色")
        case .dark:
            AppLocalization.string("深色")
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            "circle.lefthalf.filled"
        case .light:
            "sun.max"
        case .dark:
            "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

/// 全局语义色板，颜色会随当前深浅色模式自动切换。
enum AppColors {
    static let background = adaptive(light: 0xFFFFFF, dark: 0x212121)
    static let sidebarBackground = adaptive(light: 0xF9F9F9, dark: 0x171717)
    static let surface = adaptive(light: 0xFAFAFA, dark: 0x2F2F2F)
    static let primaryText = adaptive(light: 0x0D0D0D, dark: 0xECECEC)
    static let secondaryText = adaptive(light: 0x5D5D5D, dark: 0xB4B4B4)
    static let tertiaryText = adaptive(light: 0x8F8F8F, dark: 0x8F8F8F)
    static let border = adaptive(light: 0xE5E5E5, dark: 0x424242)
    static let inputBackground = adaptive(light: 0xFFFFFF, dark: 0x303030)
    static let primaryButton = adaptive(light: 0x0D0D0D, dark: 0xFFFFFF)
    static let buttonText = adaptive(light: 0xFFFFFF, dark: 0x0D0D0D)
    static let chatSendButton = adaptive(light: 0x0285FF, dark: 0x0A84FF)
    static let chatSendButtonText = Color.white

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(from: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func uiColor(from hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// 保存真正的系统主题，避免弹窗读取到应用强制覆盖后的主题。
private struct SystemColorSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme = .light
}

extension EnvironmentValues {
    var systemColorScheme: ColorScheme {
        get { self[SystemColorSchemeKey.self] }
        set { self[SystemColorSchemeKey.self] = newValue }
    }
}

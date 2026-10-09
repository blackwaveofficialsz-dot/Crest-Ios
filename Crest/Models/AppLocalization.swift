import Foundation

/// 用户可选择的应用语言。跟随系统时不覆盖设备语言偏好。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let storageKey = "app.language"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            AppLocalization.string("跟随系统")
        case .simplifiedChinese:
            AppLocalization.string("简体中文")
        case .english:
            AppLocalization.string("English")
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            "globe"
        case .simplifiedChinese:
            "character.book.closed"
        case .english:
            "textformat"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            Locale(identifier: Locale.preferredLanguages.first ?? Locale.autoupdatingCurrent.identifier)
        case .simplifiedChinese:
            Locale(identifier: "zh-Hans")
        case .english:
            Locale(identifier: "en")
        }
    }
}

/// 非 SwiftUI 字面量文案统一通过这里读取，确保动态提示也服从应用语言设置。
enum AppLocalization {
    static var language: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
            ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: rawValue) ?? .system
    }

    static var locale: Locale {
        language.locale
    }

    static func string(_ key: String) -> String {
        let localization = locale.identifier.lowercased().hasPrefix("zh") ? "zh-Hans" : "en"
        let bundle = Bundle.main.path(forResource: localization, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: locale,
            arguments: arguments
        )
    }
}

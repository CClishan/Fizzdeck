import Foundation
import Observation
import os

enum FizzLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case chinese = "zh-Hans"
    case english = "en"

    static let key = "fizzdeck.language"
    var id: Self { self }

    var title: String {
        switch self {
        case .system: FizzL10n.text("跟随系统", "Follow System")
        case .chinese: "简体中文"
        case .english: "English"
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .system
    }

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> Self {
        guard self == .system else { return self }
        for tag in preferredLanguages {
            switch Locale(identifier: tag).language.languageCode {
            case .chinese: return .chinese
            case .english: return .english
            default: continue
            }
        }
        return .english
    }
}

/// Views observe one resolved choice. Background builders can read it without consulting defaults for every label.
private final class FizzLanguageState: Observable, Sendable {
    private let registrar = ObservationRegistrar()
    private let value = OSAllocatedUnfairLock(initialState: FizzLanguage.stored().resolved())

    var language: FizzLanguage {
        registrar.access(self, keyPath: \.language)
        return value.withLock { $0 }
    }

    func update(_ language: FizzLanguage) {
        guard value.withLock({ $0 != language }) else { return }
        registrar.withMutation(of: self, keyPath: \.language) { value.withLock { $0 = language } }
    }
}

enum FizzL10n {
    private static let state = FizzLanguageState()
    @TaskLocal static var languageOverride: FizzLanguage?

    static var language: FizzLanguage { languageOverride?.resolved() ?? state.language }
    static var isEnglish: Bool { language == .english }
    static var locale: Locale { isEnglish ? Locale(identifier: "en_US") : Locale(identifier: "zh_Hans_CN") }

    static func use(_ preference: FizzLanguage) { state.update(preference.resolved()) }

    static func text(_ chinese: @autoclosure () -> String, _ english: @autoclosure () -> String) -> String {
        isEnglish ? english() : chinese()
    }
}

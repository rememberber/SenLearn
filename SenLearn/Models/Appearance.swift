import SwiftUI
import Combine

enum AppTheme: String, CaseIterable, Identifiable {
    case forest, native, play, night

    var id: String { rawValue }

    var name: String {
        switch self {
        case .forest: "森间书桌"
        case .native: "清透原生"
        case .play: "探索乐园"
        case .night: "月光共读"
        }
    }

    var subtitle: String {
        switch self {
        case .forest: "温暖纸白，陪伴每一次发现"
        case .native: "轻盈清晰，让阅读井井有条"
        case .play: "一点好奇，一起探索"
        case .night: "安静的色彩，慢慢读给你听"
        }
    }

    var background: Color {
        switch self {
        case .forest: Color(hex: 0xF7F5ED)
        case .native: Color(hex: 0xF3F5F8)
        case .play: Color(hex: 0xFFF8E8)
        case .night: Color(hex: 0x17262D)
        }
    }

    var surface: Color {
        switch self {
        case .forest: Color(hex: 0xFFFDF8)
        case .native: .white
        case .play: Color(hex: 0xFFFCF4)
        case .night: Color(hex: 0x233840)
        }
    }

    var ink: Color {
        switch self {
        case .forest: Color(hex: 0x243B32)
        case .native: Color(hex: 0x202833)
        case .play: Color(hex: 0x423426)
        case .night: Color(hex: 0xE8EDE7)
        }
    }

    var accent: Color {
        switch self {
        case .forest: Color(hex: 0x2C6250)
        case .native: Color(hex: 0x2563EB)
        case .play: Color(hex: 0x9E3F2C)
        case .night: Color(hex: 0xB6DCCE)
        }
    }

    var softAccent: Color {
        switch self {
        case .forest: Color(hex: 0xDCE8DC)
        case .native: Color(hex: 0xE3EDFF)
        case .play: Color(hex: 0xF5C75A)
        case .night: Color(hex: 0x35594F)
        }
    }

    var onAccent: Color { self == .night ? Color(hex: 0x17262D) : .white }

    var radius: CGFloat {
        switch self {
        case .forest: 20
        case .native: 14
        case .play: 24
        case .night: 18
        }
    }
}

@MainActor
final class AppearanceSettings: ObservableObject {
    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: "appearance.theme") }
    }
    @Published var reduceMotion: Bool {
        didSet { defaults.set(reduceMotion, forKey: "appearance.reduceMotion") }
    }
    @Published var parentPanel: Bool {
        didSet { defaults.set(parentPanel, forKey: "appearance.parentPanel") }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.string(forKey: "appearance.theme").flatMap(AppTheme.init(rawValue:)) ?? .forest
        reduceMotion = defaults.bool(forKey: "appearance.reduceMotion")
        parentPanel = defaults.bool(forKey: "appearance.parentPanel")
    }

    func resetTheme() {
        theme = .forest
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

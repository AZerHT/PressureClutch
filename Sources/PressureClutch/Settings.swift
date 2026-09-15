import Foundation

/// How much harder a press has to be to slow the pointer down, with the pressure trigger.
enum Sensitivity: String, CaseIterable {
    case light, normal, firm

    var title: String {
        switch self {
        case .light: return "Légère"
        case .normal: return "Normale"
        case .firm: return "Ferme"
        }
    }

    /// Force to add above the drag's lightest moment. Measured on a MacBook Pro trackpad: a drag is held at
    /// 120–400, and a deliberate press adds anywhere from 120 to 500 on top.
    var riseToEngage: Float {
        switch self {
        case .light: return 70
        case .normal: return 100
        case .firm: return 160
        }
    }
}

/// User settings, kept in UserDefaults.
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    var trigger: ClutchTap.Trigger {
        get { defaults.string(forKey: "trigger").flatMap(ClutchTap.Trigger.init(rawValue:)) ?? .function }
        set { defaults.set(newValue.rawValue, forKey: "trigger") }
    }

    var sensitivity: Sensitivity {
        get { defaults.string(forKey: "sensitivity").flatMap(Sensitivity.init(rawValue:)) ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: "sensitivity") }
    }

    /// How many times slower the pointer goes while slowed down, from 2 to 20.
    var slowdown: Double {
        get {
            let value = defaults.double(forKey: "slowdown")
            return value >= 2 && value <= 20 ? value : 10
        }
        set { defaults.set(min(20, max(2, newValue)), forKey: "slowdown") }
    }

    var clutchConfig: ClutchTap.Config {
        ClutchTap.Config(enabled: enabled, trigger: trigger, riseToEngage: sensitivity.riseToEngage, gain: 1 / slowdown)
    }
}

import Foundation

enum SharedContainerGroup {
    static var name: String {
        #if F_DEV
            return "group.pcf.polkadotapp.develop"
        #else
            return "group.pcf.polkadotapp"
        #endif
    }

    static var userDefaults: UserDefaults {
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("Failed to create UserDefaults for suite: \(name)")
        }
        return defaults
    }
}

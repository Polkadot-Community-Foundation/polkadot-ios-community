/// Products that still speak the legacy wire, so they run on the native host even when the
/// TrUAPI core is on. Get CASH is also opened by production builds, which only carry the native host.
enum LegacyRuntimeProducts {
    private static let names: Set<String> = ["getcash"]

    /// `productName` is the dotNS name without its TLD (`ProductHost.name`).
    static func runsNative(productName: String) -> Bool {
        names.contains(productName)
    }
}

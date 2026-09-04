import SwiftUI
import DesignSystem
import PolkadotUI

/// Stand-in content for the trailing action until it gets a real panel.
enum TabBarPanelPlaceholderContent {
    static func make() -> any HashableContentConfiguration {
        SwiftUIContentConfiguration(view: TabBarPanelPlaceholderView())
    }
}

private struct TabBarPanelPlaceholderView: View, Hashable {
    var body: some View {
        Text(String(localized: .tabMore))
            .font(.headline)
            .foregroundStyle(Color.fgSecondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}

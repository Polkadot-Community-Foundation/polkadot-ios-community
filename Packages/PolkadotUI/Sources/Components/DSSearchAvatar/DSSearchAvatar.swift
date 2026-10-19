import DesignSystem
import SwiftUI

/// Search result avatar: a 40 pt circle with the contact's image, or its initial in the R1 search type.
public struct DSSearchAvatar: View, Equatable {
    public static let dimension: CGFloat = 40

    private let viewModel: AvatarViewModel

    public init(viewModel: AvatarViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if let image = viewModel.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: Self.dimension, height: Self.dimension)
                .clipShape(Circle())
        } else {
            Text(viewModel.text ?? "")
                .font(DSTabBarStyle.SearchTypography.avatarInitial)
                .foregroundStyle(viewModel.textColor.map { Color($0) } ?? .avatarFgAmethyst)
                .lineLimit(1)
                .frame(width: Self.dimension, height: Self.dimension)
                .background(viewModel.backgroundColor.map { Color($0) } ?? .avatarBgAmethyst, in: Circle())
        }
    }
}

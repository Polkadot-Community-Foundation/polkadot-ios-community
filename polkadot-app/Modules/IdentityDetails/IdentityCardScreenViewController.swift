import DesignSystem
import PolkadotUI
import SnapKit
import SwiftUI
import UIKit
import UIKitExt

/// The native identity card opened onto a screen of its own, pushed on the Wallet stack above the Pocket: the card,
/// the username to copy and the QR code, with Share in the navigation bar.
///
/// The scene stays with the Wallet. While this screen is up it presents the scene's copy toast and share sheet.
final class IdentityCardScreenViewController: UIViewController {
    private let scene: IdentityDetailsScene
    private weak var pocket: ControllerBackedProtocol?
    private lazy var hosting = UIHostingController(rootView: IdentityCardScreenRoot(viewModel: scene.viewModel))

    init(scene: IdentityDetailsScene, pocket: ControllerBackedProtocol) {
        self.scene = scene
        self.pocket = pocket

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .bgSurfaceMain
        navigationItem.style = .navigator
        navigationItem.title = String(localized: .walletMainIdCard)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: .iconShareWallet,
            style: .plain,
            target: self,
            action: #selector(didTapShare)
        )
        setupHosting()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        scene.attachNavigationHost(self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if let pocket {
            scene.attachNavigationHost(pocket)
        }
    }
}

extension IdentityCardScreenViewController: ControllerBackedProtocol {}

extension IdentityCardScreenViewController: TabBarRootStandIn {}

private extension IdentityCardScreenViewController {
    @objc
    func didTapShare() {
        scene.share()
    }

    func setupHosting() {
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.backgroundColor = .clear
        hosting.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        hosting.didMove(toParent: self)
    }
}

/// The identity card with its username and QR code under it.
private struct IdentityCardScreenRoot: View {
    let viewModel: IdentityDetailsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacings.large) {
                IdentityDetailsCard(viewModel: viewModel, isExpanded: true)
                IdentityShareQrView(viewModel: viewModel)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadii.extraLarge))
            }
            .padding(.horizontal, PocketCardSize.sideMargin)
            .padding(.top, 16)
        }
    }
}

import SwiftUI
import ExternalAccessibility
import PolkadotUI
import DesignSystem

struct AssetDetailsView: View {
    @State var viewModel: AssetDetailsViewModelProtocol
    var isExpanded: Bool = false
    var onCardTapped: () -> Void
    var overscroll: CGFloat = 0
    var onCollapse: (() -> Void)?
    // TODO: Remove along with `CoinageTestDataSwitch.swift`.
    @State private var testDataMode = CoinageTestDataMode.live

    init(
        viewModel: AssetDetailsViewModelProtocol = AssetDetailsViewModel(),
        isExpanded: Bool = false,
        onCardTapped: @escaping () -> Void,
        overscroll: CGFloat = 0,
        onCollapse: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.isExpanded = isExpanded
        self.onCardTapped = onCardTapped
        self.overscroll = overscroll
        self.onCollapse = onCollapse
    }

    var body: some View {
        DSExpandableCardLayout(
            isExpanded: isExpanded,
            overscroll: overscroll,
            onCollapse: onCollapse,
            card: { headerCard },
            details: { expandedBody }
        )
    }

    @ViewBuilder
    private var headerCard: some View {
        if let balanceCardModel = viewModel.balanceCardModel {
            balanceCard(balanceCardModel)
                .onTapGesture { onCardTapped() }
        }
    }

    @ViewBuilder
    private var expandedBody: some View {
        VStack(spacing: 16) {
            if viewModel.showsAccountBackupPending {
                AccountBackupPendingView()
            }
            if viewModel.showsBackupNotification {
                backupCard()
            } else {
                actions()
            }
            if viewModel.balanceCardModel != nil {
                // TODO: Remove the `??` along with `CoinageTestDataSwitch.swift`. It keeps the card,
                // and with it the switch, on a wallet that holds no coinage, which is where test
                // data is most useful.
                CoinageBalanceBreakdownView(
                    breakdown: viewModel.coinageBreakdown
                        ?? .testDataPlaceholder,
                    testDataMode: $testDataMode
                )
            }

            #if TESTNET_FEATURE
                HStack {
                    VStack { Divider().background(Color.fgPrimary) }
                    Text(verbatim: "Debug features")
                        .typography(.labelMedium)
                        .foregroundStyle(Color.fgPrimary)
                    VStack { Divider().background(Color.fgPrimary) }
                }

                testnetTopUpButton()
            #endif
        }
    }

    private func balanceCard(
        _ balanceCardModel: AssetDetailsBalanceCard.ViewModel
    ) -> some View {
        AssetDetailsBalanceCard(
            viewModel: balanceCardModel,
            isUpdating: viewModel.isUpdating,
            isExpanded: isExpanded
        )
    }

    private func backupCard() -> some View {
        WalletBackupNotificationCard(
            isUpdating: viewModel.isUpdating,
            onSync: viewModel.onBackupSync,
            onCancel: viewModel.onBackupCancel,
            onWhyUpdate: viewModel.onBackupWhyUpdate
        )
    }

    private func actions() -> some View {
        HStack(spacing: DSSpacings.small) {
            DSButton(.actionSendCash, expands: true) {
                viewModel.onSendMoney?()
            }
            .accessibilityId(AccessibilityID.Wallet.sendPaymentButton)

            circleButton(.add24, isLoading: viewModel.isTopUpInProgress) {
                viewModel.onTopUp?()
            }
            .accessibilityId(AccessibilityID.Wallet.addFundsButton)

            withdrawButton()
        }
    }

    private func withdrawButton() -> some View {
        Button {
            viewModel.onWithdraw?()
        } label: {
            Group {
                if viewModel.isWithdrawInProgress {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.fgPrimaryInverted)
                } else {
                    Text(String(localized: .actionWithdraw))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.ds(style: .primary, shape: .pill, size: .large))
        .disabled(viewModel.isWithdrawInProgress)
        .accessibilityId(AccessibilityID.Wallet.withdrawButton)
    }

    private func circleButton(
        _ icon: ImageResource,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.fgPrimaryInverted)
                } else {
                    Image(icon)
                        .renderingMode(.template)
                }
            }
            .frame(width: 56, height: 56)
            .foregroundStyle(Color.fgPrimaryInverted)
            .background(.bgActionPrimary, in: Circle())
        }
        .disabled(isLoading)
    }

    #if TESTNET_FEATURE
        private func testnetTopUpButton() -> some View {
            Button {
                viewModel.onTestnetTopUp?()
            } label: {
                Group {
                    if viewModel.isTestnetTopUpInProgress {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.fgPrimaryInverted)
                    } else {
                        Text(verbatim: "Faucet Top Up")
                            .textStyle(.body14SemiBold())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(Color.fgPrimaryInverted)
                .background(.bgActionPrimary, in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.isTestnetTopUpInProgress)
        }
    #endif
}

/// Funding progress banner. Pinned by the wallet host while the asset card is expanded.
struct AssetDetailsFundingBar: View {
    @Bindable var viewModel: AssetDetailsViewModel

    var body: some View {
        if !viewModel.fundingStates.isEmpty {
            AssetFundingStatusView(
                states: $viewModel.fundingStates,
                isExpanded: $viewModel.isFundingExpanded,
                configuration: .fundingDigitalDollarConfiguration(
                    onCompletedAction: viewModel.onFundingCompleted,
                    onFailedAction: viewModel.onFundingFailed
                )
            )
            .frame(maxWidth: .infinity)
        }
    }
}

private struct CoinageBalanceBreakdownView: View {
    let breakdown: CoinageBalanceBreakdownViewModel
    // TODO: Remove along with `CoinageTestDataSwitch.swift`.
    @Binding var testDataMode: CoinageTestDataMode

    @State private var showDetails = false
    /// How the coins came out, reported by the view as it lays them out.
    @State private var coinMetrics = CoinageCoinsView.Metrics()

    /// Anchors the card for the scroll that follows it down as it collapses.
    private static let anchor = "coinageCard"

    var body: some View {
        // Vends a proxy for the wallet's own scroll view rather than making one: collapsing the
        // details shortens the page under the reader, and a scroll view already past the new bottom
        // has to be walked down to it rather than dropped there.
        ScrollViewReader { scroll in
            card(scroll: scroll)
        }
    }

    private func card(scroll: ScrollViewProxy) -> some View {
        VStack(spacing: DSSpacings.extraMedium) {
            // TODO: Remove along with `CoinageTestDataSwitch.swift`.
            CoinageTestDataSwitch(mode: $testDataMode)

            VStack(spacing: 0) {
                Text(.coinageSummaryTitle)
                    .typography(.bodyMedium)
                    .foregroundStyle(.fgSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityId(AccessibilityID.Wallet.coinageHeader)

                totalHeadline
            }

            CoinageCompositionBar(model: breakdown.composition)
                .padding(.vertical, DSSpacings.extraTiny)

            summaryLegend

            // Above the coins rather than below them, so it stays on the same side whether they
            // are stacked into the strip or spread out one by one.
            Button {
                toggleDetails(scroll: scroll)
            } label: {
                HStack(spacing: DSSpacings.extraSmall) {
                    Image(.iconArrowUp16)
                        .renderingMode(.template)
                        .rotationEffect(.degrees(showDetails ? 0 : 180))
                    Text(String(localized: showDetails ? .coinageHideDetails : .coinageShowDetails))
                        .typography(.bodyMediumEmphasized)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.fgPrimary)
            }

            CoinageCoinsView(
                coins: testDataMode.strip ?? breakdown.strip,
                isExpanded: showDetails,
                metrics: $coinMetrics
            )
            .frame(height: max(coinMetrics.height, CoinageStripLayout.Options().height))
            // Deliberately not animated. Expanding takes its full height at once, so the coins fly
            // out into a box that is already the right size; animating it made the scroll view
            // chase a growing content size and bounce against its own edge. Collapsing is animated,
            // but from inside the toggle, where the scroll can be moved in the same breath.
            .overlay(alignment: .topLeading) { blockHeaders }
            .overlay(alignment: .topLeading) { pileCounts }
        }
        .padding(DSSpacings.mediumIncreased)
        .background(.bgSurfaceContainer, in: RoundedRectangle(cornerRadius: DSRadii.large))
        .id(Self.anchor)
    }

    /// Collapsing has to shorten the card and move the scroll view in one animation.
    ///
    /// The coins report their height only after laying out, which lands outside any transaction, so
    /// the card took the strip's height in a step of its own and the scroll view clamped to the new
    /// bottom in one jump. Taking the strip's height here, and asking the scroll view for the card
    /// in the same breath, makes the page shorten and the scroll follow it as one movement.
    private func toggleDetails(scroll: ScrollViewProxy) {
        let isCollapsing = showDetails

        withAnimation(.easeInOut(duration: 0.35)) {
            showDetails.toggle()

            guard isCollapsing else { return }

            coinMetrics.height = CoinageStripLayout.Options().height
            scroll.scrollTo(Self.anchor, anchor: .bottom)
        }
    }

    /// The Clearing and Ready headers over the grid. The layout leaves room for them above each
    /// block, so they sit in space the coins already made rather than pushing them about.
    @ViewBuilder
    private var blockHeaders: some View {
        ForEach(coinMetrics.blocks) { block in
            Text(String(localized: block.partition == .ready ? .coinageSpendable : .coinageLoading))
                .typography(.bodySmall)
                .foregroundStyle(Color.fgSecondary)
                .offset(y: block.top)
        }
    }

    /// How many coins a stack holds. Without it a pile reads as one oddly thick, tilted coin.
    ///
    /// At the tightest packing the rows leave barely a point between them, so the count sits over
    /// the foot of the pile on its own ground rather than in a gap that is not there.
    @ViewBuilder
    private var pileCounts: some View {
        ForEach(coinMetrics.piles) { pile in
            Text(verbatim: "×\(pile.count)")
                .typography(.labelSmall)
                .foregroundStyle(Color.fgPrimary)
                .padding(.horizontal, DSSpacings.extraTiny)
                .background(.bgSurfaceContainer, in: Capsule())
                .fixedSize()
                .frame(width: Self.pileCountWidth)
                .offset(x: pile.bottom.x - Self.pileCountWidth / 2, y: pile.bottom.y - 7)
        }
    }

    /// Wide enough for any count a pile can carry, so the badge centres on the stack.
    private static let pileCountWidth: CGFloat = 48

    private var totalHeadline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(breakdown.totalBalance)
                .typography(.displaySmall)
                .lineLimit(1)
                .accessibilityId(AccessibilityID.Wallet.coinageTotalBalanceValue)

            Text(breakdown.symbol)
                .typography(.titleMedium)
                .foregroundStyle(Color.fgSecondary)
        }
        .foregroundStyle(Color.fgPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The two figures partition the total and are the two sections of the bar above, in the
    /// same order, each keyed to its section by a swatch.
    ///
    /// A grid rather than two stacked columns: a label long enough to wrap would otherwise push
    /// its own value down and leave the two figures on different lines.
    private var summaryLegend: some View {
        Grid(alignment: .leading, horizontalSpacing: DSSpacings.small, verticalSpacing: DSSpacings.tiny) {
            GridRow {
                ForEach(legendEntries) { entry in
                    HStack(spacing: DSSpacings.extraSmall) {
                        CoinageLegendSwatch(kind: entry.kind)

                        Text(entry.title)
                            .typography(.bodySmall)
                            .foregroundStyle(Color.fgSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityId(entry.labelAccessibilityId)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .gridCellAnchor(.topLeading)

            GridRow {
                ForEach(legendEntries) { entry in
                    Text(entry.value)
                        .typography(.titleLarge)
                        .foregroundStyle(Color.fgPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityId(entry.valueAccessibilityId)
                }
            }
        }
    }

    private var legendEntries: [LegendEntry] {
        [
            LegendEntry(
                kind: .availableNow,
                title: String(localized: .coinageSpendable),
                value: breakdown.availableNowBalance,
                labelAccessibilityId: AccessibilityID.Wallet.coinageSpendableBalanceLabel,
                valueAccessibilityId: AccessibilityID.Wallet.coinageSpendableBalanceValue
            ),
            // No accessibility id yet: the registry lives in another repo.
            LegendEntry(
                kind: .gainingPrivacy,
                title: String(localized: .coinageLoading),
                value: breakdown.gainingPrivacyBalance
            )
        ]
    }
}

/// One of the two figures under the summary bar.
private struct LegendEntry: Identifiable {
    let kind: CoinageLegendSwatch.Kind
    let title: String
    let value: String
    var labelAccessibilityId: (any AccessibilityIdentifying)?
    var valueAccessibilityId: (any AccessibilityIdentifying)?

    var id: String { title }
}

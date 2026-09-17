import Foundation
import Foundation_iOS
import Products
import ChainRegistry

@MainActor
protocol ProductContentPrewarming {
    func prewarm()
}

@MainActor
final class ProductContentPrewarmer {
    private let makeLabels: () -> [String]
    private let chainRegistryClosure: ChainRegistryLazyClosure
    private let flowStateProvider: any SPAFlowStateProviding
    private let logger: LoggerProtocol

    private var prewarmTask: Task<Void, Never>?

    init(
        makeLabels: @escaping () -> [String],
        chainRegistryClosure: @escaping ChainRegistryLazyClosure,
        flowStateProvider: any SPAFlowStateProviding,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.makeLabels = makeLabels
        self.chainRegistryClosure = chainRegistryClosure
        self.flowStateProvider = flowStateProvider
        self.logger = logger
    }

    deinit {
        prewarmTask?.cancel()
    }
}

extension ProductContentPrewarmer: ProductContentPrewarming {
    func prewarm() {
        guard prewarmTask == nil else { return }

        prewarmTask = Task { [weak self] in
            await self?.warmContent()
            self?.prewarmTask = nil
        }
    }
}

private extension ProductContentPrewarmer {
    func warmContent() async {
        // Resolved lazily: the labels may depend on remote config that isn't available yet at
        // prewarmer construction. By warm time the prewarm trigger has run past remote config.
        var seen = Set<String>()
        let labels = makeLabels().filter { !$0.isEmpty && seen.insert($0).inserted }

        guard !labels.isEmpty else {
            logger.error("Product prewarm skipped: no labels")
            return
        }

        await chainRegistryClosure().asyncWaitChainsSetup(for: [AppConfig.Chains.assethubChain])

        let flowState = flowStateProvider.flowState()

        for label in labels {
            await warm(label: label, flowState: flowState)
        }
    }

    func warm(label: String, flowState: SPAFlowState) async {
        guard let host = try? await flowState.hostProvider.resolveHost(label: label) else {
            logger.error("Product prewarm skipped: could not resolve TLD for \(label)")
            return
        }

        let domain = host.toDotDomain()

        do {
            // Warms the app executable's archive, which is what the SPA loads.
            let contentId = try await flowState.productResolver.resolve(domain).appContentId
            _ = try await flowState.dotNsResolver.resolveToLocalURL(dotNsName: contentId)
            logger.debug("Product prewarm: warmed \(domain)")
        } catch {
            logger.error("Product prewarm: failed to warm \(domain): \(error)")
        }
    }
}

import Foundation

/// The two parts of the dashboard services. `DashboardServicesManager` is the only caller: the durability part serves
/// both the dashboard and a background renewal run, the interactive part only a live dashboard.
protocol DashboardServicesCoordinating: AnyObject {
    /// Coinage setup and the durable transaction engine. Runs once per instance; later calls await the same run.
    /// - Returns: `false` when coinage setup failed, so nothing that depends on it may start.
    @MainActor func startDurability() async -> Bool

    /// Everything a live dashboard needs, in today's order; awaits the durability part where it used to run it.
    @MainActor func startInteractive()

    /// Stops the interactive part and leaves the durable engine running for an ongoing background run.
    @MainActor func stopInteractive()

    /// Stops both parts. The instance is not started again afterwards.
    @MainActor func stopAll()
}

extension ServiceCoordinator {
    @MainActor
    func startDurability() async -> Bool {
        if let durabilityStart {
            return await durabilityStart.value
        }

        let start = Task { await runDurabilityStart() }
        durabilityStart = start
        return await start.value
    }

    @MainActor
    func startInteractive() {
        guard interactiveStart == nil else { return }

        // Keep the cached TLD warm on each launch without blocking.
        tldProvider.refresh()

        chatCoordinator.setup()
        productWorkerFacade.setup()
        chatExtensionsRegistry.discover()
        chatRequestCoordinator.setup()
        fiatOnrampTrackingService.setup()
        attachmentUploadService.setup()
        attachmentDownloadService.setup()
        notificationBadgeSyncService.setup()
        messageExpansionService.start()
        allowanceRenewalService.setup()

        interactiveStart = Task { [self] in
            await chainStatusProvider.start()
            await signInHostCoordinator.setup()
            await setupDeviceSyncService()

            guard await startDurability() else { return }

            // Recovering backup 1st
            await coinageTransferMonitor.setup()
            await w3sPaymentTracking.setup()
            await depositService.setup()
        }
    }

    @MainActor
    func stopInteractive() {
        guard let interactiveStart else { return }

        interactiveStart.cancel()
        self.interactiveStart = nil

        chatCoordinator.throttle()
        chatRequestCoordinator.throttle()
        fiatOnrampTrackingService.throttle()
        attachmentUploadService.throttle()
        attachmentDownloadService.throttle()
        notificationBadgeSyncService.throttle()
        allowanceRenewalService.throttle()

        messageExpansionService.stop()

        Task {
            await deviceSyncService.throttle()
            await coinageTransferMonitor.throttle()
            await w3sPaymentTracking.throttle()
            await signInHostCoordinator.throttle()
            await depositService.throttle()
        }
    }

    @MainActor
    func stopAll() {
        stopInteractive()
        durableTransactionEngine.txService.stop()
    }
}

private extension ServiceCoordinator {
    func runDurabilityStart() async -> Bool {
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let mainAssetId = AppConfig.Assets.mainAsset

        guard
            let chain = chainRegistry.getChain(for: mainAssetId.chainId),
            let asset = chain.asset(for: mainAssetId.assetId)
        else {
            assertionFailure()
            return false
        }

        do {
            try await coinageService.setup(with: asset)
        } catch {
            logger.error("Coinage service setup failed: \(error)")
            return false
        }

        // After coinage setup, which releases uncommitted handoffs the first pass must not see.
        durableTransactionEngine.txService.start()
        return true
    }
}

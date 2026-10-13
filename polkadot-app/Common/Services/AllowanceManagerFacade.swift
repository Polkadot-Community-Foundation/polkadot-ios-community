import Foundation
import FoundationExt
import Individuality
import ChainRegistry

struct AllowanceManagerFacade {
    let bulletInManager: AllowanceManaging
    let sssManager: AllowanceManaging & StatementAccountFunding
    let smartContractManager: AllowanceManaging
    let cleanupService: AllowanceCleanupServicing

    var allManagers: [AllowanceManaging] {
        [bulletInManager, sssManager, smartContractManager]
    }
}

extension AllowanceManagerFacade {
    static func create(
        chainRegistry: ChainRegistryProtocol = ChainRegistryFacade.sharedRegistry
    ) -> AllowanceManagerFacade? {
        guard
            let bulletInManager = BulletInAllowanceManager.create(chainRegistry: chainRegistry),
            let sssManager = SSStoreAllowanceManager.create(chainRegistry: chainRegistry),
            let smartContractManager = PGASAllowanceManager.create(chainRegistry: chainRegistry)
        else {
            return nil
        }

        return AllowanceManagerFacade(
            bulletInManager: bulletInManager,
            sssManager: sssManager,
            smartContractManager: smartContractManager,
            cleanupService: makeCleanupService(sssManager: sssManager)
        )
    }

    private static func makeCleanupService(sssManager: AllowanceManaging) -> AllowanceCleanupServicing {
        let chatFilter = ChatAllowanceFilter(
            activityProvider: ChatActivityStore(storageFacade: UserDataStorageFacade.shared),
            statementAccountResolver: ChatStatementAccountResolver(
                peerAccounts: ChatPeerAccounts(),
                signManager: ChatSignerManager()
            ),
            dateProvider: NowDateProvider()
        )

        return AllowanceCleanupService(
            targets: [.init(manager: sssManager, filter: chatFilter)],
            logger: Logger.shared
        )
    }
}

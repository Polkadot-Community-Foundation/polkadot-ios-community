import Foundation
import CommonService
import FoundationExt

final class AllowanceRenewalService {
    private let durabilityRenewal: StatementDurabilityRenewing
    private let appStateStreamFactory: ApplicationStateStreamFactory

    private var observerTask: Task<Void, Never>?

    init(
        durabilityRenewal: StatementDurabilityRenewing,
        appStateStreamFactory: ApplicationStateStreamFactory
    ) {
        self.durabilityRenewal = durabilityRenewal
        self.appStateStreamFactory = appStateStreamFactory
    }

    deinit {
        observerTask?.cancel()
    }
}

extension AllowanceRenewalService: ApplicationServiceProtocol {
    func setup() {
        observerTask?.cancel()
        observerTask = Task { [weak self] in
            await self?.durabilityRenewal.renewAll()

            let foregroundStream = self?.appStateStreamFactory.stream(for: .willEnterForeground)
            guard let foregroundStream else { return }
            for await _ in foregroundStream {
                guard !Task.isCancelled else { return }
                await self?.durabilityRenewal.renewAll()
            }
        }
    }

    func throttle() {
        observerTask?.cancel()
        observerTask = nil
    }
}

import Foundation
import Operation_iOS

protocol ChatAcceptanceNotifying {
    /// Pushes the acceptance to the requester once; a failed push never fails the delivery.
    func notify(_ candidate: ChatAcceptanceCandidate) async
}

/// The acceptance is published outside the outbox, so it also sends the push the outbox would have sent.
final class ChatAcceptanceNotifier {
    private let apnsClientService: APNSClientServicing
    private let notifiedMessageIdRepository: AnyDataProviderRepository<Chat.NotifiedMessageId>
    private let logger: LoggerProtocol

    init(
        apnsClientService: APNSClientServicing,
        notifiedMessageIdRepository: AnyDataProviderRepository<Chat.NotifiedMessageId>,
        logger: LoggerProtocol
    ) {
        self.apnsClientService = apnsClientService
        self.notifiedMessageIdRepository = notifiedMessageIdRepository
        self.logger = logger
    }
}

extension ChatAcceptanceNotifier: ChatAcceptanceNotifying {
    func notify(_ candidate: ChatAcceptanceCandidate) async {
        let messageId = candidate.message.messageId

        guard let remoteMessage = candidate.message.toRemote() else { return }

        do {
            let alreadyNotified = try await notifiedMessageIdRepository
                .fetchOperation(by: { messageId }, options: RepositoryFetchOptions())
                .asyncExecute() != nil

            guard !alreadyNotified else { return }

            _ = try await apnsClientService
                .notifyAboutNewMessageWrapper(remoteMessage, contact: candidate.contact)
                .asyncExecute()

            try await notifiedMessageIdRepository
                .saveOperation({ [Chat.NotifiedMessageId(messageId: messageId)] }, { [] })
                .asyncExecute()
        } catch {
            logger.error("Chat acceptance \(messageId) push failed: \(error)")
        }
    }
}

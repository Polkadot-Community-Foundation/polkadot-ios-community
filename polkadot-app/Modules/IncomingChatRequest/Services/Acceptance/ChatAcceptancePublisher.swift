import Foundation
import CommonService

protocol ChatAcceptancePublishing: ApplicationServiceProtocol {}

/// Hands every new acceptance to the delivery service once; re-emitted snapshots don't start a second delivery.
final class ChatAcceptancePublisher {
    private let messageProviderFactory: ChatMessageDataProviderMaking
    private let deliveryService: ChatAcceptanceDelivering
    private let deliveries = ChatAcceptanceDeliveries()
    private let logger: LoggerProtocol

    private var subscriptionTask: Task<Void, Never>?

    init(
        messageProviderFactory: ChatMessageDataProviderMaking,
        deliveryService: ChatAcceptanceDelivering,
        logger: LoggerProtocol
    ) {
        self.messageProviderFactory = messageProviderFactory
        self.deliveryService = deliveryService
        self.logger = logger
    }
}

extension ChatAcceptancePublisher: ChatAcceptancePublishing {
    func setup() {
        guard subscriptionTask == nil else { return }

        subscriptionTask = Task { [messageProviderFactory, deliveryService, deliveries, logger] in
            let stream = messageProviderFactory.subscribeMessages(with: .newLocalDeviceChatAcceptances())

            do {
                for try await messages in stream {
                    await deliveries.start(messages.map(\.messageId), using: deliveryService)
                }
            } catch {
                logger.error("Chat acceptance subscription failed: \(error)")
            }
        }
    }

    func throttle() {
        subscriptionTask?.cancel()
        subscriptionTask = nil

        Task { [deliveries] in await deliveries.cancelAll() }
    }
}

private actor ChatAcceptanceDeliveries {
    private var inFlight: [String: Task<Void, Never>] = [:]

    func start(_ messageIds: [String], using deliveryService: ChatAcceptanceDelivering) {
        for messageId in messageIds where inFlight[messageId] == nil {
            inFlight[messageId] = Task {
                await deliveryService.deliverUntilDone(messageId: messageId)
                self.finish(messageId)
            }
        }
    }

    func cancelAll() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }

    private func finish(_ messageId: String) {
        inFlight[messageId] = nil
    }
}

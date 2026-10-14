import Foundation
import BackgroundExecution
import CommonService
import MessageExchangeKit
import SDKLogger
import ChainStore

protocol ChatRequestCoordinatorServicing: ApplicationServiceProtocol {}

final class ChatRequestCoordinatorService {
    let contactsProviderFactory: ChatContactDataProviderMaking
    let messageProviderFactory: ChatMessageDataProviderMaking
    let serviceFactory: ChatRequestServiceMaking
    let backgroundExecutor: BackgroundExecuting
    let logger: SDKLoggerProtocol

    private static let renewalInterval: Duration = .seconds(60 * 60)

    private var coordinationTask: Task<Void, Never>?

    init(
        contactsProviderFactory: ChatContactDataProviderMaking,
        messageProviderFactory: ChatMessageDataProviderMaking,
        serviceFactory: ChatRequestServiceMaking,
        backgroundExecutor: BackgroundExecuting,
        logger: SDKLoggerProtocol
    ) {
        self.contactsProviderFactory = contactsProviderFactory
        self.messageProviderFactory = messageProviderFactory
        self.serviceFactory = serviceFactory
        self.backgroundExecutor = backgroundExecutor
        self.logger = logger
    }
}

extension ChatRequestCoordinatorService: ChatRequestCoordinatorServicing {
    func setup() {
        guard coordinationTask == nil else {
            logger.warning("Service already running")
            return
        }

        logger.debug("Starting service...")

        coordinationTask = Task {
            do {
                let discoveryService = try await serviceFactory.makeDiscoveryService()
                let incomingRequestService = try await serviceFactory.makeIncomingChatRequestService()
                let deliveryService = try await serviceFactory.makeChatRequestDeliveryService()
                let incomingContext = try await serviceFactory.makeIncomingChatRequestContext()
                let outgoingContext = try await serviceFactory.makeOutgoingChatRequestContext()
                let renewer = try await serviceFactory.makeChatRequestRenewer()
                let acceptancePublisher = try await serviceFactory.makeChatAcceptancePublisher(
                    messageProviderFactory: messageProviderFactory
                )
                let acceptanceRenewer = try await serviceFactory.makeChatAcceptanceRenewer()
                let outgoingServices = try await OutgoingRequestServices(
                    deliveryService: deliveryService,
                    acceptanceListener: serviceFactory.makeChatAcceptanceListener(),
                    acceptContext: serviceFactory.makeAcceptContext()
                )

                acceptancePublisher.setup()

                let renewalTask = Task { [backgroundExecutor] in
                    await Self.runRenewal(
                        renewer,
                        acceptanceRenewer: acceptanceRenewer,
                        backgroundExecutor: backgroundExecutor
                    )
                }
                defer {
                    renewalTask.cancel()
                    acceptancePublisher.throttle()
                }

                let allContactsStream = contactsProviderFactory.subscribeAllContacts()

                logger.debug("Service started")

                try await withTaskCancellationHandler {
                    for try await contacts in allContactsStream {
                        await incomingContext.update(
                            contacts: contacts,
                            discoverTaskBuilder: { ownKeyId in
                                setupDiscoveryTask(
                                    using: discoveryService,
                                    ownKeyId: ownKeyId,
                                    with: incomingContext
                                )
                            }, incomingRequestTaskBuilder: { contacts, ownKeyId in
                                setupIncomingRequestsTask(
                                    for: contacts,
                                    ownKeyId: ownKeyId,
                                    using: incomingRequestService,
                                    context: incomingContext
                                )
                            }
                        )

                        await updateOutgoing(
                            contacts: contacts,
                            services: outgoingServices,
                            context: outgoingContext
                        )

                        logger.debug("Handled contacts: \(contacts.count)")
                    }
                } onCancel: {
                    Task { await outgoingContext.cancelAll() }
                }
            } catch {
                logger.error("Contacts subscription failed: \(error)")
            }

            logger.debug("Contacts stream ended")
        }
    }

    func throttle() {
        coordinationTask?.cancel()
        coordinationTask = nil
    }
}

private extension ChatRequestCoordinatorService {
    // The renewer stays executor-free so a background task can drive it under its own expiration.
    static func runRenewal(
        _ renewer: ChatRequestRenewing,
        acceptanceRenewer: ChatAcceptanceRenewing,
        backgroundExecutor: BackgroundExecuting
    ) async {
        while !Task.isCancelled {
            try? await backgroundExecutor.execute {
                await renewer.renew()
                await acceptanceRenewer.renew()
            }
            try? await Task.sleep(for: renewalInterval)
        }
    }

    func setupDiscoveryTask(
        using discoveryService: ChatDiscoveryServicing,
        ownKeyId: Chat.Contact.Own,
        with context: IncomingChatRequestCoordinationContext
    ) -> Task<Void, Never> {
        Task {
            guard let discoveredRequestStream = discoveryService.makeDiscoveryTask(for: ownKeyId) else {
                logger.error("Discovery stream not created")
                return
            }

            do {
                for try await validatedRequest in discoveredRequestStream {
                    do {
                        try await context.handle(incomingRequest: validatedRequest, ownKeyId: ownKeyId)

                        logger.debug("Handled discovered request: \(validatedRequest.message.messageId)")
                    } catch {
                        logger.error("Couldn't handle discovered request: \(error)")
                    }
                }
            } catch {
                logger.error("Discovery requests subscription failed: \(error)")
            }

            logger.debug("Discovery stream ended")
        }
    }

    func setupIncomingRequestsTask(
        for contacts: [Chat.Contact],
        ownKeyId: Chat.Contact.Own,
        using incomingService: IncomingChatRequestServicing,
        context: IncomingChatRequestCoordinationContext
    ) -> Task<Void, Never> {
        Task {
            let peers = contacts.map { $0.toMessageExchangePeer() }

            let incomingRequestsStream = incomingService.subscribe(peers: Set(peers), ownKeyId: ownKeyId)

            do {
                for try await validatedRequest in incomingRequestsStream {
                    do {
                        try await context.handle(incomingRequest: validatedRequest, ownKeyId: ownKeyId)

                        logger.debug("Handled incoming request: \(validatedRequest.message.messageId)")
                    } catch {
                        logger.error("Couldn't handle incoming request: \(error)")
                    }
                }
            } catch {
                logger.error("Incoming requests subscription failed: \(error)")
            }

            logger.debug("Incoming requests stream ended")
        }
    }

    func updateOutgoing(
        contacts: [Chat.Contact],
        services: OutgoingRequestServices,
        context: OutgoingChatRequestCoordinationContext
    ) async {
        await context.update(
            contacts: contacts,
            outgoingRequestTaskBuilder: {
                setupOutgoingRequestsTask(deliveryService: services.deliveryService, context: context)
            },
            acceptanceTaskBuilder: { requests in
                setupAcceptanceTask(for: requests, services: services)
            }
        )
    }

    func setupAcceptanceTask(
        for requests: [MessageExchange.SessionRequest],
        services: OutgoingRequestServices
    ) -> Task<Void, Never> {
        Task {
            guard !requests.isEmpty else { return }

            do {
                for try await acceptance in services.acceptanceListener.subscribe(to: requests) {
                    await apply(acceptance, using: services.acceptContext)
                }
            } catch {
                logger.error("Acceptance listening failed: \(error)")
            }
        }
    }

    // Copies from earlier periods can coexist; the context accepts each request once.
    func apply(_ acceptance: ReceivedChatAcceptance, using context: ChatRequestAcceptProcessorContext) async {
        do {
            guard try await context.accept(
                requestId: acceptance.requestId,
                from: acceptance.peerAccountId,
                peerDevice: acceptance.device
            ) != nil else {
                return
            }

            logger.debug("Applied acceptance of \(acceptance.requestId)")
        } catch {
            logger.error("Applying acceptance of \(acceptance.requestId) failed: \(error)")
        }
    }

    func setupOutgoingRequestsTask(
        deliveryService: ChatRequestDelivering,
        context: OutgoingChatRequestCoordinationContext
    ) -> Task<Void, Never> {
        Task {
            let outgoingRequestsStream = messageProviderFactory.subscribeNewOutgoingChatRequests()

            do {
                for try await requestMessages in outgoingRequestsStream {
                    await context.process(requestMessages: requestMessages) { message, session in
                        await deliveryService.deliverUntilDone(message, session: session)
                    }
                }
            } catch {
                logger.error("Outgoing requests processing failed: \(error)")
            }

            logger.debug("Outgoing requests stream ended")
        }
    }
}

private struct OutgoingRequestServices {
    let deliveryService: ChatRequestDelivering
    let acceptanceListener: ChatAcceptanceListening
    let acceptContext: ChatRequestAcceptProcessorContext
}

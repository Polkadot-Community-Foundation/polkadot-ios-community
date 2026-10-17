import Foundation
import FoundationExt
import MessageExchangeKit
import StatementStore
import SubstrateSdk
import NovaCrypto
import Keystore_iOS
import SDKLogger
import KeyDerivation
import BackgroundExecution
import ChainRegistry
import Individuality
import IssueMonitoring
import StatementDelivery

protocol ChatRequestServiceMaking {
    func makeDiscoveryService() async throws -> ChatDiscoveryServicing

    func makeIncomingChatRequestService() async throws -> IncomingChatRequestServicing

    func makeChatRequestDeliveryService() async throws -> any OutgoingStatementDelivering<OutgoingChatRequestInput>

    func makeChatRequestRenewer() async throws -> OutgoingStatementRenewing

    func makeIncomingChatRequestContext() async throws -> IncomingChatRequestCoordinationContext

    func makeOutgoingChatRequestContext() async throws -> OutgoingChatRequestCoordinationContext

    func makeChatAcceptancePublisher(
        messageProviderFactory: ChatMessageDataProviderMaking
    ) async throws -> ChatAcceptancePublishing

    func makeChatAcceptanceRenewer() async throws -> ChatAcceptanceRenewing

    func makeChatAcceptanceListener() async throws -> ChatAcceptanceListening

    func makeAcceptContext() async -> ChatRequestAcceptProcessorContext
}

actor ChatRequestServiceFactory {
    let chatChainId: ChainModel.Id
    let entropyManager: RootEntropyManaging
    let chainRegistry: ChainRegistryProtocol
    let storageFacade: StorageFacadeProtocol
    let discoverySettings: ChatDiscoverySettingsStoring
    let operationQueue: OperationQueue
    let logger: LoggerProtocol
    let remoteContactResolver: RemoteContactResolving
    let notificationAllocator: NotificationStatementAccountAllocating
    let signingFallback: NonPrivateSigningFallbacking
    let backgroundExecutor: BackgroundExecuting
    let issueReporter: IssueReporting

    private var connection: StatementStoreConnecting?
    private var accountSignManager: ChatSignerManager?
    private var accountEncryptionManager: MessageExchangeEncryptionManaging?
    private var diagnostics: ChatRequestDiagnostics?
    private var requestPipeline: ChatRequestPipeline?

    init(
        remoteContactResolver: RemoteContactResolving,
        notificationAllocator: NotificationStatementAccountAllocating,
        signingFallback: NonPrivateSigningFallbacking,
        backgroundExecutor: BackgroundExecuting,
        issueReporter: IssueReporting,
        chatChainId: ChainModel.Id = AppConfig.Chains.chatChain,
        chainRegistry: ChainRegistryProtocol = ChainRegistryFacade.sharedRegistry,
        entropyManager: RootEntropyManaging = RootEntropyManager.shared,
        storageFacade: StorageFacadeProtocol = UserDataStorageFacade.shared,
        discoverySettings: ChatDiscoverySettingsStoring = SettingsManager.shared,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: SDKLoggerProtocol = Logger.shared
    ) {
        self.remoteContactResolver = remoteContactResolver
        self.notificationAllocator = notificationAllocator
        self.signingFallback = signingFallback
        self.backgroundExecutor = backgroundExecutor
        self.issueReporter = issueReporter
        self.chatChainId = chatChainId
        self.chainRegistry = chainRegistry
        self.entropyManager = entropyManager
        self.storageFacade = storageFacade
        self.discoverySettings = discoverySettings
        self.operationQueue = operationQueue
        self.logger = logger
    }
}

extension ChatRequestServiceFactory: ChatRequestServiceMaking {
    func makeDiscoveryService() async throws -> ChatDiscoveryServicing {
        let connection = try await makeConnection()
        let signManager = makeAccountSignManager()
        let encryptionManager = makeAccountEncryptionManager()

        let chatRequestFactory = ChatRequestFactory(
            encryptionManager: encryptionManager,
            signManager: signManager,
            remoteContactResolver: remoteContactResolver
        )

        return ChatDiscoveryService(
            signManager: signManager,
            settings: discoverySettings,
            statementStoreConnection: connection,
            chatRequestFactory: chatRequestFactory,
            logger: logger
        )
    }

    func makeIncomingChatRequestService() async throws -> IncomingChatRequestServicing {
        let connection = try await makeConnection()
        let encryptionManager = makeAccountEncryptionManager()
        let signManager = makeAccountSignManager()

        let channelFactory = ChatRequestChannelFactory(
            encryptionManager: encryptionManager,
            signingManager: signManager,
            sessionIdFactory: PeerSessionIdFactory()
        )

        let chatRequestFactory = ChatRequestFactory(
            encryptionManager: encryptionManager,
            signManager: signManager,
            remoteContactResolver: remoteContactResolver
        )

        return IncomingChatRequestService(
            statementStoreConnection: connection,
            channelFactory: channelFactory,
            chatRequestFactory: chatRequestFactory,
            logger: logger
        )
    }

    func makeIncomingChatRequestContext() async throws -> IncomingChatRequestCoordinationContext {
        let encryptionManager = makeAccountEncryptionManager()
        let signManager = makeAccountSignManager()

        return try IncomingChatRequestCoordinationContext(
            discoveryOwnKeyIds: [Chat.Contact.Own.main()],
            matchOwnKeyIds: Chat.Contact.Own.allPossibleIds(),
            requestStoreService: makeRequestStoreService(
                encryptionManager: encryptionManager,
                signManager: signManager
            ),
            contactsStorageService: ContactsLocalStorageService(),
            remoteContactResolver: remoteContactResolver
        )
    }

    func makeOutgoingChatRequestContext() async throws -> OutgoingChatRequestCoordinationContext {
        OutgoingChatRequestCoordinationContext(logger: logger)
    }

    func makeChatRequestDeliveryService() async throws -> any OutgoingStatementDelivering<OutgoingChatRequestInput> {
        try await makeRequestPipeline().delivery
    }

    func makeChatAcceptancePublisher(
        messageProviderFactory: ChatMessageDataProviderMaking
    ) async throws -> ChatAcceptancePublishing {
        let dependencies = try await ChatAcceptanceDeliveryDependencies(
            store: ChatAcceptanceStore(storageFacade: storageFacade),
            allocator: notificationAllocator,
            signerManager: makeAccountSignManager(),
            statementService: makeAcceptanceStatementService(),
            notifier: makeAcceptanceNotifier(),
            fallback: signingFallback
        )

        let deliveryService = ChatAcceptanceDeliveryService(
            dependencies: dependencies,
            execution: ChatRequestDeliveryExecution(backgroundExecutor: backgroundExecutor),
            issueDiagnostics: .make(reporter: issueReporter),
            logger: logger
        )

        return ChatAcceptancePublisher(
            messageProviderFactory: messageProviderFactory,
            deliveryService: deliveryService,
            logger: logger
        )
    }

    func makeChatAcceptanceListener() async throws -> ChatAcceptanceListening {
        try await ChatAcceptanceListener(
            requestFactory: IdentityRouteRequestFactory(
                encryptionManager: makeAccountEncryptionManager(),
                signerManager: makeAccountSignManager()
            ),
            connection: makeConnection(),
            logger: logger
        )
    }

    func makeAcceptContext() async -> ChatRequestAcceptProcessorContext {
        let encryptionManager = makeAccountEncryptionManager()
        let signManager = makeAccountSignManager()

        return ChatRequestAcceptProcessorContext(
            requestStoreService: makeRequestStoreService(
                encryptionManager: encryptionManager,
                signManager: signManager
            ),
            contactsStorageService: ContactsLocalStorageService(),
            logger: logger
        )
    }

    func makeChatAcceptanceRenewer() async throws -> ChatAcceptanceRenewing {
        let dependencies = try await ChatAcceptanceRenewalDependencies(
            store: ChatAcceptanceStore(storageFacade: storageFacade),
            allocator: notificationAllocator,
            signerManager: makeAccountSignManager(),
            statementService: makeAcceptanceStatementService(),
            fallback: signingFallback
        )

        return ChatAcceptanceRenewer(
            dependencies: dependencies,
            dateProvider: NowDateProvider(),
            issueDiagnostics: .make(reporter: issueReporter),
            logger: logger
        )
    }

    func makeChatRequestRenewer() async throws -> OutgoingStatementRenewing {
        let pipeline = try await makeRequestPipeline()

        return OutgoingStatementRenewer(
            dependencies: OutgoingStatementRenewalDependencies(
                store: pipeline.store,
                resolver: pipeline.resolver,
                service: pipeline.service,
                delivery: pipeline.delivery
            ),
            bound: nil,
            dateProvider: NowDateProvider(),
            diagnostics: makeDiagnostics().statementDiagnostics
        )
    }
}

/// One delivery service shared by first delivery and renewal, so the two never publish the same request at once.
private struct ChatRequestPipeline {
    let store: ChatRequestOutgoingStore
    let resolver: ChatRequestSignerResolver
    let service: OutgoingStatementService<OutgoingChatRequestInput>
    let delivery: OutgoingStatementDeliveryService<OutgoingChatRequestInput>
}

private extension ChatRequestServiceFactory {
    func makeRequestPipeline() async throws -> ChatRequestPipeline {
        if let requestPipeline {
            return requestPipeline
        }

        let builder = makeRequestStatementBuilder()
        let diagnostics = makeDiagnostics()
        let store = ChatRequestOutgoingStore(storageFacade: storageFacade)
        let resolver = ChatRequestSignerResolver(
            allocator: notificationAllocator,
            signerManager: makeAccountSignManager(),
            fallback: signingFallback,
            renewalStarved: diagnostics.issues.renewalStarved,
            logger: logger
        )
        let service = try await OutgoingStatementService(
            builder: builder,
            connection: makeConnection(),
            signerManager: makeAccountSignManager()
        )
        let delivery = OutgoingStatementDeliveryService(
            dependencies: OutgoingStatementDeliveryDependencies(
                store: store,
                resolver: resolver,
                service: service,
                builder: builder,
                postDelivery: nil
            ),
            execution: OutgoingStatementDeliveryExecution(backgroundExecutor: backgroundExecutor),
            diagnostics: diagnostics.statementDiagnostics
        )

        let pipeline = ChatRequestPipeline(store: store, resolver: resolver, service: service, delivery: delivery)
        requestPipeline = pipeline

        return pipeline
    }

    func makeRequestStatementBuilder() -> ChatRequestStatementBuilder {
        let encryptionManager = makeAccountEncryptionManager()
        let signManager = makeAccountSignManager()

        return ChatRequestStatementBuilder(
            requestFactory: ChatRequestFactory(
                encryptionManager: encryptionManager,
                signManager: signManager,
                remoteContactResolver: remoteContactResolver
            ),
            channelFactory: ChatRequestChannelFactory(
                encryptionManager: encryptionManager,
                signingManager: signManager,
                sessionIdFactory: PeerSessionIdFactory()
            ),
            priorityFactory: StatementPriorityFactory()
        )
    }

    func makeRequestStoreService(
        encryptionManager: MessageExchangeEncryptionManaging,
        signManager: StatementStoreSignerManaging
    ) -> ChatRequestStoreService {
        ChatRequestStoreService(
            storageFacade: storageFacade,
            pushIdFactory: ChatPushIdFactory(
                encryptionManager: encryptionManager,
                signManager: signManager,
                sessionIdFactory: PeerSessionIdFactory(),
                logger: logger
            ),
            deviceEncryptionKeyManager: DeviceEncryptionKeyManager.shared
        )
    }

    func makeAcceptanceNotifier() -> ChatAcceptanceNotifying {
        let encryptionManager = makeAccountEncryptionManager()

        return ChatAcceptanceNotifier(
            apnsClientService: APNSClientService(
                pushIdFactory: ChatPushIdFactory(
                    encryptionManager: encryptionManager,
                    signManager: makeAccountSignManager(),
                    sessionIdFactory: PeerSessionIdFactory(),
                    logger: logger
                ),
                messageCoder: ChatPushMessageCoder(encryptionManager: encryptionManager),
                payloadBuilder: ChatNotificationPayloadBuilder(logger: logger),
                tokenProvider: JWTTokenManager.shared,
                workQueue: DispatchQueue(label: "io.chat.acceptance.push.queue")
            ),
            notifiedMessageIdRepository: NotifiedMessageIdRepositoryFactory(storageFacade: storageFacade)
                .createRepository(),
            logger: logger
        )
    }

    func makeAcceptanceStatementService() async throws -> ChatAcceptanceStatementServicing {
        try await ChatAcceptanceStatementService(
            requestFactory: IdentityRouteRequestFactory(
                encryptionManager: makeAccountEncryptionManager(),
                signerManager: makeAccountSignManager()
            ),
            connection: makeConnection()
        )
    }

    func makeDiagnostics() -> ChatRequestDiagnostics {
        if let diagnostics {
            return diagnostics
        }

        let diagnostics = ChatRequestDiagnostics(
            logger: logger,
            issues: ChatRequestIssueDiagnostics.make(reporter: issueReporter)
        )
        self.diagnostics = diagnostics

        return diagnostics
    }

    func makeConnection() async throws -> StatementStoreConnecting {
        if let connection {
            return connection
        }

        let chainConnection = try chainRegistry.getConnectionOrError(for: chatChainId)

        let connection = StatementStoreConnection(
            connection: chainConnection,
            retryMatcher: StatementSubmitErrorMatcher.retryWhenTimeoutOrNoAllowance(),
            logger: logger
        )

        self.connection = connection

        return connection
    }

    func makeAccountEncryptionManager() -> MessageExchangeEncryptionManaging {
        if let accountEncryptionManager {
            return accountEncryptionManager
        }

        let manager = ChatEncryptionManager(entropyManager: entropyManager)

        accountEncryptionManager = manager

        return manager
    }

    func makeAccountSignManager() -> ChatSignerManager {
        if let accountSignManager {
            return accountSignManager
        }

        let manager = ChatSignerManager(entropyManager: entropyManager)

        accountSignManager = manager

        return manager
    }
}

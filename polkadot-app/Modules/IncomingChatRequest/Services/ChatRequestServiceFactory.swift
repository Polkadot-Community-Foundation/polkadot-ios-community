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

protocol ChatRequestServiceMaking {
    func makeDiscoveryService() async throws -> ChatDiscoveryServicing

    func makeIncomingChatRequestService() async throws -> IncomingChatRequestServicing

    func makeOutgoingChatRequestService() async throws -> OutgoingChatRequestServicing

    func makeChatRequestDeliveryService() async throws -> ChatRequestDelivering

    func makeChatRequestRenewer() async throws -> ChatRequestRenewing

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
    let backgroundExecutor: BackgroundExecuting
    let issueReporter: IssueReporting

    private var connection: StatementStoreConnecting?
    private var accountSignManager: StatementStoreSignerManaging?
    private var accountEncryptionManager: MessageExchangeEncryptionManaging?
    private var diagnostics: ChatRequestDiagnostics?

    init(
        remoteContactResolver: RemoteContactResolving,
        notificationAllocator: NotificationStatementAccountAllocating,
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
            remoteContactResolver: remoteContactResolver,
            statementSignerResolver: ChatStatementSignerResolver(signManager: signManager)
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
            remoteContactResolver: remoteContactResolver,
            statementSignerResolver: ChatStatementSignerResolver(signManager: signManager)
        )

        return IncomingChatRequestService(
            statementStoreConnection: connection,
            channelFactory: channelFactory,
            chatRequestFactory: chatRequestFactory,
            logger: logger
        )
    }

    func makeOutgoingChatRequestService() async throws -> OutgoingChatRequestServicing {
        let connection = try await makeConnection()
        let encryptionManager = makeAccountEncryptionManager()
        let accountSignManager = makeAccountSignManager()

        let channelFactory = ChatRequestChannelFactory(
            encryptionManager: encryptionManager,
            signingManager: accountSignManager,
            sessionIdFactory: PeerSessionIdFactory()
        )

        let chatRequestFactory = ChatRequestFactory(
            encryptionManager: encryptionManager,
            signManager: accountSignManager,
            remoteContactResolver: remoteContactResolver,
            statementSignerResolver: ChatStatementSignerResolver(signManager: accountSignManager)
        )

        return OutgoingChatRequestService(
            statementStoreConnection: connection,
            requestFactory: chatRequestFactory,
            priorityFactory: StatementPriorityFactory(),
            channelFactory: channelFactory,
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

    func makeChatRequestDeliveryService() async throws -> ChatRequestDelivering {
        let resolver = ChatRequestDeliveryAccountResolver(
            allocator: notificationAllocator,
            signers: ChatRequestDeliverySigners(signManager: makeAccountSignManager())
        )

        return try await ChatRequestDeliveryService(
            outgoingService: makeOutgoingChatRequestService(),
            resolver: resolver,
            store: ChatRequestDeliveryStore(storageFacade: storageFacade),
            execution: ChatRequestDeliveryExecution(backgroundExecutor: backgroundExecutor),
            diagnostics: makeDiagnostics()
        )
    }

    func makeChatAcceptancePublisher(
        messageProviderFactory: ChatMessageDataProviderMaking
    ) async throws -> ChatAcceptancePublishing {
        let dependencies = try await ChatAcceptanceDeliveryDependencies(
            store: ChatAcceptanceStore(storageFacade: storageFacade),
            allocator: notificationAllocator,
            signers: ChatAcceptanceSigners(signManager: makeAccountSignManager()),
            statementService: makeAcceptanceStatementService(),
            notifier: makeAcceptanceNotifier()
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
            signers: ChatAcceptanceSigners(signManager: makeAccountSignManager()),
            statementService: makeAcceptanceStatementService()
        )

        return ChatAcceptanceRenewer(
            dependencies: dependencies,
            dateProvider: NowDateProvider(),
            issueDiagnostics: .make(reporter: issueReporter),
            logger: logger
        )
    }

    func makeChatRequestRenewer() async throws -> ChatRequestRenewing {
        try await ChatRequestRenewer(
            store: ChatRequestDeliveryStore(storageFacade: storageFacade),
            allocator: notificationAllocator,
            signers: ChatRequestDeliverySigners(signManager: makeAccountSignManager()),
            outgoingService: makeOutgoingChatRequestService(),
            diagnostics: makeDiagnostics()
        )
    }
}

private extension ChatRequestServiceFactory {
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
            deviceEncryptionKeyManager: DeviceEncryptionKeyManager.shared,
            statementSignerResolver: ChatStatementSignerResolver(signManager: signManager)
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

    func makeAccountSignManager() -> StatementStoreSignerManaging {
        if let accountSignManager {
            return accountSignManager
        }

        let manager = ChatSignerManager(entropyManager: entropyManager)

        accountSignManager = manager

        return manager
    }
}

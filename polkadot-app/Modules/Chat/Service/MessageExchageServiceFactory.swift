import Foundation
import SubstrateSdk
import Keystore_iOS
import MessageExchangeKit
import StatementStore
import NovaCrypto
import KeyDerivation

protocol MessageExchageServiceMaking {
    func makeService<M: MessageExchange.CodableMessage>(
        statementStoreConnection: StatementStoreConnecting,
        delegate: AnyPeerSessionDelegate<M>,
        compactorFactory: AnyMessageCompactorFactory<M>?
    ) throws -> AnyMessageExchangeService<M>
}

extension MessageExchageServiceMaking {
    func makeService<M: MessageExchange.CodableMessage>(
        statementStoreConnection: StatementStoreConnecting,
        delegate: AnyPeerSessionDelegate<M>
    ) throws -> AnyMessageExchangeService<M> {
        try makeService(
            statementStoreConnection: statementStoreConnection,
            delegate: delegate,
            compactorFactory: nil
        )
    }
}

final class MessageExchangeServiceFactory {
    let signManager: StatementStoreSignerManaging
    let encryptionManager: MessageExchangeEncryptionManaging
    let deviceEncryptionKeyFactory: MessageExchangeEncryptionMaking?
    let submissionGate: PeerSessionSubmissionGating?
    let messageExchangeModeProvider: MessageExchangeModeProviding
    let workQueue: DispatchQueue
    let operationQueue: OperationQueue
    let maxStatementSize: Int
    let logger: LoggerProtocol

    init(
        messageExchangeModeProvider: MessageExchangeModeProviding,
        signManager: StatementStoreSignerManaging,
        encryptionManager: MessageExchangeEncryptionManaging,
        deviceEncryptionKeyFactory: MessageExchangeEncryptionMaking?,
        submissionGate: PeerSessionSubmissionGating? = nil,
        maxStatementSize: Int,
        workQueue: DispatchQueue = DispatchQueue(label: "message.exchange.work.queue"),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.signManager = signManager
        self.encryptionManager = encryptionManager
        self.deviceEncryptionKeyFactory = deviceEncryptionKeyFactory
        self.submissionGate = submissionGate
        self.messageExchangeModeProvider = messageExchangeModeProvider
        self.workQueue = workQueue
        self.operationQueue = operationQueue
        self.maxStatementSize = maxStatementSize
        self.logger = logger
    }

    convenience init(
        messageExchangeModeProvider: MessageExchangeModeProviding,
        entropyManager: RootEntropyManaging,
        deviceEncryptionKeyFactory: MessageExchangeEncryptionMaking?,
        submissionGate: PeerSessionSubmissionGating? = nil,
        maxStatementSize: Int,
        workQueue: DispatchQueue = DispatchQueue(label: "message.exchange.work.queue"),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.init(
            messageExchangeModeProvider: messageExchangeModeProvider,
            signManager: ChatSignerManager(entropyManager: entropyManager),
            encryptionManager: ChatEncryptionManager(entropyManager: entropyManager),
            deviceEncryptionKeyFactory: deviceEncryptionKeyFactory,
            submissionGate: submissionGate,
            maxStatementSize: maxStatementSize,
            workQueue: workQueue,
            operationQueue: operationQueue,
            logger: logger
        )
    }
}

extension MessageExchangeServiceFactory: MessageExchageServiceMaking {
    func makeService<M: MessageExchange.CodableMessage>(
        statementStoreConnection: StatementStoreConnecting,
        delegate: AnyPeerSessionDelegate<M>,
        compactorFactory: AnyMessageCompactorFactory<M>? = nil
    ) throws -> AnyMessageExchangeService<M> {
        let subscriptionFactory = StatementSubscriptionFactory(
            statementStoreFetcher: statementStoreConnection,
            workQueue: workQueue,
            operationQueue: operationQueue,
            logger: logger
        )

        let sessionFactory = PeerSessionFactory<M>(
            delegate: delegate,
            workQueue: workQueue,
            submitter: statementStoreConnection,
            encryptionManager: encryptionManager,
            deviceEncryptionKeyFactory: deviceEncryptionKeyFactory,
            messageExchangeModeProvider: messageExchangeModeProvider,
            signerManager: signManager,
            sessionIdFactory: PeerSessionIdFactory(),
            channelFactory: ChatStatementChannelFactory(),
            preSendHandler: AnyPeerSessionPreSendHandler.empty(),
            subscriptionFactory: subscriptionFactory,
            maxStatementSize: maxStatementSize,
            compactorFactory: compactorFactory,
            submissionGate: submissionGate,
            operationQueue: operationQueue,
            logger: logger
        )

        let sessionManager = PeerSessionManager(
            sessionFactory: AnyPeerSessionFactory(sessionFactory),
            workQueue: workQueue,
            logger: logger
        )

        let messageExchangeService = MessageExchangeService(
            sessionManager: AnyPeerSessionManager(sessionManager)
        )

        return AnyMessageExchangeService(messageExchangeService)
    }
}

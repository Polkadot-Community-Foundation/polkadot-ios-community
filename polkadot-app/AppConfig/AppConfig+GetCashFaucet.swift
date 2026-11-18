#if TESTNET_FEATURE
    extension AppConfig {
        enum GetCashFaucet {
            /// H160 of the Get CASH faucet contract on Asset Hub. Its `claim(...)` calls from Get CASH's own
            /// product account are signed without the signing sheet. The zero address turns that off.
            static let claimContract = "0x0000000000000000000000000000000000000000"
        }
    }
#endif

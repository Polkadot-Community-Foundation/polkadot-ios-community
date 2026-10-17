import Testing
@testable import polkadot_app

struct LegacyRuntimeProductsTests {
    @Test
    func getCashRunsNative() {
        #expect(LegacyRuntimeProducts.runsNative(productName: "getcash"))
    }

    @Test
    func otherProductsKeepTheSelectedRuntime() {
        #expect(!LegacyRuntimeProducts.runsNative(productName: "browse"))
        #expect(!LegacyRuntimeProducts.runsNative(productName: "getcash-next"))
        #expect(!LegacyRuntimeProducts.runsNative(productName: "app.getcash"))
    }
}

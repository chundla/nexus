import Testing

@testable import nexus

struct NexusAppBootstrapTests {
    @Test func appBootstrapListeningPortKeepsFixedRemoteAccessPortOutsideXCTest() {
        #expect(
            NexusAppModel.appBootstrapListeningPort(environment: [:]) == NexusAppModel.defaultRemoteAccessListeningPort)
    }

    @Test func appBootstrapListeningPortUsesEphemeralPortWhenRunningUnderXCTest() {
        #expect(
            NexusAppModel.appBootstrapListeningPort(environment: [
                "XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"
            ]) == nil)
        #expect(
            NexusAppModel.appBootstrapListeningPort(environment: ["XCTestBundlePath": "/tmp/nexusTests.xctest"]) == nil)
    }
}

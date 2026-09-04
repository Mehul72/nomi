import Foundation
import Testing
@testable import Nomi

struct SmokeTests {
    @Test func testRunnerIsDetected() {
        #expect(ProcessInfo.processInfo.isRunningUnitTests)
    }
}

import Testing
import Foundation
@testable import myleaf

@MainActor
@Suite(.serialized)
struct MemoryMonitorTests {

    @Test func reportsMemoryFootprint() {
        let monitor = MemoryMonitor.shared
        monitor.sampleNow()

        #expect(monitor.currentFootprint > 0)
        #expect(monitor.peakFootprint >= monitor.currentFootprint)
        #expect(monitor.lastSampleDate != nil)
        #expect(monitor.sampleCount > 0)
    }
}

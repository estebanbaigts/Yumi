import Testing
import Foundation

@Suite struct MacVitalsTests {
    @Test func heatComesFirst() {
        #expect(MacStrain.from(thermal: .serious, cpuLoad: 0.99, previousLoad: 0.99, memoryUsed: 0.99) == .hot)
        #expect(MacStrain.from(thermal: .critical, cpuLoad: nil, previousLoad: nil, memoryUsed: nil) == .hot)
    }

    @Test func theProcessorCountsOnlyWhenItStaysBusy() {
        #expect(MacStrain.from(thermal: .nominal, cpuLoad: 0.95, previousLoad: 0.2, memoryUsed: 0.5) == nil)
        #expect(MacStrain.from(thermal: .fair, cpuLoad: 0.95, previousLoad: 0.9, memoryUsed: 0.5) == .busy)
    }

    @Test func memoryNearlyFull() {
        #expect(MacStrain.from(thermal: .nominal, cpuLoad: 0.1, previousLoad: 0.1, memoryUsed: 0.95) == .memory)
        #expect(MacStrain.from(thermal: .nominal, cpuLoad: 0.1, previousLoad: 0.1, memoryUsed: 0.6) == nil)
    }

    @Test func loadBetweenTwoReadings() {
        let a = MacVitals.Ticks(busy: 100, total: 400), b = MacVitals.Ticks(busy: 175, total: 500)
        #expect(MacVitals.load(from: a, to: b) == 0.75)
        #expect(MacVitals.load(from: b, to: a) == nil)
        #expect(MacVitals.ticks() != nil)
        #expect((MacVitals.memoryUsed() ?? -1) >= 0)
    }
}

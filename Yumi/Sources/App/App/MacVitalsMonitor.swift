import Foundation

/// Reads how the Mac is doing every few seconds and puts it in `AppState.macStrain`, so Yumi
/// can show it (a glass of water when it is hot, worn out when it struggles). Local only:
/// kernel counters and the thermal state, nothing sent, nothing kept. Off while filming.
@MainActor
final class MacVitalsMonitor {
    static let shared = MacVitalsMonitor()
    /// The setting: Yumi reacts to the state of the Mac. On by default.
    static let defaultsKey = "macVitalsEnabled"
    private static let interval: TimeInterval = 10

    private var timer: Timer?
    private var ticks: MacVitals.Ticks?
    private var lastLoad: Double?

    func start() {
        guard !StudioMode.isOn, timer == nil else { return }
        UserDefaults.standard.register(defaults: [Self.defaultsKey: true])
        ticks = MacVitals.ticks()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { _ in
            MainActor.assumeIsolated { MacVitalsMonitor.shared.sample() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        guard UserDefaults.standard.bool(forKey: Self.defaultsKey) else {
            if AppState.shared.macStrain != nil { AppState.shared.macStrain = nil }
            return
        }
        let now = MacVitals.ticks()
        let load = zip(ticks, now).flatMap { MacVitals.load(from: $0, to: $1) }
        ticks = now
        let strain = MacStrain.from(thermal: ProcessInfo.processInfo.thermalState, cpuLoad: load,
                                    previousLoad: lastLoad, memoryUsed: MacVitals.memoryUsed())
        lastLoad = load
        if AppState.shared.macStrain != strain { AppState.shared.macStrain = strain }
    }
}

private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}

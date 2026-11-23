import Foundation
import Darwin

/// How the Mac is doing, as far as Yumi shows it: hot, busy, short of memory, or fine.
/// Everything is read on the Mac itself (no network, nothing kept).
enum MacStrain: String, Equatable, Sendable {
    /// The Mac is hot (thermal state serious or critical).
    case hot
    /// The processor has been very busy for a while.
    case busy
    /// Memory is nearly full: the Mac starts to slow down.
    case memory

    /// Thresholds: high enough that Yumi only reacts when the person would feel it.
    static let busyLoad = 0.85
    static let memoryUsed = 0.92

    /// The strain to show, the most pressing first. `cpuLoad` and `memoryUsed` go from 0 to 1;
    /// the processor only counts when two readings in a row are high (`previousLoad`).
    static func from(thermal: ProcessInfo.ThermalState, cpuLoad: Double?, previousLoad: Double?,
                     memoryUsed: Double?) -> MacStrain? {
        if thermal == .serious || thermal == .critical { return .hot }
        if let memoryUsed, memoryUsed >= Self.memoryUsed { return .memory }
        if let cpuLoad, let previousLoad, cpuLoad >= busyLoad, previousLoad >= busyLoad { return .busy }
        return nil
    }
}

/// Reads the processor ticks and the memory, from the kernel's own counters.
enum MacVitals {
    struct Ticks: Equatable, Sendable {
        var busy: UInt64
        var total: UInt64
    }

    /// The processor's ticks since start-up, all cores together.
    static func ticks() -> Ticks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return Ticks(busy: user + system + nice, total: user + system + nice + idle)
    }

    /// The share of time the processor was busy between two readings, from 0 to 1.
    static func load(from old: Ticks, to new: Ticks) -> Double? {
        guard new.total > old.total, new.busy >= old.busy else { return nil }
        return Double(new.busy - old.busy) / Double(new.total - old.total)
    }

    /// The share of memory in use (active, wired and compressed), from 0 to 1.
    static func memoryUsed() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = Double(getpagesize())
        let used = Double(UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        return total > 0 ? min(used / total, 1) : nil
    }
}

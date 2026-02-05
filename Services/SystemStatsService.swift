// SystemStatsService.swift
// MacIsland
//
// Monitors CPU usage, memory pressure, and network throughput.
// CPU: Mach host_processor_info for per-CPU ticks, delta-computed.
// Memory: host_statistics64 for vm_statistics64.
// Network: getifaddrs byte counter deltas for upload/download speed.
// Polls every 2s.

import Foundation
import Combine

@MainActor
final class SystemStatsService: ObservableObject {

    @Published var cpuUsage: Double = 0.0             // 0.0 - 1.0
    @Published var memoryUsage: Double = 0.0           // 0.0 - 1.0
    @Published var memoryUsedGB: Double = 0.0
    @Published var memoryTotalGB: Double = 0.0
    @Published var networkDownSpeed: Double = 0.0      // bytes/sec
    @Published var networkUpSpeed: Double = 0.0        // bytes/sec
    @Published var isHighCPU: Bool = false

    private nonisolated(unsafe) var pollTimer: Timer?

    // CPU tracking — store raw integer values
    private var previousCPUTicks: [Int32] = []
    private var previousNumCPUs: natural_t = 0

    // Network tracking
    private var previousBytesIn: UInt64 = 0
    private var previousBytesOut: UInt64 = 0
    private var previousNetworkTime: Date = Date()

    init() {
        readMemory()
        initializeCPU()
        initializeNetwork()
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - CPU Usage

    private func initializeCPU() {
        _ = readCPU()
    }

    private func readCPU() -> Double {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else {
            return cpuUsage
        }

        // Copy raw ticks into a Swift array
        let tickCount = Int(numCPUInfo)
        let currentTicks = Array(UnsafeBufferPointer(start: cpuInfo, count: tickCount))

        var totalUsage: Double = 0
        var cpuCount: Int = 0

        if previousNumCPUs == numCPUs && !previousCPUTicks.isEmpty {
            for i in 0..<Int(numCPUs) {
                let offset = Int(CPU_STATE_MAX) * i
                let currentUser   = Double(currentTicks[offset + Int(CPU_STATE_USER)])
                let currentSystem = Double(currentTicks[offset + Int(CPU_STATE_SYSTEM)])
                let currentNice   = Double(currentTicks[offset + Int(CPU_STATE_NICE)])
                let currentIdle   = Double(currentTicks[offset + Int(CPU_STATE_IDLE)])

                let prevUser   = Double(previousCPUTicks[offset + Int(CPU_STATE_USER)])
                let prevSystem = Double(previousCPUTicks[offset + Int(CPU_STATE_SYSTEM)])
                let prevNice   = Double(previousCPUTicks[offset + Int(CPU_STATE_NICE)])
                let prevIdle   = Double(previousCPUTicks[offset + Int(CPU_STATE_IDLE)])

                let userDelta   = currentUser - prevUser
                let systemDelta = currentSystem - prevSystem
                let niceDelta   = currentNice - prevNice
                let idleDelta   = currentIdle - prevIdle

                let totalDelta = userDelta + systemDelta + niceDelta + idleDelta
                if totalDelta > 0 {
                    let usage = (userDelta + systemDelta + niceDelta) / totalDelta
                    totalUsage += usage
                    cpuCount += 1
                }
            }
        }

        // Save current snapshot
        previousCPUTicks = currentTicks
        previousNumCPUs = numCPUs

        // Deallocate mach memory
        vm_deallocate(
            mach_task_self_,
            vm_address_t(bitPattern: cpuInfo),
            vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
        )

        if cpuCount > 0 {
            let avg = totalUsage / Double(cpuCount)
            cpuUsage = avg
            isHighCPU = avg > 0.8
            return avg
        }

        return cpuUsage
    }

    // MARK: - Memory

    func readMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize

        let used = active + wired + compressed
        let total = Double(ProcessInfo.processInfo.physicalMemory)

        memoryUsedGB = used / (1024 * 1024 * 1024)
        memoryTotalGB = total / (1024 * 1024 * 1024)
        memoryUsage = total > 0 ? used / total : 0
    }

    // MARK: - Network Speed

    private func initializeNetwork() {
        let (bytesIn, bytesOut) = readNetworkBytes()
        previousBytesIn = bytesIn
        previousBytesOut = bytesOut
        previousNetworkTime = Date()
    }

    private func readNetworkSpeed() {
        let (bytesIn, bytesOut) = readNetworkBytes()
        let now = Date()
        let elapsed = now.timeIntervalSince(previousNetworkTime)

        if elapsed > 0 {
            let downDelta = bytesIn > previousBytesIn ? bytesIn - previousBytesIn : 0
            let upDelta = bytesOut > previousBytesOut ? bytesOut - previousBytesOut : 0

            networkDownSpeed = Double(downDelta) / elapsed
            networkUpSpeed = Double(upDelta) / elapsed
        }

        previousBytesIn = bytesIn
        previousBytesOut = bytesOut
        previousNetworkTime = now
    }

    private func readNetworkBytes() -> (UInt64, UInt64) {
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (0, 0)
        }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let name = String(cString: ptr.pointee.ifa_name)
            if name.hasPrefix("en") || name.hasPrefix("utun") || name.hasPrefix("pdp_ip") {
                if let data = ptr.pointee.ifa_data {
                    let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                    bytesIn += UInt64(ifData.ifi_ibytes)
                    bytesOut += UInt64(ifData.ifi_obytes)
                }
            }

            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        return (bytesIn, bytesOut)
    }

    // MARK: - Formatting

    func formatBytes(_ bytes: Double) -> String {
        if bytes < 1024 { return "\(Int(bytes)) B/s" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB/s", bytes / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB/s", bytes / (1024 * 1024)) }
        return String(format: "%.1f GB/s", bytes / (1024 * 1024 * 1024))
    }

    // MARK: - Polling

    private func startPolling() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                _ = self.readCPU()
                self.readMemory()
                self.readNetworkSpeed()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}

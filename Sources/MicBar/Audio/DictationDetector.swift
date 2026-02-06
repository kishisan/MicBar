import Carbon
import Darwin
import Foundation

final class DictationDetector {
    /// Callback triggered when dictation state changes (for immediate UI update)
    static var onStateChanged: (() -> Void)?

    // MARK: - Event-driven detection via input source notifications

    /// True when the current input source is DictationIM
    private(set) static var isDictating = false
    private static var observer: NSObjectProtocol?

    /// Start listening for input source changes. When macOS Dictation activates,
    /// the input source switches to DictationIM — this notification fires instantly.
    static func startMonitoring() {
        // Check initial state
        isDictating = currentInputSourceIsDictation()

        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil,
            queue: .main
        ) { _ in
            let wasDictating = isDictating
            isDictating = currentInputSourceIsDictation()

            #if DEBUG
            NSLog("[MicBar] Input source changed: isDictating=%d", isDictating ? 1 : 0)
            #endif

            if isDictating != wasDictating {
                // Reset CPU tracking on dictation end to avoid stale delta
                if !isDictating {
                    lastCpuTime = 0
                }
                onStateChanged?()
            }
        }

        #if DEBUG
        NSLog("[MicBar] DictationDetector monitoring started, initial isDictating=%d", isDictating ? 1 : 0)
        #endif
    }

    static func stopMonitoring() {
        if let obs = observer {
            DistributedNotificationCenter.default().removeObserver(obs)
            observer = nil
        }
        isDictating = false
    }

    private static func currentInputSourceIsDictation() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return false
        }
        let sourceID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        #if DEBUG
        NSLog("[MicBar] Current input source: %@", sourceID)
        #endif
        return sourceID.contains("Dictation")
    }

    // MARK: - Public API

    /// Returns true if dictation is active.
    /// Primary: event-driven via input source notification (instant).
    /// Fallback: CPU time tracking for edge cases where notification doesn't fire.
    static func isActive() -> Bool {
        if isDictating { return true }
        return isCpuActive()
    }

    // MARK: - CPU-based fallback

    private static var trackedPid: pid_t = 0
    private static var lastCpuTime: UInt64 = 0

    private static func isCpuActive() -> Bool {
        let procs = scanProcesses()

        guard let dictation = procs.first(where: { $0.name == "DictationIM" }) else {
            trackedPid = 0
            lastCpuTime = 0
            return false
        }

        let cpuTime = processCpuTime(dictation.pid)

        if dictation.pid != trackedPid {
            trackedPid = dictation.pid
            lastCpuTime = cpuTime
            return false
        }

        let previousCpu = lastCpuTime
        lastCpuTime = cpuTime

        if previousCpu == 0 { return false }

        let cpuDelta = cpuTime - previousCpu
        let active = cpuDelta > 100_000

        #if DEBUG
        if active {
            NSLog("[MicBar] DictationIM CPU fallback: pid=%d cpuDelta=%llu", dictation.pid, cpuDelta)
        }
        #endif

        return active
    }

    private static func processCpuTime(_ pid: pid_t) -> UInt64 {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard ret > 0 else { return 0 }
        return info.pti_total_user + info.pti_total_system
    }

    // MARK: - Process Scanning

    private struct ProcEntry {
        let pid: pid_t
        let name: String
    }

    private static func scanProcesses() -> [ProcEntry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0

        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return []
        }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)

        guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else {
            return []
        }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride
        var result: [ProcEntry] = []

        for i in 0..<actualCount {
            var p = procs[i]
            let pid = p.kp_proc.p_pid
            let name = withUnsafePointer(to: &p.kp_proc.p_comm) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 17) { cStr in
                    String(cString: cStr)
                }
            }
            if !name.isEmpty {
                result.append(ProcEntry(pid: pid, name: name))
            }
        }

        return result
    }
}

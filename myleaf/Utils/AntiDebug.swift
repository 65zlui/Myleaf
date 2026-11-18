import Foundation

/// Runtime hardening utilities for release builds.
enum AntiDebug {

    /// Enable anti-debugging protections. Call once at app launch.
    /// Has no effect in DEBUG builds.
    static func apply() {
        #if DEBUG
        return
        #else
        denyPtrace()
        checkDebuggerAndExit()
        #endif
    }

    // MARK: - ptrace PT_DENY_ATTACH

    @_silgen_name("ptrace")
    private static func c_ptrace(_ request: Int32, _ pid: Int32, _ addr: UnsafeMutableRawPointer?, _ data: Int32) -> Int32

    private static func denyPtrace() {
        // Prevent debugger attachment via ptrace.
        // On macOS PT_DENY_ATTACH is request number 31 (not 0, which is
        // PT_TRACE_ME). A failure here is not fatal — hardened runtime or a
        // restricted environment can reject the request; the sysctl check
        // below still detects an already-attached debugger.
        let PT_DENY_ATTACH: Int32 = 31
        _ = c_ptrace(PT_DENY_ATTACH, 0, nil, 0)
    }

    // MARK: - sysctl debugger detection

    private static func checkDebuggerAndExit() {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride

        let rc = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard rc == 0 else { return }

        let flags = info.kp_proc.p_flag
        let P_TRACED: Int32 = 0x00000800

        if (flags & P_TRACED) != 0 {
            // Debugger is attached
            exit(1)
        }
    }
}

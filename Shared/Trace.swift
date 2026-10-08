import AppKit

/// Opt-in launch timing for performance checks: `open --env MINMD_TRACE=/tmp/trace.log -a minmd file.md`.
/// Appends `event <seconds since process start>` lines. Does nothing unless the variable is set.
enum Trace {
    private static let path = ProcessInfo.processInfo.environment["MINMD_TRACE"]

    static func mark(_ event: String) {
        guard let path else { return }
        let now = Date().timeIntervalSince1970
        let line = String(format: "%@ %.1f %.4f\n", event, (now - processStart) * 1000, now)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: Data(line.utf8))
        }
    }

    /// Called once per window, on its first frame.
    static func firstDraw() {
        mark("first-draw")
    }

    /// Process start time from the kernel, so time spent before `main` is included.
    private static let processStart: TimeInterval = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        let start = info.kp_proc.p_un.__p_starttime
        return TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000
    }()
}

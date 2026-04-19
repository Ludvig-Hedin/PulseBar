import Foundation
import AppKit

enum KillResult {
    case gracefulRequested
    case forceSucceeded
    case failed
}

struct KillService {
    func gracefulQuit(pid: Int32) -> KillResult {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return .failed }
        let ok = app.terminate()
        return ok ? .gracefulRequested : .failed
    }

    func forceQuit(pid: Int32) -> KillResult {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return .failed }
        let ok = app.forceTerminate()
        return ok ? .forceSucceeded : .failed
    }
}

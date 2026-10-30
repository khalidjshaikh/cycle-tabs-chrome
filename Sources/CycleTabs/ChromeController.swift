import Foundation

/// Drives Google Chrome through its AppleScript interface.
enum ChromeController {

    enum Direction {
        case next
        case previous
    }

    enum CycleError: LocalizedError {
        case chromeNotRunning
        case noWindows
        case singleTab
        case automationDenied
        case scriptFailed(code: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .chromeNotRunning:
                return "Google Chrome isn’t running."
            case .noWindows:
                return "Google Chrome has no open windows."
            case .singleTab:
                return "Only one tab is open."
            case .automationDenied:
                return "macOS blocked access to Google Chrome. Allow CycleTabs under System Settings › Privacy & Security › Automation."
            case let .scriptFailed(code, message):
                return "Chrome scripting failed (\(code)): \(message)"
            }
        }
    }

    /// AppleScript error code returned when the user denies the Automation prompt
    /// or the permission was previously revoked.
    private static let automationErrorCode = -1743

    /// Runs on a private serial queue so the UI (and the global hotkey) never
    /// blocks while Chrome is responding.
    private static let queue = DispatchQueue(label: "com.kshaikh.cycletabs.applescript")

    /// Cycles one tab in Chrome's front window and returns the new tab's index (1-based).
    static func cycle(_ direction: Direction, activateChrome: Bool) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try runScript(direction, activateChrome: activateChrome))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Blocking variant used by the command line mode (`--next` / `--previous`).
    static func cycleBlocking(_ direction: Direction, activateChrome: Bool) throws -> Int {
        try queue.sync {
            try runScript(direction, activateChrome: activateChrome)
        }
    }

    private static func runScript(_ direction: Direction, activateChrome: Bool) throws -> Int {        guard let script = NSAppleScript(source: scriptSource(direction, activateChrome: activateChrome)) else {
            throw CycleError.scriptFailed(code: -1, message: "Could not build AppleScript.")
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? -1
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
            if code == automationErrorCode {
                throw CycleError.automationDenied
            }
            switch message {
            case "CYCLE_NOT_RUNNING": throw CycleError.chromeNotRunning
            case "CYCLE_NO_WINDOWS": throw CycleError.noWindows
            case "CYCLE_SINGLE_TAB": throw CycleError.singleTab
            default: throw CycleError.scriptFailed(code: code, message: message)
            }
        }

        return Int(result.int32Value)
    }

    private static func scriptSource(_ direction: Direction, activateChrome: Bool) -> String {
        // `newIndex` is computed in AppleScript so the wrap-around stays a single
        // round trip: Chrome reports the new active index back to us.
        let advance = """
              if currentIndex is greater than or equal to tabCount then
                  set newIndex to 1
              else
                  set newIndex to currentIndex + 1
              end if
        """

        let rewind = """
              if currentIndex is less than or equal to 1 then
                  set newIndex to tabCount
              else
                  set newIndex to currentIndex - 1
              end if
        """

        let activate = activateChrome ? "\n    activate" : ""

        return """
        tell application "Google Chrome"
            if application "Google Chrome" is not running then error "CYCLE_NOT_RUNNING"
            if (count of windows) is 0 then error "CYCLE_NO_WINDOWS"

            set targetWindow to front window
            set tabCount to count of tabs of targetWindow
            if tabCount is less than 2 then error "CYCLE_SINGLE_TAB"

            set currentIndex to active tab index of targetWindow
        \(direction == .next ? advance : rewind)

            set active tab index of targetWindow to newIndex\(activate)
            return newIndex
        end tell
        """
    }
}

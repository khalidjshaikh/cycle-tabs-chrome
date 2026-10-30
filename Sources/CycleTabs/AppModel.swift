import AppKit
import Observation
import ServiceManagement

/// Options that can be supplied on the command line, for example:
/// `CycleTabs.app/Contents/MacOS/CycleTabs --interval 30`
enum LaunchOptions {
    /// Seconds between automatic tab switches, if `--interval <seconds>` was passed.
    static let interval: Int? = {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--interval"),
              arguments.index(after: flagIndex) < arguments.endIndex,
              let seconds = Int(arguments[arguments.index(after: flagIndex)]),
              (5...3600).contains(seconds)
        else {
            return nil
        }
        return seconds
    }()
}

@MainActor
@Observable
final class AppModel {

    private static let activateChromeKey = "activateChromeOnSwitch"
    private static let intervalKey = "cycleIntervalSeconds"
    private static let autoCyclingKey = "autoCycleEnabled"

    static let defaultInterval = 60
    static let intervalChoices = [10, 30, 60, 120, 300, 600]

    /// Whether Chrome should be brought to the front after switching tabs.
    var activateChrome: Bool {
        didSet { UserDefaults.standard.set(activateChrome, forKey: Self.activateChromeKey) }
    }

    var launchAtLogin: Bool {
        didSet { updateLaunchAtLogin() }
    }

    /// Seconds between automatic tab switches.
    var interval: Int {
        didSet {
            UserDefaults.standard.set(interval, forKey: Self.intervalKey)
            if isAutoCycling {
                startTimer(resetCountdown: true)
            } else {
                remaining = interval
            }
        }
    }

    /// Whether the timer currently drives tab switches.
    private(set) var isAutoCycling: Bool {
        didSet { UserDefaults.standard.set(isAutoCycling, forKey: Self.autoCyclingKey) }
    }

    /// Seconds left until the next automatic switch. Shown in the menu bar.
    private(set) var remaining: Int

    /// Human readable result of the most recent switch, shown in the menu.
    private(set) var lastAction: String?

    /// Most recent failure, shown in the menu until the next successful switch.
    private(set) var lastError: String?

    /// Set when a global shortcut could not be registered.
    private(set) var hotKeyWarning: String?

    private var timer: Timer?
    private var isCycling = false
    private var isSyncingLaunchAtLogin = false

    init() {
        let defaults = UserDefaults.standard

        let activate: Bool
        if defaults.object(forKey: Self.activateChromeKey) == nil {
            activate = true
        } else {
            activate = defaults.bool(forKey: Self.activateChromeKey)
        }
        activateChrome = activate

        let storedInterval = defaults.object(forKey: Self.intervalKey) as? Int
        let resolvedInterval = LaunchOptions.interval ?? storedInterval ?? Self.defaultInterval
        interval = resolvedInterval
        if let override = LaunchOptions.interval {
            defaults.set(override, forKey: Self.intervalKey)
        }

        let autoCycle: Bool
        if defaults.object(forKey: Self.autoCyclingKey) == nil {
            autoCycle = true
        } else {
            autoCycle = defaults.bool(forKey: Self.autoCyclingKey)
        }
        isAutoCycling = autoCycle

        remaining = resolvedInterval

        launchAtLogin = SMAppService.mainApp.status == .enabled
        registerHotKeys()

        if autoCycle {
            startTimer(resetCountdown: true)
        }
    }

    // MARK: - Cycling

    func cycle(_ direction: ChromeController.Direction, interactive: Bool = true) {
        guard !isCycling else { return }
        isCycling = true

        let activate = activateChrome
        Task {
            do {
                let index = try await ChromeController.cycle(direction, activateChrome: activate)
                lastAction = "Tab \(index) is active"
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                // Only beep for something the user just triggered; a repeating
                // timer failure would otherwise beep once per interval forever.
                if interactive {
                    NSSound.beep()
                }
            }
            isCycling = false
        }
    }

    // MARK: - Auto-cycling

    func toggleAutoCycling() {
        isAutoCycling.toggle()
        if isAutoCycling {
            startTimer(resetCountdown: true)
        } else {
            stopTimer()
        }
    }

    private func startTimer(resetCountdown: Bool) {
        stopTimer()
        if resetCountdown {
            remaining = interval
        }

        // `.common` mode keeps the countdown ticking while a menu is open.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard remaining > 1 else {
            remaining = interval
            cycle(.next, interactive: false)
            return
        }
        remaining -= 1
    }

    // MARK: - Helpers

    func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    static func label(for seconds: Int) -> String {
        switch seconds {
        case 60: return "1 minute"
        case 120: return "2 minutes"
        case 300: return "5 minutes"
        case 600: return "10 minutes"
        default: return "\(seconds) seconds"
        }
    }

    private func registerHotKeys() {
        let nextOK = HotKeyManager.shared.register(HotKeyManager.nextTab) { [weak self] in
            self?.cycle(.next)
        }
        let previousOK = HotKeyManager.shared.register(HotKeyManager.previousTab) { [weak self] in
            self?.cycle(.previous)
        }

        if !nextOK || !previousOK {
            hotKeyWarning = "A global shortcut is already taken by another app."
        }
    }

    private func updateLaunchAtLogin() {
        guard !isSyncingLaunchAtLogin else { return }
        isSyncingLaunchAtLogin = true
        defer { isSyncingLaunchAtLogin = false }

        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            lastError = "Could not update login item: \(error.localizedDescription)"
            // Reflect the real state instead of the toggle's optimistic value.
            launchAtLogin = service.status == .enabled
        }
    }
}

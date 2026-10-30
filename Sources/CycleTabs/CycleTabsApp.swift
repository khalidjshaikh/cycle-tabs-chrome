import AppKit
import SwiftUI

@main
struct CycleTabsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Behave like a menu bar utility even when launched outside a bundle
        // (for example with `swift run`).
        NSApp.setActivationPolicy(.accessory)

        // Command line mode: `CycleTabs --next` / `CycleTabs --previous`.
        // Handy for testing, or for wiring the app into a third party hotkey tool.
        let arguments = CommandLine.arguments
        let direction: ChromeController.Direction?
        if arguments.contains("--next") {
            direction = .next
        } else if arguments.contains("--previous") {
            direction = .previous
        } else {
            direction = nil
        }

        guard let direction else { return }

        do {
            let index = try ChromeController.cycleBlocking(direction, activateChrome: true)
            print("Switched to tab \(index)")
            exit(EXIT_SUCCESS)
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(EXIT_FAILURE)
        }
    }
}

struct MenuBarLabel: View {
    var model: AppModel

    var body: some View {
        if model.isAutoCycling {
            // The countdown itself is the label, so the seconds are readable
            // without opening the menu.
            Text(verbatim: "\(model.remaining)")
                .monospacedDigit()
        } else {
            Image(systemName: "arrow.left.arrow.right.square")
        }
    }
}

struct MenuContent: View {
    @Bindable var model: AppModel

    var body: some View {
        Text(countdownText)

        Button(model.isAutoCycling ? "Pause Auto-Cycle" : "Resume Auto-Cycle") {
            model.toggleAutoCycling()
        }

        Picker("Cycle Every", selection: $model.interval) {
            ForEach(intervalChoices, id: \.self) { seconds in
                Text(AppModel.label(for: seconds)).tag(seconds)
            }
        }

        Divider()

        Button("Next Tab Now   \(HotKeyManager.nextTab.displayString)") {
            model.cycle(.next)
        }

        Button("Previous Tab Now   \(HotKeyManager.previousTab.displayString)") {
            model.cycle(.previous)
        }

        Divider()

        Toggle("Bring Chrome to front", isOn: $model.activateChrome)
        Toggle("Launch at Login", isOn: $model.launchAtLogin)

        if let warning = model.hotKeyWarning {
            Divider()
            Text(warning)
        }

        if let error = model.lastError {
            Divider()
            Text(error)
            Button("Open Automation Settings…") {
                model.openAutomationSettings()
            }
        } else if let action = model.lastAction {
            Divider()
            Text(action)
        }

        Divider()

        Button("Quit CycleTabs") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Presets plus the current value, so an interval passed with
    /// `--interval 45` still shows up as the checked item.
    private var intervalChoices: [Int] {
        var choices = AppModel.intervalChoices
        if !choices.contains(model.interval) {
            choices.append(model.interval)
            choices.sort()
        }
        return choices
    }

    private var countdownText: String {
        guard model.isAutoCycling else {
            return "Auto-cycle paused · every \(AppModel.label(for: model.interval))"
        }
        let seconds = model.remaining
        return "Next tab in \(seconds)s · every \(AppModel.label(for: model.interval))"
    }
}

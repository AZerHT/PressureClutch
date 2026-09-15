import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let clutch = ClutchTap()
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    /// Every drag waits on the event tap: App Nap must never slow this windowless app down.
    private var latencyCriticalActivity: NSObjectProtocol?
    private let speedLabel = NSTextField(labelWithString: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "PressureClutch")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        DebugLog.write("launch: trackpad found = \(ForceReader.shared.start())")
        clutch.onChange = { [weak self] _, _ in
            // A held key is felt already; a press on glass isn't.
            guard self?.settings.trigger == .pressure else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        clutch.update(settings.clutchConfig)

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startClutch()
        } else {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.startClutch()
            }
        }
    }

    private func startClutch() {
        latencyCriticalActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Event tap on drags"
        )
        DebugLog.write("event tap started = \(clutch.start())")
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let title = NSMenuItem(title: "PressureClutch", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        if !AXIsProcessTrusted() {
            let permission = NSMenuItem(title: "Autoriser dans Accessibilité…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            permission.target = self
            menu.addItem(permission)
        }
        menu.addItem(.separator())

        menu.addItem(toggle("Activé", on: settings.enabled, action: #selector(toggleEnabled)))
        menu.addItem(submenu("Ralentir en", choices: ClutchTap.Trigger.allCases.map { ($0.title, $0.rawValue, settings.trigger == $0) },
                             action: #selector(chooseTrigger(_:))))
        if settings.trigger == .pressure {
            menu.addItem(submenu("Pression nécessaire", choices: Sensitivity.allCases.map { ($0.title, $0.rawValue, settings.sensitivity == $0) },
                                 action: #selector(chooseSensitivity(_:))))
        }

        menu.addItem(.separator())
        menu.addItem(speedItem())
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// A slider from ÷2 to ÷20: how many times slower the pointer goes while the trigger is held.
    private func speedItem() -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 52))

        speedLabel.frame = NSRect(x: 20, y: 30, width: 210, height: 17)
        speedLabel.font = .menuFont(ofSize: 0)
        view.addSubview(speedLabel)

        let slider = NSSlider(value: settings.slowdown, minValue: 2, maxValue: 20, target: self, action: #selector(speedChanged(_:)))
        slider.frame = NSRect(x: 18, y: 4, width: 214, height: 24)
        slider.numberOfTickMarks = 19
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        view.addSubview(slider)

        updateSpeedLabel()
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private func updateSpeedLabel() {
        speedLabel.stringValue = "Vitesse ralentie : ÷\(Int(settings.slowdown.rounded()))"
    }

    private func toggle(_ title: String, on: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    private func submenu(_ title: String, choices: [(title: String, value: String, on: Bool)], action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for choice in choices {
            let choiceItem = toggle(choice.title, on: choice.on, action: action)
            choiceItem.representedObject = choice.value
            submenu.addItem(choiceItem)
        }
        item.submenu = submenu
        return item
    }

    @objc private func speedChanged(_ sender: NSSlider) {
        settings.slowdown = sender.doubleValue.rounded()
        updateSpeedLabel()
        clutch.update(settings.clutchConfig)
    }

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        clutch.update(settings.clutchConfig)
    }

    @objc private func chooseTrigger(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let trigger = ClutchTap.Trigger(rawValue: raw) else { return }
        settings.trigger = trigger
        clutch.update(settings.clutchConfig)
    }

    @objc private func chooseSensitivity(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let sensitivity = Sensitivity(rawValue: raw) else { return }
        settings.sensitivity = sensitivity
        clutch.update(settings.clutchConfig)
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

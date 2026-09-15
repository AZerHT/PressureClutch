import AppKit
import Carbon

/// An event tap, on its own thread, that slows the pointer down during a drag — while a key is held, or after a
/// firm press on the trackpad.
///
/// Every drag on the Mac goes through it, so it never waits: it reads the settings the app handed it, the key state
/// carried by the events themselves and the force the trackpad reported last, and leaves everything else to the
/// main thread. It never drops, holds back or adds a mouse event: it only changes where a drag lands, and hides the
/// trigger key from apps so they don't read it as one of their own modifiers.
///
/// The event keeps the finger's real movement, scaled down, while the trackpad's own idea of the pointer keeps going
/// at full speed: the window server follows the event, and the pointer is put back in step when the drag ends.
final class ClutchTap {
    /// What slows the pointer down.
    enum Trigger: String, CaseIterable {
        case function, rightOption, rightCommand, pressure

        var title: String {
            switch self {
            case .function: return "Maintenir fn"
            case .rightOption: return "Maintenir ⌥ droite"
            case .rightCommand: return "Maintenir ⌘ droite"
            case .pressure: return "Appui fort sur le trackpad"
            }
        }

        var keyCode: Int64? {
            switch self {
            case .function: return Int64(kVK_Function)
            case .rightOption: return Int64(kVK_RightOption)
            case .rightCommand: return Int64(kVK_RightCommand)
            case .pressure: return nil
            }
        }

        /// The device-dependent bit telling this very key is down (IOKit's NX_DEVICER*KEYMASK).
        var deviceBit: UInt64 {
            switch self {
            case .rightOption: return 0x40
            case .rightCommand: return 0x10
            case .function, .pressure: return 0
            }
        }

        /// The same modifier on the other side of the keyboard, which apps must keep seeing.
        var otherSideBit: UInt64 {
            switch self {
            case .rightOption: return 0x20
            case .rightCommand: return 0x08
            case .function, .pressure: return 0
            }
        }

        var modifier: CGEventFlags {
            switch self {
            case .function: return .maskSecondaryFn
            case .rightOption: return .maskAlternate
            case .rightCommand: return .maskCommand
            case .pressure: return []
            }
        }

        func isHeld(in flags: CGEventFlags) -> Bool {
            switch self {
            case .pressure: return false
            case .function: return flags.contains(.maskSecondaryFn)
            default: return flags.rawValue & deviceBit != 0
            }
        }
    }

    struct Config {
        var enabled = true
        var trigger: Trigger = .function
        /// Pressure trigger: how far above the lightest force a press has to rise to count.
        var riseToEngage: Float = 100
        /// Pressure trigger: share of the strongest force a press has to lose to be over.
        var dropToRelease: Float = 0.25
        /// Share of the finger's movement the pointer follows while slowed down.
        var gain: Double = 0.1
    }

    /// The pointer was slowed down or given back its speed, with its location (top-left screen coordinates).
    var onChange: ((_ slowed: Bool, _ location: CGPoint) -> Void)?

    private let lock = NSLock()
    private var config = Config()
    private var tap: CFMachPort?
    // Only touched on the tap thread.
    private var dragging = false
    private var slowed = false
    /// Contact frames of this drag seen so far, to start the smoothing on the first one.
    private var dragEvents = 0
    /// The force, smoothed: one odd contact frame must not count as a press.
    private var force: Float = 0
    /// A firm press is under way.
    private var pressing = false
    /// The lightest force since the last press ended.
    private var lightest: Float = .infinity
    /// The strongest force of the current press.
    private var strongest: Float = 0
    /// Where the trackpad put the pointer on the last event, before any change.
    private var lastInput = CGPoint.zero
    /// Where the last event was sent.
    private var lastOutput = CGPoint.zero

    func update(_ newConfig: Config) {
        lock.lock()
        config = newConfig
        lock.unlock()
    }

    private func currentConfig() -> Config {
        lock.lock()
        defer { lock.unlock() }
        return config
    }

    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                return Unmanaged<ClutchTap>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "PressureClutch event tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // MARK: - Tap thread

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        let config = currentConfig()
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            endDrag(at: nil)

        case .flagsChanged:
            guard config.enabled, let keyCode = config.trigger.keyCode else { return pass }
            if event.getIntegerValueField(.keyboardEventKeycode) == keyCode {
                if dragging { setSlowed(config.trigger.isHeld(in: event.flags), at: lastOutput) }
                // Apps never learn the trigger key went down or up.
                return nil
            }
            hideTrigger(from: event, config: config)

        case .leftMouseDown:
            endDrag(at: nil)
            dragging = true
            dragEvents = 0
            lastInput = event.location
            lastOutput = event.location
            hideTrigger(from: event, config: config)

        case .leftMouseDragged:
            let input = event.location
            guard dragging, config.enabled else {
                setSlowed(false, at: input)
                lastInput = input
                lastOutput = input
                return pass
            }

            if config.trigger == .pressure {
                updatePress(config: config, at: lastOutput)
            } else {
                // The events carry the key state: nothing to miss if a key change went unseen.
                setSlowed(config.trigger.isHeld(in: event.flags), at: lastOutput)
            }
            hideTrigger(from: event, config: config)
            dragEvents += 1

            // The finger's real movement since the last event, scaled, added to where the pointer is.
            let gain = slowed ? config.gain : 1
            let output = CGPoint(
                x: lastOutput.x + (input.x - lastInput.x) * gain,
                y: lastOutput.y + (input.y - lastInput.y) * gain
            )
            lastInput = input
            lastOutput = output
            guard output != input else { return pass }

            event.location = output
            if slowed {
                for field in [CGEventField.mouseEventDeltaX, .mouseEventDeltaY] {
                    let delta = Double(event.getIntegerValueField(field))
                    event.setIntegerValueField(field, value: Int64((delta * gain).rounded()))
                }
            }

        case .leftMouseUp:
            guard dragging else { return pass }
            hideTrigger(from: event, config: config)
            let moved = event.location != lastOutput
            if moved { event.location = lastOutput }
            endDrag(at: moved ? lastOutput : nil)

        default:
            break
        }
        return pass
    }

    /// Takes the trigger key out of an event's modifiers, unless the same modifier is also held on the other side.
    private func hideTrigger(from event: CGEvent, config: Config) {
        let trigger = config.trigger
        guard config.enabled, trigger != .pressure, trigger.isHeld(in: event.flags) else { return }
        var raw = event.flags.rawValue & ~trigger.deviceBit
        if trigger.otherSideBit == 0 || raw & trigger.otherSideBit == 0 {
            raw &= ~trigger.modifier.rawValue
        }
        event.flags = CGEventFlags(rawValue: raw)
    }

    /// With the pressure trigger, each new firm press flips the drag between slow and normal speed.
    private func updatePress(config: Config, at location: CGPoint) {
        let raw = ForceReader.shared.force
        force = dragEvents == 0 ? raw : force + (raw - force) * 0.5
        if pressing {
            strongest = max(strongest, force)
            if strongest - force >= max(60, strongest * config.dropToRelease) {
                pressing = false
                lightest = force
            }
        } else {
            lightest = min(lightest, force)
            if force - lightest >= config.riseToEngage {
                pressing = true
                strongest = force
                setSlowed(!slowed, at: location)
            }
        }
    }

    private func setSlowed(_ newValue: Bool, at location: CGPoint) {
        guard newValue != slowed else { return }
        slowed = newValue
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(newValue, location)
        }
    }

    /// `pointer`: where the pointer has to be put back, when the drag left it away from the trackpad's own position.
    private func endDrag(at pointer: CGPoint?) {
        setSlowed(false, at: lastOutput)
        dragging = false
        pressing = false
        lightest = .infinity
        strongest = 0
        if let pointer {
            DispatchQueue.main.async {
                CGWarpMouseCursorPosition(pointer)
                // A warp freezes the pointer for a moment; re-associating the mouse lifts that freeze.
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }
    }
}

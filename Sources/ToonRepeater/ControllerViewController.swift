import AppKit

/// Key-catching root view; swallowing key equivalents stops the system beep on forwarded keys.
final class ControllerView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
    override func flagsChanged(with event: NSEvent) {}
}

/// The small always-available controller window: four window targets, three status indicators and the
/// Click Repeater toggle.
final class ControllerViewController: NSViewController, NSWindowDelegate {
    let brain = MultiBrain()

    private var targetButtons: [[NSButton]] = []   // [group][toon]
    private let groupImage = NSImageView()
    private let stateImage = NSImageView()
    private let throwImage = NSImageView()
    private let repeaterButton = NSButton()

    /// Whether Click Repeater is on; drives the toggle's look.
    var repeaterOn = false { didSet { refreshImages() } }
    /// Called when the Click Repeater toggle is clicked.
    var onToggleRepeater: (() -> Void)?

    /// Height of the Click Repeater strip under the original controller layout.
    static let repeaterStripHeight: CGFloat = 34
    static let contentSize = NSSize(width: 172, height: 94 + repeaterStripHeight)

    private(set) var isListening = false
    private var keyMonitor: Any?
    private var mouseDownMonitor: Any?
    private var lookingForWindow: (group: Int, toon: Int)?

    override func loadView() {
        let view = ControllerView(frame: NSRect(origin: .zero, size: Self.contentSize))
        view.wantsLayer = true

        // Original layout (group 1 targets on top, group 2 below, indicators in the middle), raised to
        // leave room for the Click Repeater toggle along the bottom.
        let lift = Self.repeaterStripHeight
        let frames: [[NSRect]] = [
            [NSRect(x: 28, y: 37 + lift, width: 30, height: 30), NSRect(x: 114, y: 37 + lift, width: 30, height: 30)],
            [NSRect(x: 28, y: 2 + lift, width: 30, height: 30), NSRect(x: 114, y: 2 + lift, width: 30, height: 30)],
        ]
        targetButtons = frames.enumerated().map { group, row in
            row.enumerated().map { toon, frame in
                let button = NSButton(frame: frame)
                button.isBordered = false
                button.imageScaling = .scaleProportionallyUpOrDown
                button.title = ""
                button.tag = group * 2 + toon
                button.target = self
                button.action = #selector(targetClicked(_:))
                button.toolTip = "Group \(group + 1) – \(toon == 0 ? "left" : "right") toon: click, then click a game window"
                view.addSubview(button)
                return button
            }
        }
        groupImage.frame = NSRect(x: 72, y: 59 + lift, width: 30, height: 30)
        stateImage.frame = NSRect(x: 71, y: 21 + lift, width: 30, height: 30)
        throwImage.frame = NSRect(x: 147, y: 69 + lift, width: 20, height: 20)

        repeaterButton.frame = NSRect(x: 4, y: 5, width: 164, height: 26)
        repeaterButton.font = .systemFont(ofSize: 11, weight: .medium)
        repeaterButton.setButtonType(.pushOnPushOff)
        repeaterButton.bezelStyle = .rounded
        repeaterButton.imagePosition = .imageLeading
        repeaterButton.imageScaling = .scaleProportionallyDown
        repeaterButton.focusRingType = .none
        repeaterButton.refusesFirstResponder = true
        repeaterButton.target = self
        repeaterButton.action = #selector(repeaterClicked)
        repeaterButton.toolTip = "Click Repeater: a click in one game window is repeated in the others"
        view.addSubview(repeaterButton)
        groupImage.toolTip = "Active group (press 1 or 2)"
        stateImage.toolTip = "Mode (press ` to switch Multi/Mirror)"
        throwImage.toolTip = "Throw mode (press the Toggle Throw key)"
        [groupImage, stateImage, throwImage].forEach {
            $0.imageScaling = .scaleProportionallyUpOrDown
            view.addSubview($0)
        }
        self.view = view
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let window = view.window else { return }
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.makeFirstResponder(view)

        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: Settings.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appResignedActive),
                                               name: NSApplication.didResignActiveNotification, object: nil)
        applySettings()
        enable()
    }

    // MARK: Settings

    @objc private func settingsChanged() { applySettings() }

    private func applySettings() {
        view.window?.backgroundColor = Settings.colour(.background)
        view.window?.level = Settings.keepOnTop ? .floating : .normal
        brain.setKeepAlive(Settings.keepAlive)
        refreshImages()
    }

    // MARK: Listening

    @objc func toggleListeners(_ sender: Any?) {
        isListening ? disable() : enable()
    }

    func enable() {
        guard !isListening else { return }
        isListening = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            return self.handle(event) ? nil : event
        }
        refreshImages()
    }

    func disable() {
        guard isListening else { return }
        brain.releaseKeys()
        isListening = false
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        refreshImages()
    }

    /// Handles a key event from the controller window. Returns true if it was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        Log.events.debug("key \(event.keyCode) type \(event.type.rawValue) keyWindow=\(NSApp.keyWindow === self.view.window) mode=\(String(describing: self.brain.mode)) group=\(self.brain.group)")
        // Only act while the controller itself is the key window (not Preferences, alerts, etc.).
        guard let window = view.window, NSApp.keyWindow === window, lookingForWindow == nil else { return false }

        // Command shortcuts and the ` hotkey belong to the menu.
        if event.modifierFlags.contains(.command) { brain.releaseKeys(); return false }
        if event.type != .flagsChanged && event.keyCode == KeyCodes.grave {
            if event.type == .keyDown && !event.isARepeat { toggleMode(nil) }
            return true
        }

        let keyCode = event.keyCode

        if keyCode == Settings.toggleThrowKey {
            let pressed = event.type == .keyDown
                || (event.type == .flagsChanged && KeyCodes.isPressed(keyCode, flags: event.modifierFlags))
            if pressed && !(event.type == .keyDown && event.isARepeat) {
                brain.swapThrowMode()
                refreshImages()
            }
            return true
        }

        if brain.mode == .multi && event.type == .keyDown && (keyCode == KeyCodes.one || keyCode == KeyCodes.two) {
            brain.releaseKeys()
            brain.group = (keyCode == KeyCodes.one) ? 0 : 1
            refreshImages()
            return true
        }

        if event.type == .keyDown && event.isARepeat && brain.mode == .multi {
            return true // held movement keys stay down in game; repeats only matter for mirrored typing
        }

        switch brain.mode {
        case .multi: brain.handleMultiMode(event)
        case .mirror: brain.handleMirrorMode(event)
        }
        return true
    }

    @objc private func repeaterClicked() {
        onToggleRepeater?()
        repeaterButton.state = repeaterOn ? .on : .off // the owner decides the real state
    }

    @objc func toggleMode(_ sender: Any?) {
        brain.releaseKeys()
        brain.swapMode()
        refreshImages()
    }

    @objc private func appResignedActive() { brain.releaseKeys() }

    // MARK: Window targets

    @objc private func targetClicked(_ sender: NSButton) {
        selectWindow(group: sender.tag / 2, toon: sender.tag % 2)
    }

    /// Waits for the user to click a game window; clicking back inside the controller clears the slot instead.
    private func selectWindow(group: Int, toon: Int) {
        setButtonsEnabled(false)
        lookingForWindow = (group, toon)
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let slot = self.lookingForWindow else { return event }
            self.brain.clearWindowPID(group: slot.group, toon: slot.toon)
            self.finishSelecting()
            return nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let slot = lookingForWindow else { return }
        // Give the clicked app a moment to become frontmost before reading it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self, let current = self.lookingForWindow,
                  current.group == slot.group, current.toon == slot.toon else { return }
            self.brain.setWindowPID(group: slot.group, toon: slot.toon)
            self.finishSelecting()
        }
    }

    private func finishSelecting() {
        if let monitor = mouseDownMonitor { NSEvent.removeMonitor(monitor) }
        mouseDownMonitor = nil
        lookingForWindow = nil
        setButtonsEnabled(true)
        refreshImages()
    }

    private func setButtonsEnabled(_ enabled: Bool) {
        targetButtons.joined().forEach { $0.isEnabled = enabled }
    }

    // MARK: Images

    /// Redraws targets and indicators, e.g. after windows are linked outside the controller.
    func refreshImages() {
        Analytics.noteLinkedWindows(brain.windowsPID.flatMap { $0 }.compactMap { $0 }.count)
        repeaterButton.state = repeaterOn ? .on : .off
        repeaterButton.image = Images.clickRepeater(colour: repeaterOn ? .systemGreen : .secondaryLabelColor, size: 18)
        repeaterButton.title = repeaterOn ? "Click Repeater: On" : "Click Repeater: Off"
        for group in 0..<2 {
            for toon in 0..<2 {
                let on = brain.windowsPID[group][toon] != nil
                targetButtons[group][toon].image = Images.image(.target, colour: Settings.colour(on ? .targetOn : .targetOff))
            }
        }
        guard isListening else {
            stateImage.image = Images.image(.disabled, colour: Settings.colour(.mode))
            groupImage.image = nil
            throwImage.image = nil
            return
        }
        switch brain.mode {
        case .multi:
            stateImage.image = Images.image(.multi, colour: Settings.colour(.multi))
            groupImage.image = Images.image(brain.group == 0 ? .group1 : .group2, colour: Settings.colour(.mode))
        case .mirror:
            stateImage.image = Images.image(.mirror, colour: Settings.colour(.mirror))
            groupImage.image = Images.image(.groupAll, colour: Settings.colour(.mode))
        }
        switch brain.throwMode {
        case .charge: throwImage.image = Images.image(.charge, colour: Settings.colour(.charge), size: 20)
        case .low: throwImage.image = Images.image(.low, colour: Settings.colour(.low), size: 20)
        }
    }
}

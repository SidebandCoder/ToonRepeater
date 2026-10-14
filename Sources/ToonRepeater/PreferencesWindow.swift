import AppKit

/// Preferences: General, Keybinds and Theme tabs.
final class PreferencesWindowController: NSWindowController {
    convenience init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        let items: [(NSViewController, String, String)] = [
            (GeneralPreferencesViewController(), "General", "gearshape"),
            (KeybindPreferencesViewController(), "Keybinds", "keyboard"),
            (ThemePreferencesViewController(), "Theme", "paintpalette"),
        ]
        for (vc, title, symbol) in items {
            vc.title = title
            let item = NSTabViewItem(viewController: vc)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = "Preferences"
        self.init(window: window)
    }
}

// MARK: - General

final class GeneralPreferencesViewController: NSViewController {
    private let keepAlive = NSButton(checkboxWithTitle: "Keep Alive (tap Home in every window each minute)", target: nil, action: nil)
    private let keepOnTop = NSButton(checkboxWithTitle: "Keep window on top", target: nil, action: nil)
    private let autoUpdate = NSButton(checkboxWithTitle: "Automatically check for updates on startup", target: nil, action: nil)
    private let shareStats = NSButton(checkboxWithTitle: "Share anonymous usage statistics", target: nil, action: nil)
    private let cloneMethod = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cloneDelay = NSSlider(value: 0.25, minValue: 0.05, maxValue: 1, target: nil, action: nil)
    private let cloneDelayLabel = NSTextField(labelWithString: "")
    private let arrangeSide = NSPopUpButton(frame: .zero, pullsDown: false)
    private let arrangeWidth = NSPopUpButton(frame: .zero, pullsDown: false)
    private static let arrangePercents = [100, 90, 80, 75, 70, 65, 60, 50, 40, 30]

    override func loadView() {
        let lift: CGFloat = 70 // room for the window-arrangement section at the bottom
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 225 + lift))
        for (i, box) in [keepAlive, keepOnTop, autoUpdate, shareStats].enumerated() {
            box.frame = NSRect(x: 40, y: 180 + lift - CGFloat(i) * 25, width: 340, height: 20)
            box.target = self
            box.action = #selector(toggled(_:))
            view.addSubview(box)
        }
        let cloneLabel = NSTextField(labelWithString: "Click Repeater works by:")
        cloneLabel.frame = NSRect(x: 40, y: 75 + lift, width: 340, height: 17)
        cloneMethod.addItems(withTitles: ClickRepeater.Method.allCases.map(\.title))
        cloneMethod.frame = NSRect(x: 38, y: 44 + lift, width: 300, height: 26)
        cloneMethod.target = self
        cloneMethod.action = #selector(cloneMethodChanged)
        let delayTitle = NSTextField(labelWithString: "Pause per step:")
        delayTitle.frame = NSRect(x: 40, y: 15 + lift, width: 100, height: 17)
        cloneDelay.frame = NSRect(x: 140, y: 12 + lift, width: 170, height: 24)
        cloneDelay.target = self
        cloneDelay.action = #selector(cloneDelayChanged)
        cloneDelayLabel.frame = NSRect(x: 316, y: 15 + lift, width: 70, height: 17)
        [cloneLabel, cloneMethod, delayTitle, cloneDelay, cloneDelayLabel].forEach(view.addSubview)

        let arrangeLabel = NSTextField(labelWithString: "Arrange Game Windows (⌘G) uses:")
        arrangeLabel.frame = NSRect(x: 40, y: 52, width: 340, height: 17)
        let theLabel = NSTextField(labelWithString: "the")
        theLabel.frame = NSRect(x: 40, y: 22, width: 26, height: 17)
        arrangeWidth.addItems(withTitles: Self.arrangePercents.map { "\($0)%" })
        arrangeWidth.frame = NSRect(x: 66, y: 17, width: 84, height: 26)
        arrangeWidth.target = self
        arrangeWidth.action = #selector(arrangeChanged)
        let ofLabel = NSTextField(labelWithString: "of the screen on the")
        ofLabel.frame = NSRect(x: 154, y: 22, width: 130, height: 17)
        arrangeSide.addItems(withTitles: ["right", "left"])
        arrangeSide.frame = NSRect(x: 284, y: 17, width: 84, height: 26)
        arrangeSide.target = self
        arrangeSide.action = #selector(arrangeChanged)
        [arrangeLabel, theLabel, arrangeWidth, ofLabel, arrangeSide].forEach(view.addSubview)
        self.view = view
        preferredContentSize = view.frame.size
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        keepAlive.state = Settings.keepAlive ? .on : .off
        keepOnTop.state = Settings.keepOnTop ? .on : .off
        autoUpdate.state = Settings.autoUpdate ? .on : .off
        shareStats.state = Analytics.consent == true ? .on : .off
        shareStats.isEnabled = Analytics.isAvailable
        shareStats.toolTip = Analytics.isAvailable ? "Installs, minutes used, number of game windows and features used. No personal information." : "Analytics isn't configured in this build."
        cloneMethod.selectItem(at: ClickRepeater.Method.allCases.firstIndex(of: Settings.repeaterMethod) ?? 0)
        cloneDelay.doubleValue = Settings.repeaterDelay
        cloneDelayChanged()
        let percent = Int((Settings.arrangeWidthFraction * 100).rounded())
        let nearest = Self.arrangePercents.min { abs($0 - percent) < abs($1 - percent) } ?? 100
        arrangeWidth.selectItem(at: Self.arrangePercents.firstIndex(of: nearest) ?? 0)
        arrangeSide.selectItem(at: Settings.arrangeSide == .right ? 0 : 1)
        arrangeSide.isEnabled = nearest < 100
    }

    @objc private func arrangeChanged() {
        let percent = Self.arrangePercents[max(0, arrangeWidth.indexOfSelectedItem)]
        Settings.arrangeWidthFraction = CGFloat(percent) / 100
        Settings.arrangeSide = arrangeSide.indexOfSelectedItem == 1 ? .left : .right
        arrangeSide.isEnabled = percent < 100
    }

    @objc private func cloneDelayChanged() {
        Settings.repeaterDelay = cloneDelay.doubleValue
        cloneDelayLabel.stringValue = String(format: "%.2f s", Settings.repeaterDelay)
    }

    @objc private func cloneMethodChanged() {
        Settings.repeaterMethod = ClickRepeater.Method.allCases[max(0, cloneMethod.indexOfSelectedItem)]
    }

    @objc private func toggled(_ sender: NSButton) {
        let on = sender.state == .on
        switch sender {
        case keepAlive: Settings.keepAlive = on
        case keepOnTop: Settings.keepOnTop = on
        case shareStats: Analytics.consent = on
        default: Settings.autoUpdate = on
        }
    }
}

// MARK: - Keybinds

final class KeybindPreferencesViewController: NSViewController {
    private var buttons: [String: NSButton] = [:]   // settings key -> button
    private let info = NSTextField(labelWithString: "")
    private var assigning: (key: String, title: String)?
    private var monitor: Any?

    private static let defaultInfo = "Click a button to change the action's keybind"

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 270))

        addBinding("mirrorthrow", title: "Mirror Throw", at: NSPoint(x: 98, y: 222), in: view)
        addBinding("throwtoggle", title: "Toggle Throw", at: NSPoint(x: 242, y: 222), in: view)

        for toon in 0..<2 {
            let originX: CGFloat = toon == 0 ? 20 : 220
            let box = NSBox(frame: NSRect(x: originX, y: 45, width: 160, height: 160))
            box.title = toon == 0 ? "Left Toon" : "Right Toon"
            view.addSubview(box)
            let layout: [(Action, CGFloat, CGFloat)] = [
                (.jump, 8, 72), (.throwpie, 92, 72),
                (.forward, 8, 36), (.backward, 92, 36),
                (.left, 8, 0), (.right, 92, 0),
            ]
            for (action, x, y) in layout {
                addBinding(Settings.keyName(toon: toon, action: action), title: action.title,
                           at: NSPoint(x: originX + x, y: 52 + y), in: view)
            }
        }

        info.frame = NSRect(x: 0, y: 30, width: 400, height: 17)
        info.alignment = .center
        info.stringValue = Self.defaultInfo
        view.addSubview(info)

        let restore = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        restore.frame = NSRect(x: 130, y: 4, width: 140, height: 28)
        view.addSubview(restore)
        self.view = view
        preferredContentSize = view.frame.size
    }

    private func addBinding(_ key: String, title: String, at origin: NSPoint, in view: NSView) {
        let label = NSTextField(labelWithString: title)
        label.alignment = .center
        label.font = .systemFont(ofSize: 11)
        label.frame = NSRect(x: origin.x - 10, y: origin.y + 26, width: 80, height: 14)
        view.addSubview(label)

        let button = NSButton(title: "", target: self, action: #selector(listen(_:)))
        button.bezelStyle = .rounded
        button.frame = NSRect(x: origin.x, y: origin.y, width: 60, height: 28)
        button.identifier = NSUserInterfaceItemIdentifier(key)
        button.toolTip = title
        view.addSubview(button)
        buttons[key] = button
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshTitles()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopListening()
    }

    private func refreshTitles() {
        for (key, button) in buttons { button.title = KeyCodes.string(of: Settings.key(key)) }
    }

    @objc private func listen(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        stopListening()
        assigning = (key, sender.toolTip ?? key)
        sender.title = "…"
        info.stringValue = "Assigning \(sender.toolTip ?? key) (cancel with escape)"
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.capture(event)
            return nil
        }
    }

    private func capture(_ event: NSEvent) {
        guard let assigning = assigning else { return }
        if event.type == .flagsChanged && !KeyCodes.isPressed(event.keyCode, flags: event.modifierFlags) { return }
        if event.type == .keyDown && event.keyCode == KeyCodes.escape {
            stopListening()
            return
        }
        Settings.setKey(assigning.key, event.keyCode)
        stopListening()
    }

    private func stopListening() {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        assigning = nil
        info.stringValue = Self.defaultInfo
        refreshTitles()
    }

    @objc private func restoreDefaults() {
        stopListening()
        Settings.restoreDefaultKeys()
        refreshTitles()
    }
}

// MARK: - Theme

final class ThemePreferencesViewController: NSViewController {
    private var wells: [Settings.Colour: NSColorWell] = [:]

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 250))
        for (i, colour) in Settings.Colour.allCases.enumerated() {
            let y = CGFloat(214 - i * 25)
            let well = NSColorWell(frame: NSRect(x: 129, y: y, width: 20, height: 20))
            well.target = self
            well.action = #selector(colourChanged(_:))
            well.identifier = NSUserInterfaceItemIdentifier(colour.rawValue)
            view.addSubview(well)
            wells[colour] = well
            let label = NSTextField(labelWithString: colour.title)
            label.frame = NSRect(x: 161, y: y + 2, width: 200, height: 17)
            view.addSubview(label)
        }
        let restore = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        restore.frame = NSRect(x: 130, y: 4, width: 140, height: 28)
        view.addSubview(restore)
        self.view = view
        preferredContentSize = view.frame.size
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshWells()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        NSColorPanel.shared.orderOut(nil)
    }

    private func refreshWells() {
        for (colour, well) in wells { well.color = Settings.colour(colour) }
    }

    @objc private func colourChanged(_ sender: NSColorWell) {
        guard let raw = sender.identifier?.rawValue, let colour = Settings.Colour(rawValue: raw) else { return }
        Settings.setColour(colour, sender.color)
    }

    @objc private func restoreDefaults() {
        Settings.restoreDefaultColours()
        refreshWells()
    }
}

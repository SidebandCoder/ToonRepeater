import AppKit

/// A small "Quickstart" window docked under the controller with a "Quickstart 4 Toons" button.
/// It closes when the button is used or when the user closes it, and moves with the controller.
final class QuickstartPrompt: NSObject, NSWindowDelegate {
    private let onStart: () -> Void
    private var panel: NSPanel?
    private weak var parent: NSWindow?

    init(onStart: @escaping () -> Void) {
        self.onStart = onStart
    }

    func show(below parent: NSWindow) {
        if panel == nil { panel = makePanel(width: parent.frame.width) }
        guard let panel = panel else { return }
        self.parent = parent
        let frame = parent.frame
        panel.setFrameTopLeftPoint(NSPoint(x: frame.minX, y: frame.minY - 2))
        if panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func close() {
        guard let panel = panel else { return }
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func makePanel(width: CGFloat) -> NSPanel {
        let contentHeight: CGFloat = 44
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: contentHeight),
                            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Quickstart"
        panel.becomesKeyOnlyIfNeeded = true // keep keyboard focus on the controller
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        // Match the controller's frame width exactly, title bar included.
        panel.setContentSize(NSSize(width: panel.contentRect(forFrameRect: NSRect(x: 0, y: 0, width: width, height: 100)).width,
                                    height: contentHeight))

        let button = NSButton(title: "Quickstart 4 Toons", target: self, action: #selector(startPressed))
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.keyEquivalent = ""
        button.refusesFirstResponder = true
        button.toolTip = "Log in four saved launcher accounts and arrange their windows"
        let contentWidth = panel.contentView?.bounds.width ?? width
        button.frame = NSRect(x: 6, y: 8, width: contentWidth - 12, height: 28)
        button.autoresizingMask = [.width]
        panel.contentView?.addSubview(button)
        return panel
    }

    @objc private func startPressed() {
        close()
        onStart()
    }

    // Closing with the title bar's close button just dismisses the prompt.
    func windowWillClose(_ notification: Notification) {
        if let panel = panel { parent?.removeChildWindow(panel) }
    }
}

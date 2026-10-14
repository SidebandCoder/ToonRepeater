import AppKit

/// Small floating progress window with a status line, a spinner or progress bar, and a Cancel button.
final class ProgressPanel {
    var onCancel: (() -> Void)?
    private let title: String
    private var window: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let bar = NSProgressIndicator()

    init(title: String) { self.title = title }

    func show() {
        if window == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 92),
                                styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
            panel.title = title
            panel.level = .floating
            panel.hidesOnDeactivate = false
            let content = panel.contentView!
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.frame = NSRect(x: 16, y: 54, width: 16, height: 16)
            label.frame = NSRect(x: 40, y: 52, width: 324, height: 20)
            label.lineBreakMode = .byTruncatingTail
            bar.style = .bar
            bar.isIndeterminate = false
            bar.minValue = 0
            bar.maxValue = 1
            bar.frame = NSRect(x: 16, y: 16, width: 260, height: 16)
            bar.isHidden = true
            let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
            cancel.frame = NSRect(x: 284, y: 10, width: 82, height: 28)
            [spinner, label, bar, cancel].forEach(content.addSubview)
            panel.center()
            window = panel
        }
        spinner.startAnimation(nil)
        window?.orderFrontRegardless()
    }

    func setStatus(_ text: String) { label.stringValue = text }

    /// Shows a progress bar (0…1) under the status line.
    func setProgress(_ fraction: Double) {
        bar.isHidden = false
        bar.doubleValue = fraction
    }

    func close() {
        spinner.stopAnimation(nil)
        bar.isHidden = true
        window?.orderOut(nil)
    }

    @objc private func cancelPressed() { onCancel?() }
}

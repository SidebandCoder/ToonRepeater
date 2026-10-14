#if DEBUG
import AppKit

/// Debug builds only: `ToonRepeater --snapshot <dir>` renders each window to PNG and quits.
/// Lets the UI be checked without Screen Recording permission.
enum DebugSnapshot {
    static var directory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1])
    }

    static func run(controller: NSViewController, preferences: PreferencesWindowController, into dir: URL,
                    extra: [NSWindow] = []) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        save(controller.view, dir.appendingPathComponent("controller.png"))
        for (i, window) in extra.enumerated() {
            if let view = window.contentView { save(view, dir.appendingPathComponent("extra-\(i)-\(window.title).png")) }
            if let c = controller.view.window?.frame { print("controller frame \(c), extra frame \(window.frame)") }
        }
        preferences.showWindow(nil)
        guard let tabs = preferences.contentViewController as? NSTabViewController else { return }
        for (index, item) in tabs.tabViewItems.enumerated() {
            tabs.selectedTabViewItemIndex = index
            if let view = item.viewController?.view { save(view, dir.appendingPathComponent("prefs-\(item.label).png")) }
        }
    }

    private static func save(_ view: NSView, _ url: URL) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        // Paint the window background behind the view, as on screen.
        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        (view.window?.backgroundColor ?? .windowBackgroundColor).setFill()
        view.bounds.fill()
        rep.draw(in: view.bounds)
        image.unlockFocus()
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }
}
#endif

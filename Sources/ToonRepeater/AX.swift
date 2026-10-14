import AppKit
import ApplicationServices

/// Thin wrapper over the Accessibility API for driving other apps' controls.
struct AXElement {
    let ref: AXUIElement

    static func application(pid: pid_t) -> AXElement { AXElement(ref: AXUIElementCreateApplication(pid)) }

    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ref, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    var role: String { attribute(kAXRoleAttribute) ?? "" }
    var subrole: String { attribute(kAXSubroleAttribute) ?? "" }
    var title: String { attribute(kAXTitleAttribute) ?? "" }
    var identifier: String { attribute(kAXIdentifierAttribute) ?? "" }
    var axDescription: String { attribute(kAXDescriptionAttribute) ?? "" }
    var placeholder: String { attribute(kAXPlaceholderValueAttribute) ?? "" }
    var stringValue: String { attribute(kAXValueAttribute) ?? "" }

    var children: [AXElement] {
        (attribute(kAXChildrenAttribute) as [AXUIElement]?)?.map(AXElement.init) ?? []
    }

    var windows: [AXElement] {
        (attribute(kAXWindowsAttribute) as [AXUIElement]?)?.map(AXElement.init) ?? []
    }

    var actions: [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(ref, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    var frame: CGRect? {
        guard let posValue: AXValue = attribute(kAXPositionAttribute),
              let sizeValue: AXValue = attribute(kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posValue, .cgPoint, &point)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    @discardableResult
    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(ref, action as CFString) == .success
    }

    @discardableResult
    func set(_ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(ref, name as CFString, value) == .success
    }

    /// Depth-first search of the subtree.
    func first(maxDepth: Int = 12, where match: (AXElement) -> Bool) -> AXElement? {
        if match(self) { return self }
        guard maxDepth > 0 else { return nil }
        for child in children {
            if let found = child.first(maxDepth: maxDepth - 1, where: match) { return found }
        }
        return nil
    }

    func all(maxDepth: Int = 12, where match: (AXElement) -> Bool) -> [AXElement] {
        var found = match(self) ? [self] : []
        guard maxDepth > 0 else { return found }
        for child in children { found += child.all(maxDepth: maxDepth - 1, where: match) }
        return found
    }

    /// Outline of the subtree for diagnostics. Never includes field contents.
    func outline(depth: Int = 0, maxDepth: Int = 12, redactTitles: Bool = false) -> String {
        let title = redactTitles && !self.title.isEmpty ? "<\(self.title.count) chars>" : self.title
        var parts = [role]
        if !subrole.isEmpty { parts.append("sub=\(subrole)") }
        if !identifier.isEmpty { parts.append("id=\(identifier)") }
        if !title.isEmpty { parts.append("title=\"\(title)\"") }
        if !axDescription.isEmpty { parts.append("desc=\"\(axDescription)\"") }
        if !placeholder.isEmpty { parts.append("placeholder=\"\(placeholder)\"") }
        if let f = frame { parts.append("frame=(\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)))") }
        let acts = actions.filter { $0 != "AXShowMenu" && $0 != "AXScrollToVisible" }
        if !acts.isEmpty { parts.append("actions=\(acts.joined(separator: ","))") }
        var text = String(repeating: "  ", count: depth) + parts.joined(separator: " ") + "\n"
        guard depth < maxDepth else { return text }
        for child in children { text += child.outline(depth: depth + 1, maxDepth: maxDepth, redactTitles: redactTitles) }
        return text
    }
}

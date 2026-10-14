import AppKit

/// Indicator images, drawn from SF Symbols and tinted with the theme colours.
enum Images {
    enum Kind {
        case target, group1, group2, groupAll, multi, mirror, disabled, charge, low

        var symbol: String {
            switch self {
            case .target: return "scope"
            case .group1: return "1.circle.fill"
            case .group2: return "2.circle.fill"
            case .groupAll: return "square.grid.2x2.fill"
            case .multi: return "person.2.fill"
            case .mirror: return "rectangle.on.rectangle"
            case .disabled: return "pause.circle.fill"
            case .charge: return "bolt.fill"
            case .low: return "arrow.down.to.line"
            }
        }
    }

    static func image(_ kind: Kind, colour: NSColor, size: CGFloat = 30) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size * 0.8, weight: .semibold)) else { return nil }
        return tinted(symbol, colour)
    }

    /// The Click Repeater symbol: a cursor inside a ring of repeat arrows.
    static func clickRepeater(colour: NSColor, size: CGFloat = 20) -> NSImage? {
        let ringConfig = NSImage.SymbolConfiguration(pointSize: size * 0.9, weight: .semibold)
        let cursorConfig = NSImage.SymbolConfiguration(pointSize: size * 0.45, weight: .bold)
        guard let ring = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
                .withSymbolConfiguration(ringConfig),
              let cursor = NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: nil)?
                .withSymbolConfiguration(cursorConfig) else { return nil }
        let ringImage = tinted(ring, colour)
        let cursorImage = tinted(cursor, colour)
        let canvas = NSSize(width: size, height: size)
        let image = NSImage(size: canvas, flipped: false) { rect in
            let ringSize = ringImage.size.scaled(toFit: rect.size)
            ringImage.draw(in: NSRect(x: rect.midX - ringSize.width / 2, y: rect.midY - ringSize.height / 2,
                                      width: ringSize.width, height: ringSize.height))
            let cursorSize = cursorImage.size
            cursorImage.draw(in: NSRect(x: rect.midX - cursorSize.width / 2 + 1, y: rect.midY - cursorSize.height / 2,
                                        width: cursorSize.width, height: cursorSize.height))
            return true
        }
        image.accessibilityDescription = "Click Repeater"
        return image
    }

    private static func tinted(_ image: NSImage, _ colour: NSColor) -> NSImage {
        let result = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            colour.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        result.isTemplate = false
        return result
    }
}

private extension NSSize {
    func scaled(toFit bounds: NSSize) -> NSSize {
        let scale = min(bounds.width / max(width, 1), bounds.height / max(height, 1))
        return NSSize(width: width * scale, height: height * scale)
    }
}

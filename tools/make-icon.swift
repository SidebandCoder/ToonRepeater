import AppKit
// Usage: xcrun swift tools/make-icon.swift <artwork> Resources/AppIcon.png
// Masks the artwork to its rounded-square shape (removing the white corners) and places it on Apple's macOS
// icon grid: an 824×824 body centred on a 1024×1024 transparent canvas, with a soft drop shadow.
let source = NSImage(contentsOfFile: CommandLine.arguments[1])!
let canvas = 1024, body: CGFloat = 824
let sourceRadius: CGFloat = 232, inset: CGFloat = 2 // measured from the artwork

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
let origin = (CGFloat(canvas) - body) / 2
let scale = body / 1024
let rect = NSRect(x: origin, y: origin, width: body, height: body)
let clipRect = rect.insetBy(dx: inset * scale, dy: inset * scale)
let path = NSBezierPath(roundedRect: clipRect, xRadius: (sourceRadius - inset) * scale, yRadius: (sourceRadius - inset) * scale)

// Shadow, drawn from the shape itself.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 24
shadow.set()
NSColor.white.setFill()
path.fill()
NSGraphicsContext.restoreGraphicsState()

// Artwork clipped to the rounded square.
path.addClip()
source.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("wrote", CommandLine.arguments[2])

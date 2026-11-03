import AppKit

/// Template image drawn in code so the status item adapts to light and dark
/// menu bars without shipping extra assets.
enum MenuBarIcon {

    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let scale = size / 18.0

            // Back card, dimmed to read as "another profile behind this one".
            let back = NSBezierPath(
                roundedRect: NSRect(x: 2.0 * scale, y: 7.6 * scale,
                                    width: 9.4 * scale, height: 7.8 * scale),
                xRadius: 2.1 * scale,
                yRadius: 2.1 * scale
            )
            NSColor.black.withAlphaComponent(0.42).setFill()
            back.fill()

            // Front card.
            let front = NSBezierPath(
                roundedRect: NSRect(x: 6.4 * scale, y: 2.6 * scale,
                                    width: 9.6 * scale, height: 8.2 * scale),
                xRadius: 2.1 * scale,
                yRadius: 2.1 * scale
            )
            NSColor.black.setFill()
            front.fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}

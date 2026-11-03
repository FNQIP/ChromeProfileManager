import AppKit

/// Template image drawn in code so the status item adapts to light and dark
/// menu bars without shipping extra assets.
///
/// 尺寸说明：菜单栏高度约 24pt，早期版本用 18pt 画布、内容只占 12.8pt，
/// 在实际菜单栏里偏小。改成 20pt 画布 + 小边距后，图形实际高度约 17.6pt，
/// 与系统图标相当，但轮廓更饱满。
enum MenuBarIcon {

    static let defaultSize: CGFloat = 20

    static func make(size: CGFloat = MenuBarIcon.defaultSize) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let margin = size * 0.06
            let inner = size - margin * 2
            let cardWidth = inner * 0.80
            let cardHeight = inner * 0.58
            let radius = cardHeight * 0.26

            // 后方卡片：半透明，读作「背后还有一个配置」。
            NSColor.black.withAlphaComponent(0.42).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: margin,
                                    y: size - margin - cardHeight,
                                    width: cardWidth,
                                    height: cardHeight),
                xRadius: radius,
                yRadius: radius
            ).fill()

            // 前方卡片：实心。
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: size - margin - cardWidth,
                                    y: margin,
                                    width: cardWidth,
                                    height: cardHeight),
                xRadius: radius,
                yRadius: radius
            ).fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}

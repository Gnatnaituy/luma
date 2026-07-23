import AppKit

enum LumaStatusIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()

            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: 2.2, y: 15))
            mark.line(to: NSPoint(x: 5.4, y: 15))
            mark.line(to: NSPoint(x: 9, y: 10.6))
            mark.line(to: NSPoint(x: 12.6, y: 15))
            mark.line(to: NSPoint(x: 15.8, y: 15))
            mark.line(to: NSPoint(x: 10.5, y: 8.6))
            mark.line(to: NSPoint(x: 10.5, y: 3))
            mark.line(to: NSPoint(x: 7.5, y: 3))
            mark.line(to: NSPoint(x: 7.5, y: 8.6))
            mark.close()
            mark.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

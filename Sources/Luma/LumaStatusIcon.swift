import AppKit

enum LumaStatusIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let portal = NSBezierPath()
            portal.move(to: NSPoint(x: 3.1, y: 14.3))
            portal.line(to: NSPoint(x: 8.9, y: 12.9))
            portal.curve(
                to: NSPoint(x: 12.6, y: 9.9),
                controlPoint1: NSPoint(x: 11.1, y: 12.4),
                controlPoint2: NSPoint(x: 12.6, y: 11.1)
            )
            portal.curve(
                to: NSPoint(x: 8.9, y: 5.1),
                controlPoint1: NSPoint(x: 12.6, y: 7.5),
                controlPoint2: NSPoint(x: 11.1, y: 5.6)
            )
            portal.line(to: NSPoint(x: 3.1, y: 3.7))
            portal.lineWidth = 1.9
            portal.lineCapStyle = .round
            portal.lineJoinStyle = .round
            portal.stroke()

            let beam = NSBezierPath()
            beam.move(to: NSPoint(x: 3.3, y: 9))
            beam.line(to: NSPoint(x: 10.1, y: 9))
            beam.lineWidth = 1.25
            beam.lineCapStyle = .round
            beam.stroke()

            let spark = NSBezierPath()
            spark.move(to: NSPoint(x: 12.5, y: 12.1))
            spark.curve(
                to: NSPoint(x: 14.8, y: 9),
                controlPoint1: NSPoint(x: 12.8, y: 10.2),
                controlPoint2: NSPoint(x: 13.2, y: 9.4)
            )
            spark.curve(
                to: NSPoint(x: 12.5, y: 5.9),
                controlPoint1: NSPoint(x: 13.2, y: 8.6),
                controlPoint2: NSPoint(x: 12.8, y: 7.8)
            )
            spark.curve(
                to: NSPoint(x: 10.2, y: 9),
                controlPoint1: NSPoint(x: 12.2, y: 7.8),
                controlPoint2: NSPoint(x: 11.8, y: 8.6)
            )
            spark.curve(
                to: NSPoint(x: 12.5, y: 12.1),
                controlPoint1: NSPoint(x: 11.8, y: 9.4),
                controlPoint2: NSPoint(x: 12.2, y: 10.2)
            )
            spark.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

// สร้างภาพพื้นหลังหน้าต่าง DMG (ลูกศรลากแอปไปที่ Applications)
import AppKit
func render(scale: CGFloat, to path: String) {
    let W: CGFloat = 640, H: CGFloat = 400
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // พื้นไล่สีน้ำเงิน → เขียว แบบโลโก้
    NSGradient(colors: [NSColor(srgbRed: 0.03, green: 0.10, blue: 0.30, alpha: 1),
                        NSColor(srgbRed: 0.02, green: 0.20, blue: 0.22, alpha: 1),
                        NSColor(srgbRed: 0.03, green: 0.26, blue: 0.12, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 0)
    // แสงโค้งเบาๆ
    for (c, y) in [(NSColor(srgbRed: 0.2, green: 0.5, blue: 1, alpha: 0.18), 120.0), (NSColor(srgbRed: 0.2, green: 1, blue: 0.5, alpha: 0.14), 90.0)] {
        let p = NSBezierPath(); p.move(to: NSPoint(x: -20, y: y)); p.curve(to: NSPoint(x: W + 20, y: y + 40), controlPoint1: NSPoint(x: 200, y: y + 90), controlPoint2: NSPoint(x: 440, y: y - 60))
        p.lineWidth = 2.5; c.setStroke(); p.stroke()
    }
    // หัวเรื่อง
    let title = NSAttributedString(string: "PadFlow", attributes: [.font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: NSColor.white])
    title.draw(at: NSPoint(x: (W - title.size().width) / 2, y: H - 70))
    let sub = NSAttributedString(string: "Drag PadFlow to Applications to install", attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.75)])
    sub.draw(at: NSPoint(x: (W - sub.size().width) / 2, y: H - 98))
    // ลูกศร (ไอคอนอยู่ที่ x=170 และ x=470, ศูนย์กลาง y=200 จากด้านบน)
    let y: CGFloat = H - 200
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 255, y: y)); arrow.line(to: NSPoint(x: 370, y: y))
    arrow.lineWidth = 6; arrow.lineCapStyle = .round
    NSColor(white: 1, alpha: 0.85).setStroke(); arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 390, y: y)); head.line(to: NSPoint(x: 362, y: y + 18)); head.line(to: NSPoint(x: 362, y: y - 18)); head.close()
    NSColor(white: 1, alpha: 0.85).setFill(); head.fill()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
let dir = CommandLine.arguments[1]
render(scale: 1, to: "\(dir)/bg.png")
render(scale: 2, to: "\(dir)/bg@2x.png")

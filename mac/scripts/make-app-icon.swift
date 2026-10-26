// Draws the Claude Switch app icon into Assets.xcassets/AppIcon.appiconset.
// Run: swift scripts/make-app-icon.swift  (from mac/)
import AppKit

let ink = NSColor(srgbRed: 0x17/255, green: 0x12/255, blue: 0x0E/255, alpha: 1)
let tangerine = NSColor(srgbRed: 1, green: 0x6B/255, blue: 0x2C/255, alpha: 1)
let paper = NSColor(srgbRed: 1, green: 0xF5/255, blue: 0xEC/255, alpha: 1)
let violet = NSColor(srgbRed: 0x7C/255, green: 0x5C/255, blue: 1, alpha: 1)

func card(_ rect: NSRect, angle: CGFloat, fill: NSColor, unit: CGFloat, letter: String, letterColor: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: rect.midX, yBy: rect.midY)
    t.rotate(byDegrees: angle)
    t.concat()
    let r = NSRect(x: -rect.width/2, y: -rect.height/2, width: rect.width, height: rect.height)
    ink.setFill()
    NSBezierPath(roundedRect: r.offsetBy(dx: 0, dy: -unit*3), xRadius: unit*9, yRadius: unit*9).fill()
    let p = NSBezierPath(roundedRect: r, xRadius: unit*9, yRadius: unit*9)
    fill.setFill(); p.fill()
    p.lineWidth = unit*2.4; ink.setStroke(); p.stroke()
    let font = NSFont(name: "BricolageGrotesque-ExtraBold", size: r.height*0.62) ?? .systemFont(ofSize: r.height*0.6, weight: .black)
    let s = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: letterColor])
    let sz = s.size()
    s.draw(at: NSPoint(x: -sz.width/2, y: -sz.height/2 + r.height*0.02))
    NSGraphicsContext.restoreGraphicsState()
}

func draw(size: CGFloat) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = size / 100
    // macOS icon grid: 824/1024 body
    let body = NSRect(x: 10*u, y: 10*u, width: 80*u, height: 80*u)
    ink.setFill()
    NSBezierPath(roundedRect: body.offsetBy(dx: 0, dy: -2*u), xRadius: 18*u, yRadius: 18*u).fill()
    let bg = NSBezierPath(roundedRect: body, xRadius: 18*u, yRadius: 18*u)
    tangerine.setFill(); bg.fill()
    bg.lineWidth = 2.4*u; ink.setStroke(); bg.stroke()

    card(NSRect(x: 22*u, y: 34*u, width: 36*u, height: 36*u), angle: 10, fill: violet, unit: u, letter: "P", letterColor: paper)
    card(NSRect(x: 42*u, y: 22*u, width: 38*u, height: 38*u), angle: -7, fill: paper, unit: u, letter: "W", letterColor: ink)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Register the bundled display font so the letters match the app.
for f in ["BricolageGrotesque_800ExtraBold.ttf"] {
    CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "ClaudeSwitch/Resources/Fonts/" + f) as CFURL, .process, nil)
}

let dir = URL(fileURLWithPath: "ClaudeSwitch/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try draw(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let json = try JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys])
try json.write(to: dir.appendingPathComponent("Contents.json"))
try #"{"info":{"author":"xcode","version":1}}"#.write(to: dir.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try draw(size: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "../landing/app-icon.png"))
print("ok")

// Draws the HidPad launcher icons and store graphics.
// Run from the repository root:  swift tool/icon.swift
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let top = CGColor(red: 0x63 / 255.0, green: 0x66 / 255.0, blue: 0xF1 / 255.0, alpha: 1) // the app's seed colour
let bottom = CGColor(red: 0x43 / 255.0, green: 0x38 / 255.0, blue: 0xCA / 255.0, alpha: 1)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

/// `opaque` gives a picture with no alpha channel, which Google Play wants for the banner.
func canvas(_ w: Int, _ h: Int, opaque: Bool = false) -> CGContext {
    let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: alpha.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h)) // y grows downwards from here on
    ctx.scaleBy(x: 1, y: -1)
    return ctx
}

func save(_ ctx: CGContext, _ path: String) {
    let url = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(out, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(out)
}

func background(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat) {
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
    ctx.restoreGState()
}

/// A keyboard with a pointer over its corner, `w` wide, centred on `center`.
func glyph(_ ctx: CGContext, center: CGPoint, w: CGFloat) {
    let h = w * 0.62
    let body = CGRect(x: center.x - w / 2, y: center.y - h / 2 - w * 0.04, width: w, height: h)
    ctx.setFillColor(white)
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: w * 0.1, cornerHeight: w * 0.1, transform: nil))
    ctx.fillPath()

    let key = w * 0.12, gap = w * 0.045, left = body.minX + w * 0.11, first = body.minY + w * 0.085
    ctx.setFillColor(bottom)
    func cap(_ col: CGFloat, _ row: CGFloat, span: CGFloat = 1) {
        let rect = CGRect(x: left + col * (key + gap), y: first + row * (key + gap), width: key * span + gap * (span - 1), height: key)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: key * 0.28, cornerHeight: key * 0.28, transform: nil))
        ctx.fillPath()
    }
    for row in 0..<2 { for col in 0..<5 { cap(CGFloat(col), CGFloat(row)) } }
    cap(0, 2); cap(1, 2, span: 3); cap(4, 2)

    // Pointer: white with a dark edge, so it reads on the keyboard and on the background.
    let s = w * 0.5, origin = CGPoint(x: center.x + w * 0.14, y: center.y + w * 0.02)
    let shape: [(CGFloat, CGFloat)] = [(0, 0), (0, 0.74), (0.19, 0.57), (0.32, 0.87), (0.45, 0.81), (0.32, 0.52), (0.56, 0.52)]
    let path = CGMutablePath()
    path.addLines(between: shape.map { CGPoint(x: origin.x + $0.0 * s, y: origin.y + $0.1 * s) })
    path.closeSubpath()
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(bottom)
    ctx.setLineWidth(w * 0.07)
    ctx.addPath(path); ctx.strokePath()
    ctx.setFillColor(white)
    ctx.addPath(path); ctx.fillPath()
}

let res = "android/app/src/main/res"
for (density, scale) in [("mdpi", 1.0), ("hdpi", 1.5), ("xhdpi", 2.0), ("xxhdpi", 3.0), ("xxxhdpi", 4.0)] {
    // Fallback for tools that do not read adaptive icons: a rounded square.
    let size = Int(48 * scale), side = CGFloat(size)
    let legacy = canvas(size, size)
    background(legacy, CGRect(x: 0, y: 0, width: side, height: side), radius: side * 0.22)
    glyph(legacy, center: CGPoint(x: side / 2, y: side / 2), w: side * 0.62)
    save(legacy, "\(res)/mipmap-\(density)/ic_launcher.png")

    // Foreground of the adaptive icon: the launcher crops to the middle 66 of 108 dp.
    let full = Int(108 * scale), edge = CGFloat(full)
    let foreground = canvas(full, full)
    glyph(foreground, center: CGPoint(x: edge / 2, y: edge / 2), w: edge * 0.44)
    save(foreground, "\(res)/mipmap-\(density)/ic_launcher_foreground.png")
}

let store = "fastlane/metadata/android/en-US/images"
let icon = canvas(512, 512)
background(icon, CGRect(x: 0, y: 0, width: 512, height: 512), radius: 0) // Google Play rounds the corners
glyph(icon, center: CGPoint(x: 256, y: 256), w: 512 * 0.6)
save(icon, "\(store)/icon.png")

let banner = canvas(1024, 500, opaque: true)
background(banner, CGRect(x: 0, y: 0, width: 1024, height: 500), radius: 0)
glyph(banner, center: CGPoint(x: 230, y: 250), w: 270)
banner.scaleBy(x: 1, y: -1) // text is drawn with y growing upwards
banner.translateBy(x: 0, y: -500)
NSGraphicsContext.current = NSGraphicsContext(cgContext: banner, flipped: false)
// Roboto, the app's own font, from the Flutter SDK (FLUTTER_ROOT, or the folder of `flutter`).
let flutter = ProcessInfo.processInfo.environment["FLUTTER_ROOT"] ?? {
    let which = Process(), out = Pipe()
    which.executableURL = URL(fileURLWithPath: "/usr/bin/env"); which.arguments = ["which", "flutter"]; which.standardOutput = out
    try! which.run(); which.waitUntilExit()
    let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
    return URL(fileURLWithPath: path).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().path
}()
func text(_ string: String, font: String, size: CGFloat, y: CGFloat) {
    let file = URL(fileURLWithPath: "\(flutter)/bin/cache/artifacts/material_fonts/\(font).ttf")
    let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as! [CTFontDescriptor])[0]
    NSAttributedString(string: string, attributes: [.font: CTFontCreateWithFontDescriptor(descriptor, size, nil), .foregroundColor: NSColor.white])
        .draw(at: CGPoint(x: 440, y: y))
}
text("HidPad", font: "Roboto-Bold", size: 110, y: 235)
text("Your phone as a Bluetooth", font: "Roboto-Regular", size: 38, y: 170)
text("keyboard and mouse", font: "Roboto-Regular", size: 38, y: 122)
save(banner, "\(store)/featureGraphic.png")

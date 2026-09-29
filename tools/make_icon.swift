import AppKit
// Regenerate: swift tools/make_icon.swift Bookshelf/Assets.xcassets/AppIcon.appiconset/AppIcon.png

// 1024×1024 app icon: warm gradient, books on a shelf. iOS rounds the corners itself,
// and icons must be opaque, so the canvas has no alpha channel.
let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// Background: orange (top left) to coral (bottom right).
let gradient = CGGradient(colorsSpace: space,
                          colors: [color(252, 146, 74), color(226, 72, 92)] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])

func roundedRect(_ rect: CGRect, radius: CGFloat, fill: CGColor) {
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(fill)
    ctx.fillPath()
}

/// A book spine with two bands, like the lines on a real spine.
func book(_ rect: CGRect, fill: CGColor, band: CGColor) {
    roundedRect(rect, radius: 22, fill: fill)
    for fraction in [0.14, 0.80] {
        let y = rect.minY + rect.height * fraction
        ctx.setFillColor(band)
        ctx.fill(CGRect(x: rect.minX + 22, y: y, width: rect.width - 44, height: 16))
    }
}

let shelfY: CGFloat = 250
let cream = color(255, 244, 228)
let white = color(255, 255, 255)
let band = color(226, 72, 92, 0.35)

// Soft shadow under everything.
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(120, 20, 40, 0.35))

book(CGRect(x: 232, y: shelfY + 30, width: 130, height: 420), fill: white, band: band)
book(CGRect(x: 380, y: shelfY + 30, width: 158, height: 500), fill: cream, band: band)
book(CGRect(x: 556, y: shelfY + 30, width: 118, height: 380), fill: white, band: band)

// Last book leans against the others.
ctx.saveGState()
ctx.translateBy(x: 806, y: shelfY + 30 + 120 * sin(.pi / 9))   // lift so the tilted corner rests on the shelf
ctx.rotate(by: .pi / 9)
book(CGRect(x: -120, y: 0, width: 120, height: 440), fill: cream, band: band)
ctx.restoreGState()

// The shelf.
roundedRect(CGRect(x: 180, y: shelfY, width: 664, height: 34), radius: 17, fill: white)

let image = ctx.makeImage()!
let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")

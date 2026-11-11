// Draws the CLITool app icon (a terminal prompt) as a 1024x1024 PNG.
// Usage: swift scripts/make-icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xFF) / 255,
        CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255,
        alpha,
    ])!
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Note: CoreGraphics origin is bottom-left.

// MARK: Background tile (standard macOS icon shape: 824pt tile on a 1024 canvas)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = rounded(tile, 186)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.4))
ctx.addPath(tilePath)
ctx.setFillColor(color(0x1B1E27))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let background = CGGradient(colorsSpace: space,
                            colors: [color(0x3A3F4F), color(0x1F222C), color(0x111318)] as CFArray,
                            locations: [0, 0.55, 1])!
ctx.drawLinearGradient(background,
                       start: CGPoint(x: tile.minX, y: tile.maxY),
                       end: CGPoint(x: tile.maxX, y: tile.minY),
                       options: [])
// Soft highlight at the top of the tile.
let highlight = CGGradient(colorsSpace: space,
                           colors: [color(0xFFFFFF, 0.12), color(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
ctx.drawLinearGradient(highlight,
                       start: CGPoint(x: 512, y: tile.maxY),
                       end: CGPoint(x: 512, y: tile.midY),
                       options: [])
ctx.restoreGState()

// Thin inner rim so the dark tile reads against dark backgrounds.
ctx.addPath(rounded(tile.insetBy(dx: 3, dy: 3), 183))
ctx.setStrokeColor(color(0xFFFFFF, 0.10))
ctx.setLineWidth(6)
ctx.strokePath()

// MARK: Traffic lights
for (index, hex) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
    let centerX = 214 + CGFloat(index) * 70
    ctx.setFillColor(color(hex))
    ctx.fillEllipse(in: CGRect(x: centerX - 23, y: 800 - 23, width: 46, height: 46))
}

// MARK: Prompt chevron
let chevron = CGMutablePath()
chevron.move(to: CGPoint(x: 290, y: 630))
chevron.addLine(to: CGPoint(x: 488, y: 462))
chevron.addLine(to: CGPoint(x: 290, y: 294))

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 46, color: color(0xFF4FB8, 0.55))
ctx.addPath(chevron)
ctx.setStrokeColor(color(0xFF6AC1))
ctx.setLineWidth(88)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.strokePath()
ctx.restoreGState()

// MARK: Cursor
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 30, color: color(0xFFFFFF, 0.3))
ctx.addPath(rounded(CGRect(x: 560, y: 250, width: 200, height: 88), 22))
ctx.setFillColor(color(0xEEF1F6))
ctx.fillPath()
ctx.restoreGState()

// MARK: Write PNG
guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: make-icon.swift <output.png>\n".data(using: .utf8)!)
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write("failed to write \(output.path)\n".data(using: .utf8)!)
    exit(1)
}

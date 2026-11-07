// Renders the ChocoEdit app icon as PNGs at every size macOS uses: a caramel
// rounded square holding a four-piece chocolate bar, each piece wearing a
// round metal footswitch like the Chocolate Plus, with the pedal's little
// amber display between B and C. Fine details (bevels, display digits, the
// shine on the caps) only appear where they stay crisp.
//   swiftc Tools/make-icon.swift -o make-icon && ./make-icon <out-dir>
// Tools/make-icns.py then packs the PNGs into Resources/AppIcon.icns.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-png")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// macOS-style rounded square with continuous (superellipse) corners.
func squircle(in r: CGRect) -> CGPath {
    let c = r.width * 0.30
    let n: CGFloat = 4.2
    let path = CGMutablePath()
    let corners: [(CGPoint, CGFloat)] = [
        (CGPoint(x: r.maxX - c, y: r.maxY - c), 0),
        (CGPoint(x: r.minX + c, y: r.maxY - c), .pi / 2),
        (CGPoint(x: r.minX + c, y: r.minY + c), .pi),
        (CGPoint(x: r.maxX - c, y: r.minY + c), 3 * .pi / 2),
    ]
    for (k, (centre, a0)) in corners.enumerated() {
        for i in 0...90 {
            let t = a0 + CGFloat(i) / 90 * (.pi / 2)
            let cs = cos(t), sn = sin(t)
            let p = CGPoint(x: centre.x + c * (cs < 0 ? -1 : 1) * pow(abs(cs), 2 / n),
                            y: centre.y + c * (sn < 0 ? -1 : 1) * pow(abs(sn), 2 / n))
            if k == 0 && i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
    }
    path.closeSubpath()
    return path
}

func linear(_ ctx: CGContext, _ path: CGPath, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func render(_ px: Int) -> CGImage {
    let s = CGFloat(px) / 1024          // everything is laid out on a 1024 grid
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)
    let small = px <= 32
    let medium = px <= 64

    // Tile: Apple's icon grid leaves ~100 px of margin at 1024.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = squircle(in: tile)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.30))
    ctx.addPath(tilePath)
    ctx.setFillColor(rgb(0xE9CFA6))
    ctx.fillPath()
    ctx.restoreGState()
    linear(ctx, tilePath, [rgb(0xF7E6C8), rgb(0xD9AE78)], from: CGPoint(x: 0, y: tile.maxY), to: CGPoint(x: 0, y: tile.minY))

    // Chocolate bar: four pieces in a row, like the pedal's four switches.
    let bar = CGRect(x: 168, y: small ? 330 : 318, width: 688, height: small ? 364 : 388)
    let barPath = CGPath(roundedRect: bar, cornerWidth: 46, cornerHeight: 46, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: medium ? 10 : 26, color: rgb(0x2A1206, 0.45))
    ctx.addPath(barPath)
    ctx.setFillColor(rgb(0x4A2412))
    ctx.fillPath()
    ctx.restoreGState()
    linear(ctx, barPath, [rgb(0x6B3A1F), rgb(0x3E1D0E)], from: CGPoint(x: 0, y: bar.maxY), to: CGPoint(x: 0, y: bar.minY))

    let gap: CGFloat = small ? 22 : 16
    let pieceW = (bar.width - 2 * 22 - 3 * gap) / 4
    let pieceH = bar.height - 2 * 22
    for i in 0..<4 {
        let r = CGRect(x: bar.minX + 22 + CGFloat(i) * (pieceW + gap), y: bar.minY + 22, width: pieceW, height: pieceH)
        let piece = CGPath(roundedRect: r, cornerWidth: 22, cornerHeight: 22, transform: nil)
        // Raised piece: light top-left edge, dark bottom-right, flat top.
        if !small {
            linear(ctx, piece, [rgb(0x8A5131), rgb(0x2E1408)], from: CGPoint(x: r.minX, y: r.maxY), to: CGPoint(x: r.maxX, y: r.minY))
            let top = CGPath(roundedRect: r.insetBy(dx: 14, dy: 14), cornerWidth: 14, cornerHeight: 14, transform: nil)
            linear(ctx, top, [rgb(0x6E3B1E), rgb(0x55291A)], from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.minY))
        } else {
            ctx.addPath(piece)
            ctx.setFillColor(rgb(0x5E3019))
            ctx.fillPath()
        }

        // Footswitch cap: brushed-metal disc with a dark rim.
        let c = CGPoint(x: r.midX, y: r.minY + pieceH * 0.40)
        let rad: CGFloat = small ? 56 : 52
        ctx.saveGState()
        if !medium { ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 10, color: rgb(0x000000, 0.5)) }
        ctx.addEllipse(in: CGRect(x: c.x - rad - 8, y: c.y - rad - 8, width: 2 * rad + 16, height: 2 * rad + 16))
        ctx.setFillColor(rgb(0x1C1C1E))
        ctx.fillPath()
        ctx.restoreGState()
        let cap = CGPath(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: 2 * rad, height: 2 * rad), transform: nil)
        linear(ctx, cap, [rgb(0xF2F2F4), rgb(0x9A9AA0)], from: CGPoint(x: c.x - rad, y: c.y + rad), to: CGPoint(x: c.x + rad, y: c.y - rad))
        if !medium {
            let shine = CGPath(ellipseIn: CGRect(x: c.x - rad * 0.55, y: c.y + rad * 0.05, width: rad * 0.75, height: rad * 0.5), transform: nil)
            ctx.addPath(shine)
            ctx.setFillColor(rgb(0xFFFFFF, 0.55))
            ctx.fillPath()
        }
    }

    // The pedal's 3-digit display, between B and C, above the caps.
    if !small {
        let dw: CGFloat = 132, dh: CGFloat = 70
        let d = CGRect(x: bar.midX - dw / 2, y: bar.minY + 22 + pieceH * 0.72, width: dw, height: dh)
        let disp = CGPath(roundedRect: d, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.addPath(disp)
        ctx.setFillColor(rgb(0x120804))
        ctx.fillPath()
        ctx.addPath(disp)
        ctx.setStrokeColor(rgb(0xB07A52, 0.8))
        ctx.setLineWidth(4)
        ctx.strokePath()
        if !medium {
            let font = CTFontCreateWithName("Menlo-Bold" as CFString, 52, nil)
            let attr = NSAttributedString(string: "01", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): rgb(0xFFB020),
            ])
            let line = CTLineCreateWithAttributedString(attr)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            ctx.textPosition = CGPoint(x: d.midX - bounds.width / 2 - bounds.minX, y: d.midY - bounds.height / 2 - bounds.minY)
            CTLineDraw(line, ctx)
        } else {
            ctx.setFillColor(rgb(0xFFB020))
            ctx.fill(d.insetBy(dx: 34, dy: 24))
        }
    }

    // A bite out of the top-right corner of the bar.
    if !small {
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        let biteCentres = [CGPoint(x: bar.maxX - 6, y: bar.maxY + 10), CGPoint(x: bar.maxX - 74, y: bar.maxY + 34),
                           CGPoint(x: bar.maxX + 28, y: bar.maxY - 62)]
        ctx.addPath(tilePath)
        ctx.clip()
        for b in biteCentres {
            ctx.addEllipse(in: CGRect(x: b.x - 58, y: b.y - 58, width: 116, height: 116))
        }
        ctx.clip()
        linear(ctx, tilePath, [rgb(0xF7E6C8), rgb(0xD9AE78)], from: CGPoint(x: 0, y: tile.maxY), to: CGPoint(x: 0, y: tile.minY))
        ctx.restoreGState()
    }

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ name: String) {
    let url = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("couldn't write \(url.path)") }
}

for px in [16, 32, 64, 128, 256, 512, 1024] {
    writePNG(render(px), "icon_\(px).png")
}
print("wrote icons to \(outDir.path)")

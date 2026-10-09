import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the 1024 px app icon master: a white drop on a deep-blue tile, with
// one soft glint. No ring, numerals or text (captain's revision of concept 2).
// Run via scripts/make-app-icon.sh, which also derives Resources/AppIcon.iconset.
// Usage: swift scripts/render-app-icon.swift [--ios] <output.png>
// --ios draws the same tile full-bleed and opaque, as iOS requires (the system masks it).
let arguments = Array(CommandLine.arguments.dropFirst())
let iOS = arguments.first == "--ios"
guard arguments.count == (iOS ? 2 : 1) else {
    FileHandle.standardError.write(Data("usage: render-app-icon.swift [--ios] <output.png>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: arguments[arguments.count - 1])

let canvas = 1024
// Apple's macOS icon grid: an 824 pt rounded square centred on the 1024 canvas,
// leaving room for the system drop shadow. iOS icons fill the canvas.
let tile = iOS ? CGRect(x: 0, y: 0, width: 1024, height: 1024) : CGRect(x: 100, y: 100, width: 824, height: 824)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

// Continuous-corner tile: straight sides joined by superellipse quarters, matching
// the macOS icon shape (nominal 185.4 pt corner radius on the 824 pt tile).
func continuousRoundedSquare(in rect: CGRect, corner: CGFloat = 185.4 * 1.45, exponent n: CGFloat = 4.4,
                             steps: Int = 90) -> CGPath {
    let path = CGMutablePath()
    let centres = [CGPoint(x: rect.maxX - corner, y: rect.maxY - corner), CGPoint(x: rect.minX + corner, y: rect.maxY - corner),
                   CGPoint(x: rect.minX + corner, y: rect.minY + corner), CGPoint(x: rect.maxX - corner, y: rect.minY + corner)]
    for (quadrant, centre) in centres.enumerated() {
        for i in 0...steps {
            let t = (CGFloat(quadrant) + CGFloat(i) / CGFloat(steps)) * .pi / 2
            let c = cos(t), s = sin(t)
            let point = CGPoint(x: centre.x + corner * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n),
                                y: centre.y + corner * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n))
            quadrant == 0 && i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
    }
    path.closeSubpath()
    return path
}

// Drop in y-down tile units (the tile is 128 units wide): a round bowl of radius r
// centred at (cx, cy) whose sides sweep up to a point. Proportions follow the
// approved board mockup.
let unit = tile.width / 128
let cx = tile.midX, cy = tile.minY + 76 * unit, r = 30 * unit
func dropPath() -> CGPath {
    let path = CGMutablePath()
    let tip = CGPoint(x: cx, y: cy - 1.9 * r)
    path.move(to: tip)
    path.addCurve(to: CGPoint(x: cx - r, y: cy),
                  control1: CGPoint(x: cx - 0.5 * r, y: tip.y + 0.72 * r),
                  control2: CGPoint(x: cx - r, y: cy - 0.62 * r))
    path.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
    path.addCurve(to: tip,
                  control1: CGPoint(x: cx + r, y: cy - 0.62 * r),
                  control2: CGPoint(x: cx + 0.5 * r, y: tip.y + 0.72 * r))
    path.closeSubpath()
    return path
}

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space,
                              bitmapInfo: (iOS ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)
else { fatalError("could not create bitmap context") }
// Draw in y-down coordinates; shadow offsets stay in device space (negative y is down).
context.translateBy(x: 0, y: CGFloat(canvas))
context.scaleBy(x: 1, y: -1)

let tileShape = iOS ? CGPath(rect: tile, transform: nil) : continuousRoundedSquare(in: tile)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: rgb(0x000000, 0.3))
context.addPath(tileShape)
context.setFillColor(rgb(0x0e2463))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tileShape)
context.clip()
let background = CGGradient(colorsSpace: space, colors: [rgb(0x2b5fc9), rgb(0x0d2160)] as CFArray,
                            locations: [0, 1])!
context.drawLinearGradient(background, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY),
                           options: [])
context.restoreGState()

let drop = dropPath()
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: rgb(0x061235, 0.35))
context.addPath(drop)
context.setFillColor(rgb(0xffffff))
context.fillPath()
context.restoreGState()

// The single glint: a soft blue-tinted arc hugging the lower-left of the bowl,
// like the curved reflection on the board mockup. It fades out at small sizes.
context.saveGState()
context.addPath(drop)
context.clip()
let glint = CGMutablePath()
glint.move(to: CGPoint(x: cx - 0.56 * r, y: cy + 0.06 * r))
glint.addQuadCurve(to: CGPoint(x: cx - 0.12 * r, y: cy + 0.62 * r),
                   control: CGPoint(x: cx - 0.56 * r, y: cy + 0.5 * r))
context.setShadow(offset: .zero, blur: 10, color: rgb(0x2b5fc9, 0.35))
context.addPath(glint)
context.setLineWidth(0.13 * r)
context.setLineCap(.round)
context.setStrokeColor(rgb(0x2b5fc9, 0.28))
context.strokePath()
context.restoreGState()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not create PNG destination at \(output.path)") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(output.path)") }
print("wrote \(output.path)")

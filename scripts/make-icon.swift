import AppKit
import SwiftUI
import CoreGraphics
import Foundation

// MARK: - Geometry

/// A rounded rectangle with longer, smoothly easing corners than CGPath's
/// circular rounded rectangle.  The geometry is built from cubic curves so the
/// result has the continuous-corner character used by modern macOS icons.
/// `radius` is the design corner radius; the icon uses 22.37% of its width.
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    // SwiftUI's .continuous style is Apple's own squircle curve; approximating
    // it by hand produced corners round enough that macOS 26 stopped treating
    // the artwork as an app-icon silhouette and inset it onto a grey plaque.
    Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath
}

func impellerBlade(center: CGPoint, radius r: CGFloat) -> CGPath {
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: center.x + x * r, y: center.y + y * r)
    }

    let path = CGMutablePath()
    path.move(to: point(0.14, 0.18))
    path.addCurve(
        to: point(0.70, 0.51),
        control1: point(0.23, 0.34),
        control2: point(0.47, 0.48)
    )
    path.addCurve(
        to: point(0.91, 0.79),
        control1: point(0.87, 0.53),
        control2: point(0.97, 0.67)
    )
    path.addCurve(
        to: point(0.57, 0.94),
        control1: point(0.84, 0.96),
        control2: point(0.69, 1.00)
    )
    path.addCurve(
        to: point(-0.04, 0.34),
        control1: point(0.29, 0.78),
        control2: point(0.07, 0.53)
    )
    path.addCurve(
        to: point(0.14, 0.18),
        control1: point(-0.09, 0.25),
        control2: point(0.03, 0.13)
    )
    path.closeSubpath()
    return path
}

// MARK: - Drawing helpers

func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [red, green, blue, alpha])!
}

func fillEllipse(_ context: CGContext, _ rect: CGRect, color: CGColor) {
    context.setFillColor(color)
    context.fillEllipse(in: rect)
}

func strokeEllipse(_ context: CGContext, _ rect: CGRect, color: CGColor, width: CGFloat) {
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.strokeEllipse(in: rect)
}

// MARK: - Icon artwork

func drawIcon(in context: CGContext, size: Int) {
    let s = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // The 80% squircle leaves a transparent perimeter for the macOS icon
    // silhouette and enough room for the shadow to breathe.
    let tile = CGRect(x: s * 0.0977, y: s * 0.0977, width: s * 0.8047, height: s * 0.8047)
    let tilePath = continuousRoundedRect(tile, radius: tile.width * 0.2237)

    // Soft shadow, biased visually downward (negative y in Core Graphics).
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -s * 0.012),
        blur: s * 0.020,
        color: rgb(0.02, 0.07, 0.12, 0.34)
    )
    context.addPath(tilePath)
    context.setFillColor(rgb(0.04, 0.24, 0.38))
    context.fillPath()
    context.restoreGState()

    // Cool teal-to-blue enamel, subtly lighter toward the top.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let background = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            rgb(0.13, 0.70, 0.76),
            rgb(0.04, 0.42, 0.63),
            rgb(0.025, 0.24, 0.43)
        ] as CFArray,
        locations: [0.0, 0.55, 1.0]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: tile.midX, y: tile.maxY),
        end: CGPoint(x: tile.midX, y: tile.minY),
        options: []
    )

    // A restrained top sheen gives the tile depth without adding fine detail
    // that would disappear at menu-bar scale.
    let sheen = CGGradient(
        colorsSpace: colorSpace,
        colors: [rgb(1, 1, 1, 0.22), rgb(1, 1, 1, 0.0)] as CFArray,
        locations: [0.0, 1.0]
    )!
    context.drawLinearGradient(
        sheen,
        start: CGPoint(x: tile.midX, y: tile.maxY),
        end: CGPoint(x: tile.midX, y: tile.midY),
        options: []
    )
    context.restoreGState()

    // Fine inner rim. Clamp widths so even the 16 px icon gets a visible but
    // not overpowering edge.
    context.saveGState()
    context.addPath(tilePath)
    context.setStrokeColor(rgb(0.80, 1.00, 1.00, 0.30))
    context.setLineWidth(max(0.6, s * 0.006))
    context.strokePath()
    context.restoreGState()

    let center = CGPoint(x: tile.midX, y: tile.midY + s * 0.004)
    let fanRadius = tile.width * 0.325

    // A dark backing disc separates the pale impeller from the blue tile and
    // keeps the fan recognisable at 16 and 32 pixels.
    let backingRect = CGRect(
        x: center.x - fanRadius * 1.04,
        y: center.y - fanRadius * 1.04,
        width: fanRadius * 2.08,
        height: fanRadius * 2.08
    )
    fillEllipse(context, backingRect, color: rgb(0.015, 0.12, 0.22, 0.30))

    // Five hand-drawn swept blades. The slight shadow defines their gaps at
    // small sizes without relying on outlines or any system-symbol artwork.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -s * 0.008),
        blur: s * 0.008,
        color: rgb(0.00, 0.08, 0.13, 0.38)
    )
    for index in 0..<5 {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat(index) * (2 * .pi / 5))
        context.translateBy(x: -center.x, y: -center.y)
        context.addPath(impellerBlade(center: center, radius: fanRadius))
        context.setFillColor(rgb(0.88, 0.98, 0.98))
        context.fillPath()
        context.restoreGState()
    }
    context.restoreGState()

    // Compact hub with a bright retaining ring and a blue centre cap.
    let hubRadius = fanRadius * 0.245
    let hubRect = CGRect(
        x: center.x - hubRadius,
        y: center.y - hubRadius,
        width: hubRadius * 2,
        height: hubRadius * 2
    )
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -s * 0.006),
        blur: s * 0.008,
        color: rgb(0.00, 0.06, 0.10, 0.45)
    )
    fillEllipse(context, hubRect, color: rgb(0.92, 1.00, 1.00))
    context.restoreGState()

    let capInset = max(0.8, hubRadius * 0.32)
    let capRect = hubRect.insetBy(dx: capInset, dy: capInset)
    fillEllipse(context, capRect, color: rgb(0.035, 0.35, 0.53))
    strokeEllipse(
        context,
        capRect,
        color: rgb(0.72, 1.00, 1.00, 0.75),
        width: max(0.45, s * 0.0035)
    )
}

// MARK: - PNG output

enum IconError: Error, CustomStringConvertible {
    case usage
    case cannotCreateContext(Int)
    case cannotCreateImage(Int)
    case cannotEncodePNG(Int)

    var description: String {
        switch self {
        case .usage:
            return "Usage: ./makeicon <output-directory>"
        case .cannotCreateContext(let size):
            return "Could not create a \(size)x\(size) bitmap context"
        case .cannotCreateImage(let size):
            return "Could not create the \(size)x\(size) CGImage"
        case .cannotEncodePNG(let size):
            return "Could not encode the \(size)x\(size) PNG"
        }
    }
}

func renderPNG(size: Int, destination: URL) throws {
    // RGBA, 8 bits per component, premultiplied alpha. Each requested image is
    // rendered directly into its own native-resolution bitmap.
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw IconError.cannotCreateContext(size)
    }

    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    drawIcon(in: context, size: size)

    guard let image = context.makeImage() else {
        throw IconError.cannotCreateImage(size)
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw IconError.cannotEncodePNG(size)
    }
    try png.write(to: destination, options: .atomic)
}

do {
    guard CommandLine.arguments.count == 2 else {
        throw IconError.usage
    }

    let outputURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(
        at: outputURL,
        withIntermediateDirectories: true,
        attributes: nil
    )

    let sizes = [16, 32, 64, 128, 256, 512, 1024]
    for size in sizes {
        let destination = outputURL.appendingPathComponent("icon_\(size).png")
        try renderPNG(size: size, destination: destination)
        print("Wrote \(destination.path) (\(size)x\(size))")
    }
} catch {
    FileHandle.standardError.write(Data("makeicon: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}

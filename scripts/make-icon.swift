#!/usr/bin/env swift
//
// Draws Resources/Toe.icns. Run it with `make icon` — never as part of a build, since the
// committed .icns is what `scripts/bundle.sh` ships and regenerating a binary file on every
// build would churn the tree for nothing.
//
// Everything here is vector, drawn from scratch at each output size. That keeps the whole icon
// in one reviewable text file, needs nothing but the Swift toolchain the package already
// requires, and — unlike downscaling a single 1024px master — lets the small sizes drop detail
// that would otherwise turn to mud. `iconutil` and `sips` are both in /usr/bin on stock macOS,
// so there is no third-party dependency either.

import AppKit
import Foundation

// MARK: - Design constants

/// The icon's geometry, all of it expressed as a fraction of the output's pixel size so a
/// single set of numbers drives every size from 16px to 1024px.
enum Design {

    // MARK: Bundle shape

    /// Apple's macOS icon grid puts a square app icon's rounded shape at 824pt on a 1024pt
    /// canvas — a ~10% transparent margin on every side, which the system relies on for its
    /// own drop shadow and spacing. Drawing on-grid also matters on macOS 26: it masks legacy
    /// .icns icons to the system shape, and a shape already on the grid coincides with that
    /// mask instead of being inset a second time.
    static let shapeFraction: CGFloat = 824.0 / 1024.0

    /// Apple's shape is a *continuous* rounded rect: straight sides over the middle of each
    /// edge, and a corner whose curvature eases in rather than starting abruptly at a tangent
    /// point. Two knobs approximate it — how far the corner runs along each edge, and how full
    /// the cubic is between those two points.
    ///
    /// These are fitted, not guessed. AppKit exposes no continuous-corner path to borrow
    /// (`CALayer.cornerCurve` is a layer property, not a path), so both values come from a
    /// parameter sweep against the alpha silhouette of a real system icon — Calculator's
    /// AppIcon.icns at 1024px. The fit lands at 1.50px rms across all 824 rows of the shape,
    /// i.e. under a fifth of a pixel at 128px. Eyeballing was actively misleading here: a
    /// plausible-looking tension of 0.45 measures 25.5px rms, and the error hides in the
    /// corner where a downscaled preview cannot show it.
    ///
    /// Note the tension is *above* the 0.5523 that would make this run a circular arc, not
    /// below it. The continuous corner both starts earlier along the edge and stays fuller
    /// once it does — which is the opposite of the intuition that a "softer" corner means a
    /// slacker curve.
    ///
    /// Two shapes that were tried and are wrong for macOS: a superellipse, which spreads
    /// curvature over the whole outline and so has no straight sides at all (visibly blobby),
    /// and a plain `CGPath(roundedRect:)`, whose circular arc reads pinched at the corners.
    static let cornerRun: CGFloat = 0.294
    static let cornerTension: CGFloat = 0.740

    // MARK: Ground

    /// Graphite, lit from above. Deliberately colourless: toe's only visible surface is a
    /// monochrome menu bar strip, and inventing a brand colour here would be the one place in
    /// the whole product it appears.
    ///
    /// Kept lighter than it first looks like it wants to be. A darker graphite reads better in
    /// isolation but sinks into a dark-mode Finder window or a near-black launcher grid, where
    /// this icon has to hold its own silhouette.
    static let groundTop = RGB(0x45, 0x4B, 0x54)
    static let groundBottom = RGB(0x29, 0x2D, 0x33)

    /// A sheen down from the top edge, and a hairline rim around the whole shape. Both are
    /// what stop a flat gradient from looking like a coloured rectangle — and the rim is the
    /// other half of staying visible against black.
    static let sheenAlpha: CGFloat = 0.10
    static let sheenDepth: CGFloat = 0.18
    static let rimAlpha: CGFloat = 0.11

    // MARK: The T

    /// A "T" built from tiled panes rather than set in a typeface: a full-width crossbar with
    /// a stem below it, split by a gutter. The silhouette is purely typographic, but the
    /// gutter says what the app is for.
    static let paneColor = RGB(0xF2, 0xF4, 0xF7)

    /// The T's bounding box, as a fraction of the bundle shape. Taller than it is wide, as a
    /// set letter is — an equal-sided box renders as a squat nail rather than a T.
    static let tWidth: CGFloat = 0.52
    static let tHeight: CGFloat = 0.60

    /// How the T divides that box: crossbar depth and stem width. Chosen so the two strokes
    /// come out within a pixel or two of each other at 1024px (~119px each on the 824 grid),
    /// which is what makes the letter look drawn rather than assembled.
    static let crossbarDepth: CGFloat = 0.24
    static let stemWidth: CGFloat = 0.28

    /// The gutter between crossbar and stem, as a fraction of the bundle shape.
    ///
    /// toe's own `gaps_in` default is 5pt, which on a real display is about a third of one
    /// percent of the screen — far too fine to survive here. This is the gap read as a graphic
    /// device rather than to scale.
    ///
    /// Tuned down from 0.020 once the shadow compositing was fixed and it became visible at
    /// large sizes for the first time: at 0.020 it reads as a gap that interrupts the letter,
    /// where the intent is a seam that hints at tiling without costing legibility.
    static let gutter: CGFloat = 0.014

    /// Pane corners, as a fraction of the bundle shape. In the neighbourhood of a real macOS
    /// window's 24pt rounding relative to a display, then nudged up so it still reads as
    /// rounded at 128px.
    static let paneRadius: CGFloat = 0.020

    /// Depth under the panes. Large sizes only — see `Detail`.
    static let shadowAlpha: CGFloat = 0.30
    static let shadowBlur: CGFloat = 0.020
    static let shadowOffset: CGFloat = 0.011

    /// The crossbar sits back from the stem, the same focused/unfocused distinction
    /// `StatusItem.marker(filled:)` draws with a filled square against dimmed digits — carried
    /// in opacity rather than hue, because the menu bar has no second colour either.
    static let crossbarAlpha: CGFloat = 0.93
    static let stemAlpha: CGFloat = 1.0
}

/// How much detail an output size can actually hold.
///
/// Below these thresholds the fine work stops being detail and starts being noise: a 2px gutter
/// dithers into grey, and a blurred shadow just fogs the panes. Small sizes get one solid,
/// full-opacity T instead — the same decision Apple's own icons make between their 512 and
/// 16px representations.
enum Detail {
    /// Under this, crossbar and stem merge into a single solid T with no gutter.
    static let gutterFloor = 128

    /// Under this, no shadow.
    static let shadowFloor = 256

    /// A hairline can't be drawn thinner than a pixel, so the rim is dropped where it would
    /// swamp the shape.
    static let rimFloor = 64

    /// The stem thickens at small sizes. A stem scaled straight down disappears next to the
    /// crossbar; this keeps the T legible as a letter at 16px.
    static func stemWidth(forPixelSize px: Int) -> CGFloat {
        px >= gutterFloor ? Design.stemWidth : Design.stemWidth * 1.22
    }
}

// MARK: - Colour

struct RGB {
    let r: CGFloat, g: CGFloat, b: CGFloat

    init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = CGFloat(r) / 255
        self.g = CGFloat(g) / 255
        self.b = CGFloat(b) / 255
    }

    func cgColor(alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    var components: [CGFloat] { [r, g, b, 1] }
}

// MARK: - Paths

/// Apple's continuous rounded rect: straight sides, and corners eased with a cubic Bézier.
///
/// Each corner runs `run` in from the true corner along both edges, then a single cubic joins
/// those two points with control points pulled `tension` of the way toward the corner. At
/// `tension == 0.5523` any given run degenerates into a circular arc; the fitted values in
/// `Design` sit above that, which is what produces the continuous curve.
func bundleShapePath(center: CGPoint, side: CGFloat) -> CGPath {
    let half = side / 2
    let x0 = center.x - half, x1 = center.x + half
    let y0 = center.y - half, y1 = center.y + half
    let d = side * Design.cornerRun
    let t = Design.cornerTension

    let path = CGMutablePath()
    path.move(to: CGPoint(x: x0 + d, y: y0))
    path.addLine(to: CGPoint(x: x1 - d, y: y0))
    // Bottom-right, then anticlockwise round the shape. Each corner's control points sit on
    // the two edges, `t * d` short of where they would meet.
    path.addCurve(
        to: CGPoint(x: x1, y: y0 + d),
        control1: CGPoint(x: x1 - d + t * d, y: y0),
        control2: CGPoint(x: x1, y: y0 + d - t * d))
    path.addLine(to: CGPoint(x: x1, y: y1 - d))
    path.addCurve(
        to: CGPoint(x: x1 - d, y: y1),
        control1: CGPoint(x: x1, y: y1 - d + t * d),
        control2: CGPoint(x: x1 - d + t * d, y: y1))
    path.addLine(to: CGPoint(x: x0 + d, y: y1))
    path.addCurve(
        to: CGPoint(x: x0, y: y1 - d),
        control1: CGPoint(x: x0 + d - t * d, y: y1),
        control2: CGPoint(x: x0, y: y1 - d + t * d))
    path.addLine(to: CGPoint(x: x0, y: y0 + d))
    path.addCurve(
        to: CGPoint(x: x0 + d, y: y0),
        control1: CGPoint(x: x0, y: y0 + d - t * d),
        control2: CGPoint(x: x0 + d - t * d, y: y0))
    path.closeSubpath()
    return path
}

// MARK: - Drawing

func drawIcon(into ctx: CGContext, pixelSize px: Int) {
    let size = CGFloat(px)
    let center = CGPoint(x: size / 2, y: size / 2)
    let shapeSide = size * Design.shapeFraction
    let shape = bundleShapePath(center: center, side: shapeSide)

    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // --- Ground -------------------------------------------------------------------------
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    if let gradient = CGGradient(
        colorSpace: space,
        colorComponents: Design.groundBottom.components + Design.groundTop.components,
        locations: [0, 1], count: 2) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: center.y - shapeSide / 2),
            end: CGPoint(x: 0, y: center.y + shapeSide / 2),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    // Sheen from the top edge downward, still inside the clip.
    let sheenTop = center.y + shapeSide / 2
    if let sheen = CGGradient(
        colorSpace: space,
        colorComponents: [1, 1, 1, 0, 1, 1, 1, Design.sheenAlpha],
        locations: [0, 1], count: 2) {
        ctx.drawLinearGradient(
            sheen,
            start: CGPoint(x: 0, y: sheenTop - shapeSide * Design.sheenDepth),
            end: CGPoint(x: 0, y: sheenTop),
            options: [])
    }
    ctx.restoreGState()

    // --- Rim ----------------------------------------------------------------------------
    // Stroked inside the shape's own clip so only the inner half of the line lands, giving a
    // hairline that reads as a lit edge rather than a border drawn around the icon.
    if px >= Detail.rimFloor {
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.addPath(shape)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: Design.rimAlpha))
        ctx.setLineWidth(max(1, size * 0.004) * 2)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // --- The T --------------------------------------------------------------------------
    let box = CGRect(
        x: center.x - shapeSide * Design.tWidth / 2,
        y: center.y - shapeSide * Design.tHeight / 2,
        width: shapeSide * Design.tWidth,
        height: shapeSide * Design.tHeight)
    let radius = shapeSide * Design.paneRadius
    let stemWidth = Detail.stemWidth(forPixelSize: px)
    let drawsGutter = px >= Detail.gutterFloor

    // Crossbar and stem as separate rects. Without a gutter they meet exactly, which is the
    // solid T the small sizes want.
    let gutter = drawsGutter ? shapeSide * Design.gutter : 0
    let crossbarHeight = box.height * Design.crossbarDepth
    let crossbar = CGRect(
        x: box.minX, y: box.maxY - crossbarHeight,
        width: box.width, height: crossbarHeight)
    let stemW = box.width * stemWidth
    let stem = CGRect(
        x: box.midX - stemW / 2, y: box.minY,
        width: stemW, height: box.height - crossbarHeight - gutter)

    let crossbarPath = CGPath(roundedRect: crossbar, cornerWidth: radius, cornerHeight: radius, transform: nil)
    let stemPath = CGPath(roundedRect: stem, cornerWidth: radius, cornerHeight: radius, transform: nil)
    let silhouette = CGMutablePath()
    silhouette.addPath(crossbarPath)
    silhouette.addPath(stemPath)

    // --- Shadow -------------------------------------------------------------------------
    // Cast from the panes, but clipped to everything *outside* them, so only the spill lands.
    //
    // The obvious version of this — set a shadow, fill the shape, move on — silently destroys
    // both pane details. The fill is opaque, so it paints over the gutter the pane pass is
    // about to draw around, and it puts an opaque layer of the pane colour under the
    // translucent crossbar, where `α·C + (1-α)·C == C` flattens `crossbarAlpha` to nothing.
    // The result renders correctly *only* between gutterFloor and shadowFloor, which is one
    // representation, and degrades to a solid T at exactly the sizes with room for the detail.
    //
    // Clipping to the inverse keeps the shadow and discards the fill that caused both problems.
    // Shadow does fall into the gutter now, which is right: the panes are two objects over the
    // ground, and the gap between tiled windows is where you would see that.
    if px >= Detail.shadowFloor {
        ctx.saveGState()
        let outside = CGMutablePath()
        outside.addRect(CGRect(x: 0, y: 0, width: size, height: size))
        outside.addPath(silhouette)
        ctx.addPath(outside)
        ctx.clip(using: .evenOdd)
        ctx.setShadow(
            offset: CGSize(width: 0, height: -size * Design.shadowOffset),
            blur: size * Design.shadowBlur,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: Design.shadowAlpha))
        ctx.addPath(silhouette)
        // Colour is irrelevant — the clip discards every pixel of this fill. Only its shadow
        // survives, outside the panes.
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // --- Panes --------------------------------------------------------------------------
    // With no gutter the two rects abut, so they must share an alpha or the seam shows.
    ctx.setFillColor(Design.paneColor.cgColor(alpha: drawsGutter ? Design.crossbarAlpha : Design.stemAlpha))
    ctx.addPath(crossbarPath)
    ctx.fillPath()

    ctx.setFillColor(Design.paneColor.cgColor(alpha: Design.stemAlpha))
    ctx.addPath(stemPath)
    ctx.fillPath()
}

// MARK: - Output

func renderPNG(pixelSize px: Int) -> Data {
    guard let ctx = CGContext(
        data: nil, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("could not create a \(px)x\(px) bitmap context") }

    drawIcon(into: ctx, pixelSize: px)

    guard let image = ctx.makeImage() else { fatalError("could not snapshot the \(px)px context") }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: px, height: px)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode the \(px)px PNG")
    }
    return png
}

/// The ten representations `iconutil` expects, as (filename, pixel size). Several sizes are
/// written twice under different names — a 32px image is both `icon_16x16@2x` and
/// `icon_32x32`, and iconutil wants both files present.
let representations: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
// Intermediates go under build/, which is already gitignored, so only the .icns is committed.
let iconset = root.appendingPathComponent("build/Toe.iconset")
let icns = root.appendingPathComponent("Resources/Toe.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (name, px) in representations {
    let url = iconset.appendingPathComponent("\(name).png")
    try renderPNG(pixelSize: px).write(to: url)
    print("drew \(name).png (\(px)px)")
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed with status \(iconutil.terminationStatus)\n".data(using: .utf8)!)
    exit(1)
}

print("wrote \(icns.path)")

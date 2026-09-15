#!/usr/bin/env swift

// Draws the app icon master and exports every size the macOS AppIcon set needs.
//
// Run from the repo root:
//   swift scripts/make-icon.swift
//
// Committing the generated PNGs keeps CI from needing to run this.

import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: "DesktopVideoCompress/DesktopVideoCompress/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let masterSize: CGFloat = 1024

func drawIcon(in context: CGContext, size: CGFloat) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // macOS icons sit inset inside their canvas rather than bleeding to the edge.
    let inset = size * 0.085
    let body = rect.insetBy(dx: inset, dy: inset)
    let corner = body.width * 0.2237  // Apple's squircle radius ratio

    let path = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)

    context.saveGState()
    context.addPath(path)
    context.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.29, green: 0.36, blue: 0.95, alpha: 1),
            CGColor(red: 0.55, green: 0.25, blue: 0.90, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: body.minX, y: body.maxY),
        end: CGPoint(x: body.maxX, y: body.minY),
        options: []
    )
    context.restoreGState()

    // Film sprocket strips down both edges.
    let stripWidth = body.width * 0.11
    let holeWidth = stripWidth * 0.52
    let holeHeight = body.height * 0.058
    let holeCount = 6
    let spacing = body.height / CGFloat(holeCount + 1)

    context.setFillColor(CGColor(gray: 1, alpha: 0.28))
    for index in 1...holeCount {
        let y = body.minY + spacing * CGFloat(index) - holeHeight / 2
        for stripX in [body.minX + (stripWidth - holeWidth) / 2,
                       body.maxX - stripWidth + (stripWidth - holeWidth) / 2] {
            let hole = CGRect(x: stripX, y: y, width: holeWidth, height: holeHeight)
            context.addPath(CGPath(
                roundedRect: hole,
                cornerWidth: holeWidth * 0.3,
                cornerHeight: holeWidth * 0.3,
                transform: nil
            ))
        }
    }
    context.fillPath()

    // Downward arrow: "make this smaller".
    let center = CGPoint(x: body.midX, y: body.midY)
    let shaftWidth = body.width * 0.115
    let shaftTop = center.y + body.height * 0.215
    let shaftBottom = center.y - body.height * 0.045

    context.setFillColor(CGColor(gray: 1, alpha: 0.96))
    context.addPath(CGPath(
        roundedRect: CGRect(
            x: center.x - shaftWidth / 2,
            y: shaftBottom,
            width: shaftWidth,
            height: shaftTop - shaftBottom
        ),
        cornerWidth: shaftWidth / 2,
        cornerHeight: shaftWidth / 2,
        transform: nil
    ))
    context.fillPath()

    let headHalfWidth = body.width * 0.155
    let headTip = center.y - body.height * 0.235
    context.move(to: CGPoint(x: center.x - headHalfWidth, y: shaftBottom + shaftWidth * 0.35))
    context.addLine(to: CGPoint(x: center.x + headHalfWidth, y: shaftBottom + shaftWidth * 0.35))
    context.addLine(to: CGPoint(x: center.x, y: headTip))
    context.closePath()
    context.fillPath()
}

func renderPNG(size: CGFloat) throws -> Data {
    let pixels = Int(size)
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "make-icon", code: 1)
    }

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    drawIcon(in: context, size: size)

    guard let image = context.makeImage() else { throw NSError(domain: "make-icon", code: 2) }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 3)
    }
    return data
}

// (point size, scale) pairs required by a macOS AppIcon set.
let variants: [(point: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2),
    (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

var entries: [[String: String]] = []
var written: Set<String> = []

for variant in variants {
    let pixels = variant.point * variant.scale
    let filename = "icon_\(pixels)x\(pixels).png"

    if !written.contains(filename) {
        let data = try renderPNG(size: CGFloat(pixels))
        try data.write(to: outputDirectory.appendingPathComponent(filename))
        written.insert(filename)
        print("wrote \(filename)")
    }

    entries.append([
        "idiom": "mac",
        "size": "\(variant.point)x\(variant.point)",
        "scale": "\(variant.scale)x",
        "filename": filename,
    ])
}

let contents: [String: Any] = [
    "images": entries,
    "info": ["version": 1, "author": "xcode"],
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDirectory.appendingPathComponent("Contents.json"))
print("wrote Contents.json (master \(Int(masterSize))px)")

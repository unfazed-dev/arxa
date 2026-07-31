// lens_native — appbox lens macOS helper: ScreenCaptureKit one-shot capture +
// Vision OCR. Single file, no packages. Compiled on demand by
// lib/lens/native/sck.dart (ensureLensNativeBinary) into
// .dart_tool/appboxd/lens_native and driven through the ProcessRunner seam.
//
// Usage:
//   lens_native shot <out.png> [--window-id N]
//   lens_native ocr <image.png>
//   lens_native tcc-check
//
// The TCC Screen-Recording grant follows the responsible terminal process,
// not this binary. `tcc-check` preflights WITHOUT prompting
// (CGPreflightScreenCaptureAccess); `shot` performs the real capture and will
// fail if the terminal lacks the grant. Plan: appbox-lens-full-port.md, Task 10.

import Foundation
import ScreenCaptureKit
import Vision
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: lens_native shot|ocr|tcc-check ...\n".data(using: .utf8)!)
    exit(64)
}

/// Writes a CGImage to `path` as PNG via ImageIO.
func writePng(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "lens", code: 1) }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) { throw NSError(domain: "lens", code: 2) }
}

switch args[1] {
case "tcc-check":
    // Returns 0 when the terminal already has Screen Recording, 3 otherwise.
    // Does NOT prompt — use CGRequestScreenCaptureAccess() to prompt.
    exit(CGPreflightScreenCaptureAccess() ? 0 : 3)

case "shot":
    guard args.count >= 3 else { exit(64) }
    let out = args[2]
    let sem = DispatchSemaphore(value: 0)
    var code: Int32 = 0
    Task {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            let filter: SCContentFilter
            if let wi = args.firstIndex(of: "--window-id"),
               wi + 1 < args.count,
               let id = Int(args[wi + 1]),
               let win = content.windows.first(where: { $0.windowID == CGWindowID(id) }) {
                filter = SCContentFilter(desktopIndependentWindow: win)
            } else if let display = content.displays.first {
                filter = SCContentFilter(display: display, excludingWindows: [])
            } else {
                throw NSError(domain: "lens", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "no capturable target"])
            }
            let config = SCStreamConfiguration()
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            try writePng(image, to: out)
        } catch {
            FileHandle.standardError.write(
                "shot failed: \(error.localizedDescription)\n".data(using: .utf8)!)
            code = 1
        }
        sem.signal()
    }
    sem.wait()
    exit(code)

case "ocr":
    guard args.count >= 3 else { exit(64) }
    do {
        let url = URL(fileURLWithPath: args[2])
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else {
            FileHandle.standardError.write("unreadable image\n".data(using: .utf8)!)
            exit(2)
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        var observations: [[String: Any]] = []
        var texts: [String] = []
        for obs in request.results ?? [] {
            guard let top = obs.topCandidates(1).first else { continue }
            texts.append(top.string)
            observations.append([
                "text": top.string,
                "confidence": top.confidence,
                "bbox": [
                    obs.boundingBox.origin.x,
                    obs.boundingBox.origin.y,
                    obs.boundingBox.size.width,
                    obs.boundingBox.size.height,
                ],
            ])
        }
        let json: [String: Any] = ["text": texts, "observations": observations]
        let data = try JSONSerialization.data(withJSONObject: json)
        FileHandle.standardOutput.write(data)
        exit(0)
    } catch {
        FileHandle.standardError.write(
            "ocr failed: \(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }

default:
    FileHandle.standardError.write("unknown subcommand: \(args[1])\n".data(using: .utf8)!)
    exit(64)
}

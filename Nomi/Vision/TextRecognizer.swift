import CoreGraphics
import Foundation
import Vision

/// A line of recognised text and where it sits on screen.
nonisolated struct RecognizedLine: Sendable, Equatable {
    var text: String
    /// Screen points, top-left origin.
    var frame: CGRect
    var confidence: Float
}

/// Runs Vision text recognition on a captured window and maps the results back to screen coordinates.
nonisolated enum TextRecognizer {
    static func recognize(_ capture: ScreenCapture.WindowImage) async throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: capture.image, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        let frame = capture.frame
        return observations.compactMap { observation -> RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            // Vision boxes are normalised with a bottom-left origin; flip into the window's top-left space.
            let box = observation.boundingBox
            let rect = CGRect(
                x: frame.minX + box.minX * frame.width,
                y: frame.minY + (1 - box.maxY) * frame.height,
                width: box.width * frame.width,
                height: box.height * frame.height
            )
            return RecognizedLine(text: candidate.string, frame: rect, confidence: candidate.confidence)
        }
        .sorted { lhs, rhs in
            // Reading order: top to bottom, then left to right, with a tolerance for the same line.
            if abs(lhs.frame.midY - rhs.frame.midY) > min(lhs.frame.height, rhs.frame.height) * 0.6 {
                return lhs.frame.midY < rhs.frame.midY
            }
            return lhs.frame.minX < rhs.frame.minX
        }
    }

    /// Groups lines into paragraphs by vertical gaps, so the model gets readable text rather than a word soup.
    static func paragraphs(from lines: [RecognizedLine]) -> String {
        var result: [String] = []
        var previous: RecognizedLine?
        for line in lines {
            if let previous, line.frame.minY - previous.frame.maxY > previous.frame.height * 0.8 {
                result.append("")
            }
            result.append(line.text)
            previous = line
        }
        return result.joined(separator: "\n")
    }
}

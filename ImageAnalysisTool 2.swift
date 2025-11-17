import Foundation
import Vision
import ImageIO
import CoreML

final class ImageAnalysisTool {
    struct Arguments {
        var mode: String?
        init(mode: String? = nil) { self.mode = mode }
    }

    private let imageProvider: () -> Data?

    init(imageProvider: @escaping () -> Data?) {
        self.imageProvider = imageProvider
    }

    func call(arguments: Arguments) async throws -> String {
        guard let data = imageProvider(), !data.isEmpty else { return "" }
        guard let cgImage = Self.makeCGImage(from: data) else { return "" }

        let width = cgImage.width
        let height = cgImage.height
        let sizeString = Self.humanFileSize(data.count)

        // Perform OCR with Vision
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["it-IT", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        try handler.perform([request])

        var recognizedLines: [String] = []
        if let observations = request.results {
            for obs in observations {
                if let candidate = obs.topCandidates(1).first {
                    recognizedLines.append(candidate.string)
                }
            }
        }

        // Classification (Core ML custom model if present, otherwise system classifier)
        var classificationResults: [(label: String, confidence: Float)] = []
        var classificationSource: String = "no model available"

        // Try Core ML custom model from bundle (.mlmodelc)
        if let modelURL = Bundle.main.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil)?.first,
           let mlModel = try? MLModel(contentsOf: modelURL),
           let vnModel = try? VNCoreMLModel(for: mlModel) {
            let clsRequest = VNCoreMLRequest(model: vnModel)
            let clsHandler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try clsHandler.perform([clsRequest])
                if let results = clsRequest.results as? [VNClassificationObservation] {
                    classificationResults = results.prefix(3).map { (label: $0.identifier, confidence: $0.confidence) }
                    classificationSource = "custom Core ML model"
                }
            } catch {
                // Will try system classifier below
            }
        }

        // Fallback: system on-device classifier (no custom model required)
        if classificationResults.isEmpty {
            let sysRequest = VNClassifyImageRequest()
            let sysHandler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try sysHandler.perform([sysRequest])
                if let results = sysRequest.results, !results.isEmpty {
                    classificationResults = results.prefix(3).map { (label: $0.identifier, confidence: $0.confidence) }
                    classificationSource = "system model"
                }
            } catch {
                // No classification available
            }
        }

        let linesCount = recognizedLines.count
        var parts: [String] = []
        parts.append("Image dimensions: \(width)x\(height) px")
        parts.append("File size: \(sizeString)")
        parts.append("Recognized text lines: \(linesCount)")

        parts.append("Classification: \(classificationSource)")
        if !classificationResults.isEmpty {
            for (label, conf) in classificationResults {
                let pct = Int((Double(conf) * 100.0).rounded())
                parts.append("- \(label) (\(pct)%)")
            }
        } else {
            parts.append("- no results")
        }

        if !recognizedLines.isEmpty {
            parts.append("")
            parts.append("Text (OCR):")
            parts.append(recognizedLines.joined(separator: "\n"))
        }

        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private static func makeCGImage(from data: Data) -> CGImage? {
        let cfData = data as CFData
        guard let src = CGImageSourceCreateWithData(cfData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func humanFileSize(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 KB" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.0f KB", kb)
        }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
}

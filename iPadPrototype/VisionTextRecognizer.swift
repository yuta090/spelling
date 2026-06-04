import UIKit
import Vision

struct VisionSpellingOCR {
    var language = "en-US"
    var usesLanguageCorrection = false

    func recognize(_ image: UIImage, expected: String) async throws -> [OCRCandidate] {
        guard let cgImage = image.cgImage else {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .sorted {
                        if abs($0.boundingBox.origin.y - $1.boundingBox.origin.y) > 0.04 {
                            return $0.boundingBox.origin.y > $1.boundingBox.origin.y
                        }
                        return $0.boundingBox.origin.x < $1.boundingBox.origin.x
                    }

                let candidates = observations
                    .flatMap { $0.topCandidates(3) }
                    .map {
                        OCRCandidate(
                            text: $0.string,
                            normalizedText: normalize($0.string),
                            confidence: $0.confidence
                        )
                    }

                continuation.resume(returning: candidates)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = [language]
            request.usesLanguageCorrection = usesLanguageCorrection
            request.customWords = [expected]
            request.minimumTextHeight = 0.02

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

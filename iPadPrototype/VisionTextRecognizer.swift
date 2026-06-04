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

                let candidates = buildCandidates(from: observations)

                continuation.resume(returning: candidates)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = [language]
            request.usesLanguageCorrection = usesLanguageCorrection
            request.customWords = [expected]
            request.minimumTextHeight = 0.005

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func buildCandidates(from observations: [VNRecognizedTextObservation]) -> [OCRCandidate] {
        let groups = observations
            .map { $0.topCandidates(3) }
            .filter { !$0.isEmpty }

        guard !groups.isEmpty else {
            return []
        }

        var candidates: [OCRCandidate] = []

        let bestParts = groups.compactMap(\.first)
        if !bestParts.isEmpty {
            appendCandidate(
                OCRCandidate(
                    text: bestParts.map(\.string).joined(separator: " "),
                    normalizedText: normalize(bestParts.map(\.string).joined(separator: " ")),
                    confidence: bestParts.map(\.confidence).reduce(0, +) / Float(bestParts.count)
                ),
                to: &candidates
            )
        }

        for group in groups {
            for recognizedText in group {
                appendCandidate(
                    OCRCandidate(
                        text: recognizedText.string,
                        normalizedText: normalize(recognizedText.string),
                        confidence: recognizedText.confidence
                    ),
                    to: &candidates
                )
            }
        }

        return candidates
    }

    private func appendCandidate(_ candidate: OCRCandidate, to candidates: inout [OCRCandidate]) {
        guard !candidate.normalizedText.isEmpty else {
            return
        }
        if !candidates.contains(where: { $0.normalizedText == candidate.normalizedText }) {
            candidates.append(candidate)
        }
    }
}

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

                let candidates = buildCandidates(from: observations, expected: expected)

                continuation.resume(returning: candidates)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = [language]
            request.usesLanguageCorrection = usesLanguageCorrection
            request.customWords = [expected, expected.uppercased(), expected.capitalized]
            request.minimumTextHeight = 0.005

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func buildCandidates(from observations: [VNRecognizedTextObservation], expected: String) -> [OCRCandidate] {
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

        if groups.count > 1, groups.count <= 6 {
            appendCombinationCandidates(from: groups, to: &candidates)
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

        return candidates.sorted { lhs, rhs in
            candidateRank(lhs, expected: expected) < candidateRank(rhs, expected: expected)
        }
    }

    private func appendCandidate(_ candidate: OCRCandidate, to candidates: inout [OCRCandidate]) {
        guard !candidate.normalizedText.isEmpty else {
            return
        }
        guard isEnglishLetterCandidate(candidate.text) else {
            return
        }
        if !candidates.contains(where: { $0.normalizedText == candidate.normalizedText }) {
            candidates.append(candidate)
        }
    }

    private func appendCombinationCandidates(from groups: [[VNRecognizedText]], to candidates: inout [OCRCandidate]) {
        var combinations: [(text: String, confidence: Float, count: Int)] = [("", 0, 0)]

        for group in groups {
            var next: [(text: String, confidence: Float, count: Int)] = []
            for partial in combinations {
                for recognizedText in group {
                    let joined = partial.text.isEmpty ? recognizedText.string : "\(partial.text) \(recognizedText.string)"
                    next.append((
                        text: joined,
                        confidence: partial.confidence + recognizedText.confidence,
                        count: partial.count + 1
                    ))
                }
            }
            combinations = next
        }

        for combination in combinations {
            appendCandidate(
                OCRCandidate(
                    text: combination.text,
                    normalizedText: normalize(combination.text),
                    confidence: combination.confidence / Float(max(combination.count, 1))
                ),
                to: &candidates
            )
        }
    }

    private func candidateRank(_ candidate: OCRCandidate, expected: String) -> (Int, Int, Float) {
        let expectedText = normalize(expected)
        let distance = levenshtein(candidate.normalizedText, expectedText)
        let exactPenalty = candidate.normalizedText == expectedText ? 0 : 1
        return (exactPenalty, distance, -candidate.confidence)
    }

    private func isEnglishLetterCandidate(_ text: String) -> Bool {
        var hasLetter = false

        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }

            let isUppercaseLetter = scalar.value >= 65 && scalar.value <= 90
            let isLowercaseLetter = scalar.value >= 97 && scalar.value <= 122
            if isUppercaseLetter || isLowercaseLetter {
                hasLetter = true
                continue
            }

            return false
        }

        return hasLetter
    }
}

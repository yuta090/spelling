import CoreGraphics
import Foundation
import ImageIO
import Vision

struct Candidate: Codable {
    let observationIndex: Int
    let rank: Int
    let text: String
    let normalizedText: String
    let confidence: Float
}

struct OCRResult: Codable {
    let image: String
    let expected: String
    let bestText: String
    let normalizedBestText: String
    let bestConfidence: Float
    let editDistance: Int?
    let hasStrongAlternative: Bool
    let classification: String
    let usesLanguageCorrection: Bool
    let customWords: [String]
    let candidates: [Candidate]
}

struct Options {
    var expected = ""
    var language = "en-US"
    var usesLanguageCorrection = false
    var customWords: [String] = []
    var images: [String] = []
}

enum CLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case missingExpected
    case missingImages
    case imageLoadFailed(String)

    var description: String {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)"
        case .missingExpected:
            return "Missing --expected word"
        case .missingImages:
            return "Missing image paths"
        case .imageLoadFailed(let path):
            return "Could not load image: \(path)"
        }
    }
}

func parseOptions(_ args: [String]) throws -> Options {
    var options = Options()
    var index = 0

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--expected":
            guard index + 1 < args.count else { throw CLIError.missingValue(arg) }
            options.expected = args[index + 1]
            index += 2
        case "--language":
            guard index + 1 < args.count else { throw CLIError.missingValue(arg) }
            options.language = args[index + 1]
            index += 2
        case "--language-correction":
            guard index + 1 < args.count else { throw CLIError.missingValue(arg) }
            options.usesLanguageCorrection = ["1", "true", "yes"].contains(args[index + 1].lowercased())
            index += 2
        case "--custom-word":
            guard index + 1 < args.count else { throw CLIError.missingValue(arg) }
            options.customWords.append(args[index + 1])
            index += 2
        default:
            options.images.append(arg)
            index += 1
        }
    }

    if options.expected.isEmpty {
        throw CLIError.missingExpected
    }
    if options.images.isEmpty {
        throw CLIError.missingImages
    }

    return options
}

func normalize(_ text: String) -> String {
    let allowed = Set("abcdefghijklmnopqrstuvwxyz")
    return text
        .lowercased()
        .filter { allowed.contains($0) }
}

func levenshtein(_ a: String, _ b: String) -> Int {
    let aChars = Array(a)
    let bChars = Array(b)

    if aChars.isEmpty { return bChars.count }
    if bChars.isEmpty { return aChars.count }

    var previous = Array(0...bChars.count)
    var current = Array(repeating: 0, count: bChars.count + 1)

    for i in 1...aChars.count {
        current[0] = i
        for j in 1...bChars.count {
            let substitution = previous[j - 1] + (aChars[i - 1] == bChars[j - 1] ? 0 : 1)
            let insertion = current[j - 1] + 1
            let deletion = previous[j] + 1
            current[j] = min(substitution, insertion, deletion)
        }
        swap(&previous, &current)
    }

    return previous[bChars.count]
}

func loadCGImage(path: String) throws -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw CLIError.imageLoadFailed(path)
    }
    return image
}

func classify(best: String, confidence: Float, expected: String, distance: Int?, hasStrongAlternative: Bool) -> String {
    guard !best.isEmpty, let distance else {
        return "rewrite"
    }

    if best == expected && confidence >= 0.80 && !hasStrongAlternative {
        return "autoCorrect"
    }

    if confidence < 0.35 {
        return "rewrite"
    }

    if best == expected {
        return "needsReview"
    }

    let expectedLength = max(expected.count, 1)
    let clearMissThreshold = max(2, Int(ceil(Double(expectedLength) * 0.34)))
    if distance >= clearMissThreshold && confidence >= 0.65 {
        return "autoIncorrect"
    }

    return "needsReview"
}

func recognize(path: String, options: Options) throws -> OCRResult {
    let image = try loadCGImage(path: path)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = [options.language]
    request.usesLanguageCorrection = options.usesLanguageCorrection
    request.customWords = options.customWords
    request.minimumTextHeight = 0.02

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    let observations = (request.results ?? [])
        .sorted {
            if abs($0.boundingBox.origin.y - $1.boundingBox.origin.y) > 0.04 {
                return $0.boundingBox.origin.y > $1.boundingBox.origin.y
            }
            return $0.boundingBox.origin.x < $1.boundingBox.origin.x
        }

    var candidates: [Candidate] = []
    var bestParts: [String] = []
    var confidenceSum: Float = 0

    for (observationIndex, observation) in observations.enumerated() {
        let top = observation.topCandidates(5)
        if let first = top.first {
            bestParts.append(first.string)
            confidenceSum += first.confidence
        }

        for (rank, recognizedText) in top.enumerated() {
            candidates.append(
                Candidate(
                    observationIndex: observationIndex,
                    rank: rank,
                    text: recognizedText.string,
                    normalizedText: normalize(recognizedText.string),
                    confidence: recognizedText.confidence
                )
            )
        }
    }

    let bestText = bestParts.joined(separator: " ")
    let normalizedBest = normalize(bestText)
    let expected = normalize(options.expected)
    let bestConfidence = observations.isEmpty ? 0 : confidenceSum / Float(observations.count)
    let distance = normalizedBest.isEmpty ? nil : levenshtein(normalizedBest, expected)
    let hasStrongAlternative = candidates.contains {
        $0.rank > 0 && $0.confidence >= 0.75 && $0.normalizedText != normalizedBest
    }
    let classification = classify(
        best: normalizedBest,
        confidence: bestConfidence,
        expected: expected,
        distance: distance,
        hasStrongAlternative: hasStrongAlternative
    )

    return OCRResult(
        image: path,
        expected: expected,
        bestText: bestText,
        normalizedBestText: normalizedBest,
        bestConfidence: bestConfidence,
        editDistance: distance,
        hasStrongAlternative: hasStrongAlternative,
        classification: classification,
        usesLanguageCorrection: options.usesLanguageCorrection,
        customWords: options.customWords,
        candidates: candidates
    )
}

do {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    for image in options.images {
        let result = try recognize(path: image, options: options)
        let data = try encoder.encode(result)
        print(String(decoding: data, as: UTF8.self))
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}

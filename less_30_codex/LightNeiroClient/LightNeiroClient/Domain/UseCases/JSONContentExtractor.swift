import Foundation

enum JSONContentExtractor {
    /// Извлекает первый валидно ограниченный JSON-объект или массив из текста модели.
    static func extractJSONObject(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fencedJSON = extractFencedJSON(from: trimmed) {
            return fencedJSON
        }
        return extractBalancedJSON(from: trimmed)
    }

    private static func extractFencedJSON(from text: String) -> String? {
        let fenceMarkers = ["```json", "```"]

        for marker in fenceMarkers {
            guard let fenceStart = text.range(of: marker) else { continue }
            let contentStart = fenceStart.upperBound
            guard let fenceEnd = text.range(of: "```", range: contentStart..<text.endIndex) else { continue }

            let candidate = String(text[contentStart..<fenceEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let balanced = extractBalancedJSON(from: candidate) {
                return balanced
            }
            if !candidate.isEmpty {
                return candidate
            }
        }

        return nil
    }

    private static func extractBalancedJSON(from text: String) -> String? {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            return nil
        }

        var stack: [Character] = []
        var inString = false
        var escaped = false
        var index = start

        while index < text.endIndex {
            let character = text[index]

            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                switch character {
                case "\"":
                    inString = true
                case "{", "[":
                    stack.append(character)
                case "}":
                    guard stack.last == "{" else { return nil }
                    stack.removeLast()
                    if stack.isEmpty {
                        return String(text[start...index])
                    }
                case "]":
                    guard stack.last == "[" else { return nil }
                    stack.removeLast()
                    if stack.isEmpty {
                        return String(text[start...index])
                    }
                default:
                    break
                }
            }

            index = text.index(after: index)
        }

        return nil
    }
}

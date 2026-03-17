import Foundation
import PDFKit

final class CompositeDocumentParser: DocumentParser {
    private let markdownParser: MarkdownDocumentParser
    private let codeParser: CodeDocumentParser
    private let pdfParser: PDFDocumentParserAdapter
    private let plainTextParser: PlainTextDocumentParser

    init(
        markdownParser: MarkdownDocumentParser = MarkdownDocumentParser(),
        codeParser: CodeDocumentParser = CodeDocumentParser(),
        pdfParser: PDFDocumentParserAdapter = PDFDocumentParserAdapter(),
        plainTextParser: PlainTextDocumentParser = PlainTextDocumentParser()
    ) {
        self.markdownParser = markdownParser
        self.codeParser = codeParser
        self.pdfParser = pdfParser
        self.plainTextParser = plainTextParser
    }

    func parse(url: URL) throws -> ParsedDocument {
        let ext = url.pathExtension.lowercased()

        if ["md", "markdown"].contains(ext) {
            return try markdownParser.parse(url: url)
        }

        if ["swift", "py", "js", "ts", "go", "kt", "java", "rb", "rs", "c", "cpp", "h", "hpp", "m", "mm"].contains(ext) {
            return try codeParser.parse(url: url)
        }

        if ext == "pdf" {
            return try pdfParser.parse(url: url)
        }

        if ["txt", "json", "yaml", "yml", "xml", "csv", "log"].contains(ext) || !ext.isEmpty {
            return try plainTextParser.parse(url: url)
        }

        throw RAGError.unsupportedDocumentType(url)
    }
}

struct MarkdownDocumentParser: DocumentParser {
    func parse(url: URL) throws -> ParsedDocument {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)

        var sections: [ParsedSection] = []
        var buffer: [String] = []
        var currentTitle: String? = nil
        var currentOffset = 0
        var runningOffset = 0

        for line in lines {
            let isHeading = line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
            if isHeading {
                let sectionText = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !sectionText.isEmpty {
                    sections.append(ParsedSection(title: currentTitle, content: sectionText, offset: currentOffset))
                }
                currentTitle = line
                    .replacingOccurrences(of: "#", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                currentOffset = runningOffset
                buffer = []
            } else {
                buffer.append(line)
            }
            runningOffset += line.count + 1
        }

        let tailText = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !tailText.isEmpty {
            sections.append(ParsedSection(title: currentTitle, content: tailText, offset: currentOffset))
        }

        if sections.isEmpty {
            sections = [ParsedSection(title: nil, content: text, offset: 0)]
        }

        return ParsedDocument(
            source: url.path,
            title: url.deletingPathExtension().lastPathComponent,
            kind: .markdown,
            fullText: text,
            sections: sections
        )
    }
}

struct CodeDocumentParser: DocumentParser {
    func parse(url: URL) throws -> ParsedDocument {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)

        let markers = ["struct ", "class ", "enum ", "protocol ", "extension ", "func ", "actor ", "def "]

        var sections: [ParsedSection] = []
        var buffer: [String] = []
        var currentTitle: String? = nil
        var currentOffset = 0
        var runningOffset = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let hasMarker = markers.contains { trimmed.hasPrefix($0) }
            if hasMarker {
                let sectionText = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !sectionText.isEmpty {
                    sections.append(ParsedSection(title: currentTitle, content: sectionText, offset: currentOffset))
                }
                currentTitle = trimmed
                currentOffset = runningOffset
                buffer = [line]
            } else {
                buffer.append(line)
            }
            runningOffset += line.count + 1
        }

        let tailText = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !tailText.isEmpty {
            sections.append(ParsedSection(title: currentTitle, content: tailText, offset: currentOffset))
        }

        if sections.isEmpty {
            sections = [ParsedSection(title: nil, content: text, offset: 0)]
        }

        return ParsedDocument(
            source: url.path,
            title: url.lastPathComponent,
            kind: .code,
            fullText: text,
            sections: sections
        )
    }
}

struct PDFDocumentParserAdapter: DocumentParser {
    func parse(url: URL) throws -> ParsedDocument {
        guard let document = PDFDocument(url: url) else {
            throw RAGError.unsupportedDocumentType(url)
        }

        var sections: [ParsedSection] = []
        var fullTextParts: [String] = []
        var runningOffset = 0

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !pageText.isEmpty else { continue }

            let sectionTitle = "Page \(pageIndex + 1)"
            sections.append(ParsedSection(title: sectionTitle, content: pageText, offset: runningOffset))
            fullTextParts.append(pageText)
            runningOffset += pageText.count + 1
        }

        let fullText = fullTextParts.joined(separator: "\n")
        return ParsedDocument(
            source: url.path,
            title: url.deletingPathExtension().lastPathComponent,
            kind: .pdf,
            fullText: fullText,
            sections: sections
        )
    }
}

struct PlainTextDocumentParser: DocumentParser {
    func parse(url: URL) throws -> ParsedDocument {
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return ParsedDocument(
            source: url.path,
            title: url.lastPathComponent,
            kind: .plainText,
            fullText: text,
            sections: [ParsedSection(title: nil, content: text, offset: 0)]
        )
    }
}

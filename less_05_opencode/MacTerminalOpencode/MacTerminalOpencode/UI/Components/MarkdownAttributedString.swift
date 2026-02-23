//
//  MarkdownAttributedString.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Parses basic Markdown syntax into NSAttributedString
enum MarkdownAttributedString {
    
    private static let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let boldFont = NSFont.boldSystemFont(ofSize: 13)
    private static let regularFont = NSFont.systemFont(ofSize: 13)
    private static let italicFont: NSFont = {
        let descriptor = regularFont.fontDescriptor.withSymbolicTraits([.italic])
        return NSFont(descriptor: descriptor, size: 13) ?? regularFont
    }()
    
    /// Parses markdown text and returns an attributed string with basic formatting
    static func parse(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var currentIndex = text.startIndex
        
        while currentIndex < text.endIndex {
            if let codeBlock = parseCodeBlock(text, from: currentIndex) {
                result.append(codeBlock.attributedString)
                currentIndex = codeBlock.endIndex
            } else if let inlineCode = parseInlineCode(text, from: currentIndex) {
                result.append(inlineCode.attributedString)
                currentIndex = inlineCode.endIndex
            } else if let bold = parseBold(text, from: currentIndex) {
                result.append(bold.attributedString)
                currentIndex = bold.endIndex
            } else if let italic = parseItalic(text, from: currentIndex) {
                result.append(italic.attributedString)
                currentIndex = italic.endIndex
            } else {
                let char = text[currentIndex]
                result.append(NSAttributedString(
                    string: String(char),
                    attributes: [.font: regularFont, .foregroundColor: NSColor.labelColor]
                ))
                currentIndex = text.index(after: currentIndex)
            }
        }
        
        return result
    }
    
    private static func parseCodeBlock(_ text: String, from startIndex: String.Index) -> ParsedBlock? {
        guard startIndex < text.endIndex else { return nil }
        
        let threeBackticks = "```"
        let endRange = text.index(startIndex, offsetBy: 3, limitedBy: text.endIndex)
        
        guard let end = endRange, end <= text.endIndex else { return nil }
        
        let substring = text[startIndex..<end]
        guard substring == threeBackticks else { return nil }
        
        let codeStart = text.index(startIndex, offsetBy: 3)
        
        guard let closingIndex = findRange(of: threeBackticks, in: text, startingAt: codeStart) else {
            return nil
        }
        
        let codeText = String(text[codeStart..<closingIndex])
        let lines = codeText.components(separatedBy: "\n")
        let codeContent = lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : codeText
        
        let attributedString = NSAttributedString(
            string: codeContent,
            attributes: [
                .font: codeFont,
                .foregroundColor: NSColor.textColor,
                .backgroundColor: NSColor.textBackgroundColor.withAlphaComponent(0.5)
            ]
        )
        
        return ParsedBlock(attributedString: attributedString, endIndex: text.index(closingIndex, offsetBy: 3))
    }
    
    private static func parseInlineCode(_ text: String, from startIndex: String.Index) -> ParsedBlock? {
        guard startIndex < text.endIndex, text[startIndex] == "`" else { return nil }
        
        let endIndex = text.index(after: startIndex)
        guard endIndex < text.endIndex else { return nil }
        
        guard let closingIndex = findRange(of: "`", in: text, startingAt: endIndex) else { return nil }
        
        let codeText = String(text[endIndex..<closingIndex])
        
        let attributedString = NSAttributedString(
            string: codeText,
            attributes: [
                .font: codeFont,
                .foregroundColor: NSColor.systemRed,
                .backgroundColor: NSColor.controlBackgroundColor
            ]
        )
        
        return ParsedBlock(attributedString: attributedString, endIndex: text.index(after: closingIndex))
    }
    
    private static func parseBold(_ text: String, from startIndex: String.Index) -> ParsedBlock? {
        guard startIndex < text.endIndex else { return nil }
        
        let doubleAsterisk = "**"
        let endRange = text.index(startIndex, offsetBy: 2, limitedBy: text.endIndex)
        
        guard let end = endRange, end <= text.endIndex else { return nil }
        guard text[startIndex..<end] == doubleAsterisk else { return nil }
        
        let contentStart = end
        guard let closingIndex = findRange(of: doubleAsterisk, in: text, startingAt: contentStart) else {
            return nil
        }
        
        let contentText = String(text[contentStart..<closingIndex])
        
        let attributedString = NSAttributedString(
            string: contentText,
            attributes: [.font: boldFont, .foregroundColor: NSColor.labelColor]
        )
        
        return ParsedBlock(attributedString: attributedString, endIndex: text.index(closingIndex, offsetBy: 2))
    }
    
    private static func parseItalic(_ text: String, from startIndex: String.Index) -> ParsedBlock? {
        guard startIndex < text.endIndex, text[startIndex] == "*" else { return nil }
        
        let endIndex = text.index(after: startIndex)
        guard endIndex < text.endIndex, text[endIndex] != "*" else { return nil }
        
        guard let closingIndex = findRange(of: "*", in: text, startingAt: endIndex) else { return nil }
        
        let contentText = String(text[endIndex..<closingIndex])
        
        let attributedString = NSAttributedString(
            string: contentText,
            attributes: [.font: italicFont, .foregroundColor: NSColor.labelColor]
        )
        
        return ParsedBlock(attributedString: attributedString, endIndex: text.index(after: closingIndex))
    }
    
    private static func findRange(of substring: String, in text: String, startingAt index: String.Index) -> String.Index? {
        let searchRange = index..<text.endIndex
        if let range = text.range(of: substring, options: [], range: searchRange) {
            return range.lowerBound
        }
        return nil
    }
}

private struct ParsedBlock {
    let attributedString: NSAttributedString
    let endIndex: String.Index
}

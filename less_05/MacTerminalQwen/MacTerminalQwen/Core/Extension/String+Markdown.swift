//
//  String+Markdown.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Extension для базового форматирования текста (псевдо-Markdown).
/// Использует NSAttributedString для стилизации без внешних зависимостей.
extension String {
    
    /// Преобразовать базовый Markdown в NSAttributedString
    /// Поддерживает: **bold**, *italic*, `code`, ```code blocks```, заголовки #
    func toAttributedString(baseFont: NSFont = .systemFont(ofSize: 13)) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: self)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.textColor
        ]
        attributedString.addAttributes(baseAttributes, range: NSRange(location: 0, length: attributedString.length))
        
        // Жирный текст: **text**
        applyBoldStyle(to: attributedString, baseFont: baseFont)
        
        // Курсив: *text*
        applyItalicStyle(to: attributedString, baseFont: baseFont)
        
        // Inline code: `code`
        applyCodeStyle(to: attributedString, baseFont: baseFont)
        
        // Заголовки: # Text
        applyHeadingStyle(to: attributedString, baseFont: baseFont)
        
        return attributedString
    }
    
    // MARK: - Private Styling Methods
    
    private func applyBoldStyle(to attributedString: NSMutableAttributedString, baseFont: NSFont) {
        let pattern = "\\*\\*(.+?)\\*\\*"
        applyRegex(pattern: pattern, to: attributedString) { match, range in
            let font = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            return [NSAttributedString.Key.font: font]
        }
    }
    
    private func applyItalicStyle(to attributedString: NSMutableAttributedString, baseFont: NSFont) {
        let pattern = "\\*(?!\\*)(.+?)\\*(?!\\*)"
        applyRegex(pattern: pattern, to: attributedString) { match, range in
            let font = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            return [NSAttributedString.Key.font: font]
        }
    }
    
    private func applyCodeStyle(to attributedString: NSMutableAttributedString, baseFont: NSFont) {
        let pattern = "``(.+?)``"
        applyRegex(pattern: pattern, to: attributedString) { match, range in
            let codeFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular)
            return [
                .font: codeFont,
                .backgroundColor: NSColor.textBackgroundColor.blended(withFraction: 0.3, of: NSColor.textColor) ?? NSColor.gray.withAlphaComponent(0.1),
                .foregroundColor: NSColor.labelColor
            ]
        }
    }
    
    private func applyHeadingStyle(to attributedString: NSMutableAttributedString, baseFont: NSFont) {
        let pattern = "^(#+)\\s+(.+)$"
        applyRegex(pattern: pattern, to: attributedString, options: .anchorsMatchLines) { match, range in
            guard let hashRange = Range(match.range(at: 1), in: self) else { return [:] }
            let hashes = self[hashRange].count
            
            let sizeMultiplier: CGFloat
            switch hashes {
            case 1: sizeMultiplier = 1.4
            case 2: sizeMultiplier = 1.2
            case 3: sizeMultiplier = 1.1
            default: sizeMultiplier = 1.0
            }
            
            let font = NSFont.systemFont(ofSize: baseFont.pointSize * sizeMultiplier, weight: .bold)
            return [
                .font: font,
                .paragraphStyle: paragraphStyleWithSpacing(sizeMultiplier * 2)
            ]
        }
    }
    
    private func applyRegex(
        pattern: String,
        to attributedString: NSMutableAttributedString,
        options: NSRegularExpression.Options = [],
        apply: (NSTextCheckingResult, NSRange) -> [NSAttributedString.Key: Any]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        
        let matches = regex.matches(in: attributedString.string, options: [], range: NSRange(location: 0, length: attributedString.length))
        
        // Идём с конца, чтобы ranges не смещались
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            let contentRange = match.range(at: 1)
            
            // Удаляем маркеры (**, *, ``)
            let fullRange = match.range
            let fullText = (attributedString.string as NSString).substring(with: fullRange)
            let contentText = (attributedString.string as NSString).substring(with: contentRange)
            
            // Заменяем текст, убирая маркеры
            attributedString.replaceCharacters(in: fullRange, with: contentText)
            
            // Применяем атрибуты
            let attributes = apply(match, contentRange)
            attributedString.addAttributes(attributes, range: contentRange)
        }
    }
    
    private func paragraphStyleWithSpacing(_ spacing: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = spacing
        style.paragraphSpacingBefore = spacing
        return style
    }
}

// MARK: - Code Block Support

extension String {
    
    /// Найти и выделить блоки кода ``` ... ```
    func extractCodeBlocks() -> (text: String, blocks: [String]) {
        var blocks: [String] = []
        var result = self
        
        let pattern = "```(?:\\w+)?\\n(.+?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return (self, [])
        }
        
        let matches = regex.matches(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count))
        
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 1), in: self) else { continue }
            let codeBlock = String(self[range]).trimmingCharacters(in: .newlines)
            blocks.insert(codeBlock, at: 0)
            
            // Заменяем блок кода на плейсхолдер
            let fullRange = Range(match.range, in: self)!
            let placeholder = "\u{0000}CODE_BLOCK_\(blocks.count - 1)\u{0000}"
            result.replaceSubrange(fullRange, with: placeholder)
        }
        
        return (result, blocks)
    }
}

//
//  String+Chunks.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation

extension String {
    /// Разбить текст на чанки с заданным размером и перекрытием
    /// - Parameters:
    ///   - maxSize: Максимальный размер чанка в символах
    ///   - overlap: Перекрытие между чанками в символах
    /// - Returns: Массив чанков
    func chunked(by size: Int, overlap: Int = 0) -> [String] {
        guard size > 0 else { return [self] }
        guard count > size else { return [self] }
        
        var chunks: [String] = []
        var startIndex = self.startIndex
        
        while startIndex < endIndex {
            let chunkEndIndex = index(startIndex, offsetBy: size, limitedBy: endIndex) ?? endIndex
            
            // Если это не последний чанк и есть перекрытие
            if chunkEndIndex < endIndex && overlap > 0 {
                // Находим начало следующего чанка с учетом перекрытия
                let nextStartIndex = index(chunkEndIndex, offsetBy: -overlap, limitedBy: startIndex) ?? startIndex
                let chunk = String(self[startIndex..<chunkEndIndex])
                chunks.append(chunk)
                startIndex = nextStartIndex
            } else {
                // Последний чанк
                let chunk = String(self[startIndex..<endIndex])
                chunks.append(chunk)
                break
            }
        }
        
        return chunks
    }
    
    /// Разбить текст по заголовкам Markdown
    /// - Returns: Массив секций с заголовками
    func splitByHeadings() -> [(heading: String, content: String)] {
        let lines = components(separatedBy: .newlines)
        var sections: [(heading: String, content: String)] = []
        var currentHeading = ""
        var currentContent: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("#") {
                // Сохраняем предыдущую секцию
                if !currentContent.isEmpty || !currentHeading.isEmpty {
                    sections.append((currentHeading, currentContent.joined(separator: "\n")))
                }
                
                // Новый заголовок
                currentHeading = trimmed
                currentContent = [line]
            } else {
                currentContent.append(line)
            }
        }
        
        // Добавляем последнюю секцию
        if !currentContent.isEmpty || !currentHeading.isEmpty {
            sections.append((currentHeading, currentContent.joined(separator: "\n")))
        }
        
        return sections
    }
    
    /// Разбить текст на предложения
    var sentences: [String] {
        var sentences: [String] = []
        enumerateSubstrings(in: startIndex..<endIndex, options: .localized) { _, _, range, _ in
            sentences.append(String(self[range]))
        }
        return sentences
    }
    
    /// Разбить текст на чанки по предложениям с учетом размера
    /// - Parameters:
    ///   - maxSize: Максимальный размер чанка
    ///   - overlap: Перекрытие
    /// - Returns: Массив чанков
    func chunkedBySentences(maxSize: Int, overlap: Int = 0) -> [String] {
        let sentences = self.sentences
        var chunks: [String] = []
        var currentChunk: [String] = []
        var currentSize = 0
        
        for sentence in sentences {
            let sentenceSize = sentence.count
            
            if currentSize + sentenceSize > maxSize && !currentChunk.isEmpty {
                // Сохраняем текущий чанк
                chunks.append(currentChunk.joined(separator: " "))
                
                // Добавляем перекрытие
                if overlap > 0 && chunks.count > 1 {
                    let previousChunk = chunks[chunks.count - 2]
                    let overlapWords = previousChunk.split(separator: " ").suffix(overlap / 5)
                    currentChunk = Array(overlapWords.map { String($0) })
                    currentSize = currentChunk.reduce(0) { $0 + $1.count }
                } else {
                    currentChunk = []
                    currentSize = 0
                }
            }
            
            currentChunk.append(sentence)
            currentSize += sentenceSize
        }
        
        // Добавляем последний чанк
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: " "))
        }
        
        return chunks
    }
    
    /// Подсчитать количество слов
    var wordCount: Int {
        components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
    
    /// Извлечь заголовки из Markdown текста
    var headings: [String] {
        let lines = components(separatedBy: .newlines)
        return lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
    }
    
    /// Удалить Markdown форматирование
    var strippingMarkdown: String {
        var result = self
        
        // Удаляем заголовки
        result = result.replacingOccurrences(of: #"^#+\s+"#, with: "", options: .regularExpression)
        
        // Удаляем жирный и курсив
        result = result.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\*([^*]+)\*"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"__([^_]+)__"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"_([^_]+)_"#, with: "$1", options: .regularExpression)
        
        // Удаляем ссылки
        result = result.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        
        // Удаляем код
        result = result.replacingOccurrences(of: #"`[^`]+`"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"```[\s\S]*?```"#, with: "", options: .regularExpression)
        
        // Удаляем списки
        result = result.replacingOccurrences(of: #"^[\s]*[-*+]\s+"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"^[\s]*\d+\.\s+"#, with: "", options: .regularExpression)
        
        return result
    }
}

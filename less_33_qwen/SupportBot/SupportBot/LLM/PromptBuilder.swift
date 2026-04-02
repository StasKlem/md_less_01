//
//  PromptBuilder.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation

/// Строитель промптов для LLM
final class PromptBuilder {
    
    /// Системный промпт по умолчанию
    private let defaultSystemPrompt = """
    Ты — SupportBot, интеллектуальный ассистент поддержки.
    
    Твои задачи:
    1. Отвечай на вопросы пользователей на основе предоставленного контекста
    2. Если информации в контексте недостаточно, честно скажи об этом
    3. Будь вежливым и полезным
    4. Отвечай на том же языке, на котором задан вопрос
    5. Не выдумывай информацию — используй только предоставленный контекст
    6. Если вопрос не относится к продукту, мягко направь пользователя к теме поддержки
    """
    
    /// Разделитель секций
    private let sectionSeparator = "\n\n---\n\n"
    
    /// Построить промпт для генерации ответа
    /// - Parameters:
    ///   - query: Запрос пользователя
    ///   - context: Контекст из RAG (найденные фрагменты)
    ///   - history: История диалога
    ///   - systemPrompt: Кастомный системный промпт (опционально)
    /// - Returns: Готовый промпт для LLM
    func buildPrompt(
        query: String,
        context: [RAGContext],
        history: [Message],
        systemPrompt: String? = nil
    ) -> String {
        let system = systemPrompt ?? defaultSystemPrompt
        
        var prompt = ""
        
        // Системный промпт
        prompt += "### SYSTEM\n"
        prompt += system
        prompt += sectionSeparator
        
        // Контекст из RAG
        prompt += "### CONTEXT\n"
        if context.isEmpty {
            prompt += "Контекст не найден. Отвечай на основе общих знаний, но предупреждай пользователя, что информация может быть неточной.\n"
        } else {
            for (index, item) in context.enumerated() {
                prompt += "[Контекст \(index + 1)]\n"
                prompt += "Источник: \(item.source)\n"
                prompt += "Релевантность: \(String(format: "%.2f", item.score))\n"
                prompt += "Содержание:\n\(item.content)\n\n"
            }
        }
        prompt += sectionSeparator
        
        // История диалога
        if !history.isEmpty {
            prompt += "### HISTORY\n"
            for message in history {
                let sender = message.sender == .user ? "Пользователь" : "Ассистент"
                prompt += "\(sender): \(message.text)\n"
            }
            prompt += sectionSeparator
        }
        
        // Запрос пользователя
        prompt += "### USER QUERY\n"
        prompt += query
        
        return prompt
    }
    
    /// Построить промпт только с контекстом (без истории)
    func buildSimplePrompt(
        query: String,
        context: [RAGContext],
        systemPrompt: String? = nil
    ) -> String {
        buildPrompt(query: query, context: context, history: [], systemPrompt: systemPrompt)
    }
    
    /// Построить промпт для классификации запроса
    func buildClassificationPrompt(query: String) -> String {
        return """
        Классифицируй запрос пользователя по категориям:
        - general: общий вопрос о продукте
        - technical: техническая проблема
        - billing: вопросы оплаты и тарифов
        - feature: вопрос о функциях
        - other: другое
        
        Верни только название категории.
        
        Запрос: \(query)
        
        Категория:
        """
    }
    
    /// Построить промпт для извлечения ключевых слов
    func buildKeywordExtractionPrompt(query: String) -> String {
        return """
        Извлеки 3-5 ключевых слов или фраз из запроса пользователя.
        Верни только ключевые слова через запятую.
        
        Запрос: \(query)
        
        Ключевые слова:
        """
    }
}

/// Элемент контекста для RAG
struct RAGContext {
    let content: String
    let source: String
    let score: Double
    
    init(content: String, source: String, score: Double) {
        self.content = content
        self.source = source
        self.score = score
    }
}

//
//  PromptBuilder.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation

/// Строитель промптов для LLM
final class PromptBuilder {

    /// Системный промпт по умолчанию (RAG режим)
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

    /// Системный промпт для работы с файлами
    private let fileAssistantSystemPrompt = """
    Ты — AI-ассистент для работы с файлами проекта SupportBot.

    Твои возможности:
    1. 📖 Чтение файлов — просмотр содержимого файлов проекта
    2. 🔍 Поиск — поиск по содержимому и именам файлов
    3. 📝 Создание файлов — создание новых файлов с содержимым
    4. ✏️  Изменение файлов — редактирование существующих файлов
    5. 📊 Diff — просмотр изменений между версиями
    6. 🔬 Анализ — анализ структуры проекта, статистика
    7. ✅ Инварианты — проверка соответствия правилам проекта

    Правила:
    - Анализируй код и давай точные, конкретные ответы
    - При поиске указывай файлы и номера строк
    - При создании файлов предлагай осмысленное содержимое
    - При анализе проекта давай конкретные рекомендации
    - Отвечай на русском языке
    - Используй форматирование Markdown для кода
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

    /// Построить промпт для файлового ассистента
    func buildFileAssistantPrompt(query: String, fileContext: String? = nil) -> String {
        var prompt = ""

        // Системный промпт
        prompt += "### SYSTEM\n"
        prompt += fileAssistantSystemPrompt
        prompt += sectionSeparator

        // Контекст файла (если есть)
        if let context = fileContext, !context.isEmpty {
            prompt += "### FILE CONTEXT\n"
            prompt += context
            prompt += sectionSeparator
        }

        // Запрос пользователя
        prompt += "### USER QUERY\n"
        prompt += query

        return prompt
    }

    /// Построить промпт для анализа кода
    func buildCodeAnalysisPrompt(code: String, query: String) -> String {
        return """
        ### SYSTEM
        Ты — эксперт по анализу кода на Swift. Проанализируй код и ответь на вопрос.

        \(sectionSeparator)

        ### CODE
        ```swift
        \(code)
        ```

        \(sectionSeparator)

        ### QUESTION
        \(query)
        """
    }

    /// Построить промпт для генерации содержимого файла
    func buildFileContentPrompt(fileType: String, description: String) -> String {
        return """
        ### SYSTEM
        Ты — эксперт по созданию файлов. Создай содержимое файла на основе описания.

        \(sectionSeparator)

        ### FILE TYPE
        \(fileType)

        \(sectionSeparator)

        ### DESCRIPTION
        \(description)

        \(sectionSeparator)

        Сгенерируй содержимое файла. Верни только содержимое, без дополнительных объяснений.
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

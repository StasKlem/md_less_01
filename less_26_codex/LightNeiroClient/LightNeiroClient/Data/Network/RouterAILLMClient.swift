import Foundation

protocol HTTPClientProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClientProtocol {}

struct RouterAIConfiguration {
    let endpoint: URL
    let timeoutInterval: TimeInterval
    let apiKeyProvider: @Sendable () -> String?

    static let `default` = RouterAIConfiguration(
        endpoint: URL(string: "https://routerai.ru/api/v1/chat/completions")!,
        timeoutInterval: 120,
        apiKeyProvider: { ProcessInfo.processInfo.environment["ROUTERAI_API_KEY"] }
    )
}

enum RouterAILLMClientError: LocalizedError {
    case missingAPIKey
    case invalidHTTPResponse
    case api(statusCode: Int, message: String)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing ROUTERAI_API_KEY environment variable."
        case .invalidHTTPResponse:
            return "Invalid HTTP response."
        case let .api(statusCode, message):
            return "RouterAI API error (\(statusCode)): \(message)"
        case .invalidPayload:
            return "RouterAI response does not contain assistant message."
        }
    }
}

final class RouterAILLMClient: LLMClientProtocol {
    private let httpClient: HTTPClientProtocol
    private let configuration: RouterAIConfiguration
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        httpClient: HTTPClientProtocol = URLSession.shared,
        configuration: RouterAIConfiguration = .default
    ) {
        self.httpClient = httpClient
        self.configuration = configuration
    }

    func send(request: LLMRequest) async throws -> LLMResponse {
        guard let apiKey = configuration.apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw RouterAILLMClientError.missingAPIKey
        }

        let startedAt = Date()
        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let apiMessages = toAPIMessages(from: request)
        let payload = RouterAIChatCompletionRequest(
            model: request.settings.model.rawValue,
            messages: apiMessages
        )
        urlRequest.httpBody = try encoder.encode(payload)

        let (data, response) = try await httpClient.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RouterAILLMClientError.invalidHTTPResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseAPIErrorMessage(from: data)
            throw RouterAILLMClientError.api(statusCode: httpResponse.statusCode, message: message)
        }

        let apiResponse = try decoder.decode(RouterAIChatCompletionResponse.self, from: data)
        guard let content = apiResponse.firstContent, !content.isEmpty else {
            throw RouterAILLMClientError.invalidPayload
        }

        let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000.0)
        let inputTokens = apiResponse.usage?.promptTokens ?? estimatedTokens(in: apiMessages.map(\.content).joined(separator: " "))
        let outputTokens = apiResponse.usage?.completionTokens ?? estimatedTokens(in: content)

        return LLMResponse(
            content: content,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            latencyMs: latencyMs
        )
    }

    private func toAPIMessages(from request: LLMRequest) -> [RouterAIMessagePayload] {
        var messages: [RouterAIMessagePayload] = []

        let systemPrompt = request.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !systemPrompt.isEmpty {
            messages.append(.init(role: .system, content: systemPrompt))
        }

        if let taskState = request.taskState, !taskState.isEmpty {
            messages.append(.init(role: .system, content: formatTaskStateBlock(taskState)))
        }

        if !request.workingMemory.isEmpty {
            let workingBlock = request.workingMemory
                .map { "\($0.key): \($0.value)" }
                .joined(separator: "\n")
            messages.append(.init(role: .system, content: "WORKING_MEMORY:\n\(workingBlock)"))
        }

        if !request.longTermMemory.isEmpty {
            let longTermBlock = request.longTermMemory
                .map { "[\($0.namespace.rawValue)] \($0.key): \($0.value)" }
                .joined(separator: "\n")
            messages.append(.init(role: .system, content: "LONG_TERM_MEMORY:\n\(longTermBlock)"))
        }

        messages.append(.init(role: .system, content: "RECENT_DIALOG:"))
        messages.append(contentsOf: request.shortTermMessages.map {
            RouterAIMessagePayload(role: .init(domainRole: $0.role), content: $0.content)
        })

        return messages
    }

    private func formatTaskStateBlock(_ taskState: TaskStateMemory) -> String {
        var lines: [String] = ["TASK_STATE:"]

        if let goal = taskState.goal, !goal.isEmpty {
            lines.append("goal: \(goal)")
        }

        if !taskState.clarifiedFacts.isEmpty {
            lines.append("clarified:")
            lines.append(contentsOf: taskState.clarifiedFacts.map { "- \($0)" })
        }

        if !taskState.constraints.isEmpty {
            lines.append("constraints:")
            lines.append(contentsOf: taskState.constraints.map { "- \($0)" })
        }

        if !taskState.terms.isEmpty {
            lines.append("terms:")
            lines.append(contentsOf: taskState.terms.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private func parseAPIErrorMessage(from data: Data) -> String {
        guard let envelope = try? decoder.decode(RouterAIAPIErrorEnvelope.self, from: data) else {
            return String(data: data, encoding: .utf8) ?? "Unknown API error"
        }

        if let nested = envelope.error?.message, !nested.isEmpty {
            return nested
        }
        if let message = envelope.message, !message.isEmpty {
            return message
        }
        return "Unknown API error"
    }

    private func estimatedTokens(in text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }
}

private struct RouterAIChatCompletionRequest: Encodable {
    let model: String
    let messages: [RouterAIMessagePayload]
}

private struct RouterAIMessagePayload: Encodable {
    enum Role: String, Encodable {
        case system
        case user
        case assistant

        init(domainRole: MessageRole) {
            switch domainRole {
            case .system:
                self = .system
            case .user:
                self = .user
            case .assistant:
                self = .assistant
            }
        }
    }

    let role: Role
    let content: String
}

private struct RouterAIChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String

            private enum CodingKeys: String, CodingKey {
                case content
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let text = try? container.decode(String.self, forKey: .content) {
                    content = text
                    return
                }

                let parts = try container.decode([MessagePart].self, forKey: .content)
                content = parts
                    .map(\.text)
                    .joined()
            }
        }

        let message: Message
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }

    let choices: [Choice]
    let usage: Usage?

    var firstContent: String? {
        choices.first?.message.content
    }
}

private struct MessagePart: Decodable {
    let text: String
}

private struct RouterAIAPIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError?
    let message: String?
}

final class LLMAnswerExtractionService: AnswerExtractionServiceProtocol {
    private let llmClient: LLMClientProtocol
    private let decoder = JSONDecoder()

    init(llmClient: LLMClientProtocol) {
        self.llmClient = llmClient
    }

    func extractFields(
        userText: String,
        schema: QuestionnaireSchema,
        currentState: QuestionnaireState,
        settings: LLMSettings
    ) async throws -> QuestionnaireExtractionResult {
        let request = LLMRequest(
            systemPrompt: extractionSystemPrompt(schema: schema, state: currentState, settings: settings),
            shortTermMessages: [ChatMessage(role: .user, content: userText)],
            workingMemory: [],
            longTermMemory: [],
            settings: settings
        )

        let response: LLMResponse
        do {
            response = try await llmClient.send(request: request)
        } catch {
            return QuestionnaireExtractionResult(
                fields: [],
                warnings: [
                    QuestionnaireExtractionWarning(
                        code: .llmError,
                        fieldID: nil,
                        message: "LLM extraction недоступен: \(error.localizedDescription)"
                    ),
                ]
            )
        }

        guard let rawJSON = extractJSONObject(from: response.content),
              let data = rawJSON.data(using: .utf8) else {
            return QuestionnaireExtractionResult(
                fields: [],
                warnings: [
                    QuestionnaireExtractionWarning(
                        code: .invalidJSON,
                        fieldID: nil,
                        message: "LLM вернул невалидный JSON для extraction."
                    ),
                ]
            )
        }

        let payload: LLMExtractionPayload
        do {
            payload = try decoder.decode(LLMExtractionPayload.self, from: data)
        } catch {
            return QuestionnaireExtractionResult(
                fields: [],
                warnings: [
                    QuestionnaireExtractionWarning(
                        code: .invalidJSON,
                        fieldID: nil,
                        message: "Не удалось декодировать JSON extraction: \(error.localizedDescription)"
                    ),
                ]
            )
        }

        var fields: [QuestionnaireFieldExtraction] = []
        var warnings = payload.warnings.map {
            QuestionnaireExtractionWarning(
                code: QuestionnaireWarningCode(rawValue: $0.code) ?? .llmError,
                fieldID: $0.fieldID,
                message: $0.message
            )
        }

        for item in payload.fields {
            guard let definition = schema.field(id: item.fieldID) else {
                warnings.append(
                    QuestionnaireExtractionWarning(
                        code: .invalidType,
                        fieldID: item.fieldID,
                        message: "LLM вернул неизвестное поле \(item.fieldID)."
                    )
                )
                continue
            }
            guard let value = mapToValue(item: item, expectedType: definition.type) else {
                warnings.append(
                    QuestionnaireExtractionWarning(
                        code: .invalidType,
                        fieldID: item.fieldID,
                        message: "LLM вернул неверный тип значения для поля \(item.fieldID)."
                    )
                )
                continue
            }
            fields.append(
                QuestionnaireFieldExtraction(
                    fieldID: item.fieldID,
                    value: value,
                    confidence: min(max(item.confidence, 0.0), 1.0),
                    rationale: item.rationale
                )
            )
        }

        return QuestionnaireExtractionResult(fields: fields, warnings: warnings)
    }

    private func mapToValue(item: LLMExtractionField, expectedType: QuestionnaireFieldType) -> QuestionnaireValue? {
        switch expectedType {
        case .text:
            guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return .text(text)
        case .dateRange:
            guard
                let startRaw = item.startDate,
                let endRaw = item.endDate,
                let start = Self.date(fromISODate: startRaw),
                let end = Self.date(fromISODate: endRaw)
            else { return nil }
            return .dateRange(VacationDateRange(start: start, end: end))
        case .money:
            guard let amount = item.amount, amount > 0 else { return nil }
            let currency = (item.currency ?? "USD").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !currency.isEmpty else { return nil }
            return .money(VacationBudgetInput(total: amount, currency: currency))
        case .integer:
            guard let number = item.integer else { return nil }
            return .integer(number)
        case .stringList:
            guard let values = item.values?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }),
                  !values.isEmpty else { return nil }
            return .stringList(values)
        }
    }

    private func extractionSystemPrompt(
        schema: QuestionnaireSchema,
        state: QuestionnaireState,
        settings: LLMSettings
    ) -> String {
        let schemaLines = schema.fields.map { field in
            "- \(field.id) [\(field.type.rawValue)] required=\(field.requiredLevel.rawValue)"
        }.joined(separator: "\n")
        let unresolved = (state.missingHard + state.missingSoft).joined(separator: ", ")
        let invariants = settings.plannerInvariants.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return """
        Ты extraction-модуль. Извлеки данные поездки из свободного текста пользователя.
        Верни СТРОГО JSON без markdown и комментариев.

        Schema fields:
        \(schemaLines)

        Missing now: \(unresolved)

        Planner invariants:
        \(invariants)

        Output format:
        {
          "fields": [
            {
              "field_id": "destination|dates|budget|travel_style|interests|constraints",
              "confidence": 0.0,
              "rationale": "short reason",
              "text": "...",
              "start_date": "YYYY-MM-DD",
              "end_date": "YYYY-MM-DD",
              "amount": 0,
              "currency": "USD",
              "integer": 1,
              "values": ["..."]
            }
          ],
          "warnings": [
            {
              "code": "ambiguous|not_extracted|invalid_type|out_of_range",
              "field_id": "optional",
              "message": "..."
            }
          ]
        }
        Если поле не найдено — не выдумывай. Если двусмысленно — добавь warning code=\"ambiguous\".
        """
    }

    private func extractJSONObject(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{", trimmed.last == "}" {
            return trimmed
        }
        if let fencedStart = trimmed.range(of: "```json"),
           let fencedEnd = trimmed.range(of: "```", range: fencedStart.upperBound..<trimmed.endIndex) {
            return String(trimmed[fencedStart.upperBound..<fencedEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") else { return nil }
        return String(trimmed[start...end])
    }

    private static func date(fromISODate value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

final class LLMQuestionGenerationService: QuestionGenerationServiceProtocol {
    private let llmClient: LLMClientProtocol
    private let decoder = JSONDecoder()

    init(llmClient: LLMClientProtocol) {
        self.llmClient = llmClient
    }

    func generateQuestion(
        context: QuestionnaireQuestionContext,
        targetField: QuestionnaireFieldDefinition?,
        toneHints _: [String]
    ) async throws -> QuestionPrompt {
        guard let targetField else {
            return QuestionPrompt(
                fieldID: nil,
                text: "Опишите поездку в свободной форме: куда, когда и какой бюджет.",
                suggestions: [
                    "Например: Хочу в Японию в августе на 10 дней, бюджет около 3000 долларов.",
                    "Альтернатива: destination: Japan; dates: 2026-08-10 to 2026-08-20; budget: 3000 USD",
                ],
                isFallback: true
            )
        }

        let response: LLMResponse
        do {
            response = try await llmClient.send(
                request: LLMRequest(
                    systemPrompt: questionSystemPrompt(field: targetField, context: context),
                    shortTermMessages: [ChatMessage(role: .user, content: context.latestUserMessage ?? "")],
                    workingMemory: [],
                    longTermMemory: [],
                    settings: context.settings
                )
            )
        } catch {
            return fallbackPrompt(for: targetField)
        }

        guard let json = extractJSONObject(from: response.content),
              let data = json.data(using: .utf8),
              let payload = try? decoder.decode(LLMQuestionPayload.self, from: data) else {
            return fallbackPrompt(for: targetField)
        }

        let suggestions = [payload.naturalExample, payload.technicalExample]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return QuestionPrompt(
            fieldID: targetField.id,
            text: payload.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? targetField.fallbackQuestion : payload.question,
            suggestions: suggestions.isEmpty ? fallbackPrompt(for: targetField).suggestions : suggestions,
            isFallback: false
        )
    }

    private func fallbackPrompt(for field: QuestionnaireFieldDefinition) -> QuestionPrompt {
        QuestionPrompt(
            fieldID: field.id,
            text: field.fallbackQuestion,
            suggestions: [naturalExample(for: field.id), technicalExample(for: field.id)],
            isFallback: true
        )
    }

    private func questionSystemPrompt(field: QuestionnaireFieldDefinition, context: QuestionnaireQuestionContext) -> String {
        let unresolved = (context.state.missingHard + context.state.missingSoft).joined(separator: ", ")
        let invariants = context.settings.plannerInvariants.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return """
        Ты формируешь короткий вопрос пользователю на русском.
        Нужное поле: \(field.id). Подсказка: \(field.promptHint)
        Пропущенные поля: \(unresolved)
        Учитывай инварианты планировщика:
        \(invariants)
        Верни строго JSON:
        {"question":"...","natural_example":"...","technical_example":"..."}
        natural_example — свободная фраза пользователя.
        technical_example — формат ключ: значение.
        """
    }

    private func naturalExample(for fieldID: String) -> String {
        switch fieldID {
        case VacationQuestionnaireSchemaAdapter.destinationFieldID:
            return "Например: Хочу в Италию, либо просто спокойный пляжный отдых."
        case VacationQuestionnaireSchemaAdapter.datesFieldID:
            return "Например: Планирую с 10 по 20 августа 2026."
        case VacationQuestionnaireSchemaAdapter.budgetFieldID:
            return "Например: Бюджет примерно 2500 евро."
        case VacationQuestionnaireSchemaAdapter.styleFieldID:
            return "Например: Нравится экскурсионный и активный отдых."
        case VacationQuestionnaireSchemaAdapter.interestsFieldID:
            return "Например: Интересуют музеи, кухня и природа."
        case VacationQuestionnaireSchemaAdapter.constraintsFieldID:
            return "Например: Без ночных перелетов и длительных пересадок."
        default:
            return "Например: Опишу детали поездки обычным текстом."
        }
    }

    private func technicalExample(for fieldID: String) -> String {
        switch fieldID {
        case VacationQuestionnaireSchemaAdapter.destinationFieldID:
            return "Альтернатива: destination: Italy"
        case VacationQuestionnaireSchemaAdapter.datesFieldID:
            return "Альтернатива: dates: 2026-08-10 to 2026-08-20"
        case VacationQuestionnaireSchemaAdapter.budgetFieldID:
            return "Альтернатива: budget: 2500 EUR"
        case VacationQuestionnaireSchemaAdapter.styleFieldID:
            return "Альтернатива: style: active sightseeing"
        case VacationQuestionnaireSchemaAdapter.interestsFieldID:
            return "Альтернатива: interests: food, museums, nature"
        case VacationQuestionnaireSchemaAdapter.constraintsFieldID:
            return "Альтернатива: constraints: no night flights, short transfers"
        default:
            return "Альтернатива: destination: Italy; dates: 2026-08-10 to 2026-08-20; budget: 2500 EUR"
        }
    }

    private func extractJSONObject(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{", trimmed.last == "}" {
            return trimmed
        }
        if let fencedStart = trimmed.range(of: "```json"),
           let fencedEnd = trimmed.range(of: "```", range: fencedStart.upperBound..<trimmed.endIndex) {
            return String(trimmed[fencedStart.upperBound..<fencedEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") else { return nil }
        return String(trimmed[start...end])
    }
}

private struct LLMExtractionPayload: Decodable {
    let fields: [LLMExtractionField]
    let warnings: [LLMExtractionWarning]
}

private struct LLMExtractionField: Decodable {
    let fieldID: String
    let confidence: Double
    let rationale: String?
    let text: String?
    let startDate: String?
    let endDate: String?
    let amount: Double?
    let currency: String?
    let integer: Int?
    let values: [String]?

    private enum CodingKeys: String, CodingKey {
        case fieldID = "field_id"
        case confidence
        case rationale
        case text
        case startDate = "start_date"
        case endDate = "end_date"
        case amount
        case currency
        case integer
        case values
    }
}

private struct LLMExtractionWarning: Decodable {
    let code: String
    let fieldID: String?
    let message: String

    private enum CodingKeys: String, CodingKey {
        case code
        case fieldID = "field_id"
        case message
    }
}

private struct LLMQuestionPayload: Decodable {
    let question: String
    let naturalExample: String
    let technicalExample: String

    private enum CodingKeys: String, CodingKey {
        case question
        case naturalExample = "natural_example"
        case technicalExample = "technical_example"
    }
}

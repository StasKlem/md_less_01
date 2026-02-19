import Foundation

// MARK: - Network Manager

final class NetworkManager {

    // MARK: - Singleton

    static let shared = NetworkManager()

    // MARK: - Properties

    private var apiURL: String = ""
    private var apiKey: String = ""
    private var currentTask: URLSessionDataTask?

    // MARK: - Initialization

    private init() {}

    // MARK: - Configuration

    func configure(apiURL: String, apiKey: String) {
        self.apiURL = apiURL
        self.apiKey = apiKey
        Logger.shared.log("NetworkManager настроен: URL=\(apiURL), API Key=\(maskApiKey(apiKey))", type: .info)
    }

    private func maskApiKey(_ key: String) -> String {
        guard key.count > 8 else { return "****" }
        return "\(key.prefix(4))....\(key.suffix(4))"
    }
    
    // MARK: - Create Session
    
    private func createSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
//        configuration.protocolClasses = [LoggingURLProtocol.self]
        return URLSession(configuration: configuration)
    }
    
    // MARK: - Send Message

    func sendMessage(
        messages: [Message],
        settings: ChatSettings,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        // Cancel any existing streaming task
        cancelStreaming()

        guard !apiKey.isEmpty else {
            Logger.shared.log("Ошибка: API ключ не установлен", type: .error)
            onComplete(.failure(NetworkError.unauthorized))
            return
        }

        let request = ChatRequest(settings: settings, messages: messages)

        guard let url = URL(string: apiURL) else {
            Logger.shared.log("Ошибка: Неверный URL API: \(apiURL)", type: .error)
            onComplete(.failure(NetworkError.invalidURL))
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let encoder = JSONEncoder()
            let httpBody = try encoder.encode(request)
            urlRequest.httpBody = httpBody
            
            // Логируем запрос
//            logRequest(urlRequest)
        } catch {
            Logger.shared.log("Ошибка кодирования запроса: \(error.localizedDescription)", type: .error)
            onComplete(.failure(error))
            return
        }

        let session = createSession()

        if settings.stream {
            Logger.shared.log("Запуск стриминга", type: .stream)
            startStreamingSession(request: urlRequest, session: session, onToken: onToken, onComplete: onComplete)
        } else {
            Logger.shared.log("Запуск не-streaming запроса", type: .info)
            startNonStreamingSession(request: urlRequest, session: session, onComplete: onComplete)
        }
    }
    
    // MARK: - Request Logging
    
    private func logRequest(_ request: URLRequest) {
        var logMessage = """
        
        ╔═══════════════════════════════════════════════════════════
        ║ 📤 HTTP REQUEST
        ╚═══════════════════════════════════════════════════════════
        Method: \(request.httpMethod ?? "GET")
        URL: \(request.url?.absoluteString ?? "unknown")
        
        """
        
        // Headers (скрываем Authorization)
        if let headers = request.allHTTPHeaderFields {
            logMessage += "Headers:\n"
            for (key, value) in headers {
                if key.lowercased() == "authorization" {
                    logMessage += "  \(key): Bearer ****\n"
                } else {
                    logMessage += "  \(key): \(value)\n"
                }
            }
            logMessage += "\n"
        }
        
        // Body
        if let httpBody = request.httpBody,
           let jsonString = String(data: httpBody, encoding: .utf8) {
            logMessage += "Body:\n\(formatJSON(jsonString))\n"
        } else {
            logMessage += "Body: Пустрой !!!!\n"
        }
            
        
        logMessage += "═══════════════════════════════════════════════════════════\n"
        
        Logger.shared.log(logMessage, type: .request)
    }
    
    private func formatJSON(_ jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return jsonString
        }
        return prettyString
    }
    
    // MARK: - Streaming Session
    
    private func startStreamingSession(
        request: URLRequest,
        session: URLSession,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        let delegate = StreamingDelegate(onToken: onToken, onComplete: onComplete)
        
        let streamingSession = URLSession(configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        let task = streamingSession.dataTask(with: request)
        currentTask = task
        task.resume()
    }
    
    // MARK: - Non-Streaming Session

    private func startNonStreamingSession(
        request: URLRequest,
        session: URLSession,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        let startTime = Date()
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            let duration = Date().timeIntervalSince(startTime)
            
            if let error = error {
                Logger.shared.log("Ошибка запроса: \(error.localizedDescription)", type: .error)
                onComplete(.failure(error))
                return
            }

            guard let data = data else {
                Logger.shared.log("Ошибка: Нет данных в ответе", type: .error)
                onComplete(.failure(NetworkError.noData))
                return
            }

            Logger.shared.log("Получен ответ за \(String(format: "%.2f", duration))с, размер: \(self?.formatBytes(data.count) ?? "0 B")", type: .response)

            do {
                let decoder = JSONDecoder()
                let chatResponse = try decoder.decode(ChatResponse.self, from: data)
                
                // Логируем ответ
                if let jsonData = try? JSONSerialization.jsonObject(with: data),
                   let prettyData = try? JSONSerialization.data(withJSONObject: jsonData, options: .prettyPrinted),
                   let jsonString = String(data: prettyData, encoding: .utf8) {
                    Logger.shared.log("Тело ответа:\n\(jsonString)", type: .response)
                }

                if let content = chatResponse.content {
                    Logger.shared.log("Ответ получен успешно, длина: \(content.count) символов", type: .response)
                    onComplete(.success(content))
                } else {
                    Logger.shared.log("Ошибка: Пустой контент в ответе", type: .error)
                    onComplete(.failure(NetworkError.invalidResponse))
                }
            } catch {
                Logger.shared.log("Ошибка декодирования ответа: \(error.localizedDescription)", type: .error)
                onComplete(.failure(error))
            }
        }

        currentTask = task
        task.resume()
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // MARK: - Cancel Streaming
    
    func cancelStreaming() {
        Logger.shared.log("Отмена стриминга", type: .stream)
        currentTask?.cancel()
        currentTask = nil
    }
}

// MARK: - Streaming Delegate

private class StreamingDelegate: NSObject, URLSessionDataDelegate {
    let onToken: (String) -> Void
    let onComplete: (Result<String, Error>) -> Void
    
    private var accumulatedContent = ""
    private var tokenCount = 0
    private var startTime: Date?
    private var totalBytesReceived = 0
    
    init(onToken: @escaping (String) -> Void, onComplete: @escaping (Result<String, Error>) -> Void) {
        self.onToken = onToken
        self.onComplete = onComplete
        super.init()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        startTime = Date()
        totalBytesReceived = 0
        Logger.shared.log("Streaming: начало получения данных", type: .stream)
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        totalBytesReceived += data.count
        let responseString = String(decoding: data, as: UTF8.self)
        
        let lines = responseString.components(separatedBy: "\n")
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.hasPrefix("data: ") {
                let jsonData = trimmedLine.dropFirst(6).data(using: .utf8)
                
                if let jsonData = jsonData {
                    do {
                        let decoder = JSONDecoder()
                        let chatResponse = try decoder.decode(ChatResponse.self, from: jsonData)
                        
                        if let content = chatResponse.content, !content.isEmpty {
                            accumulatedContent += content
                            tokenCount += 1
                            onToken(content)
                        }
                        
                        if let finishReason = chatResponse.choices?.first?.finish_reason,
                           finishReason == "stop" || finishReason == "length" {
                            let duration = Date().timeIntervalSince(startTime ?? Date())
                            Logger.shared.log("Streaming: завершено (finish_reason: \(finishReason)), токенов: \(tokenCount), время: \(String(format: "%.2f", duration))с", type: .stream)
                            onComplete(.success(accumulatedContent))
                        }
                    } catch {
                        // Ignore parsing errors for incomplete chunks
                    }
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            if (error as NSError).code == NSURLErrorCancelled {
                Logger.shared.log("Streaming: отменено пользователем", type: .stream)
                return
            }
            Logger.shared.log("Streaming: ошибка: \(error.localizedDescription)", type: .error)
            onComplete(.failure(error))
        } else if !accumulatedContent.isEmpty {
            let duration = Date().timeIntervalSince(startTime ?? Date())
            Logger.shared.log("Streaming: готово, токенов: \(tokenCount), байт: \(totalBytesReceived), время: \(String(format: "%.2f", duration))с", type: .stream)
            onComplete(.success(accumulatedContent))
        }
    }
}

// MARK: - Network Error

enum NetworkError: LocalizedError {
    case unauthorized
    case invalidURL
    case noData
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "API ключ не установлен"
        case .invalidURL:
            return "Неверный URL API"
        case .noData:
            return "Нет данных в ответе"
        case .invalidResponse:
            return "Неверный формат ответа"
        }
    }
}

import Foundation

// MARK: - LLM Service Protocol

protocol LLMServiceProtocol {
    func sendMessage(messages: [Message], settings: ChatSettings, onToken: @escaping (String) -> Void, onComplete: @escaping (Result<String, Error>) -> Void)
    func cancelStreaming()
}

// MARK: - LLM Service Implementation

final class LLMService: LLMServiceProtocol {
    
    private var apiURL: String
    private var apiKey: String
    private var currentTask: URLSessionDataTask?
    
    init(apiURL: String = "https://api.openrouter.ai/api/v1/chat/completions", apiKey: String = "") {
        self.apiURL = apiURL
        self.apiKey = apiKey
    }
    
    func updateCredentials(apiURL: String, apiKey: String) {
        self.apiURL = apiURL
        self.apiKey = apiKey
    }
    
    func sendMessage(
        messages: [Message],
        settings: ChatSettings,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        // Cancel any existing streaming task
        cancelStreaming()
        
        guard !apiKey.isEmpty else {
            onComplete(.failure(LLMError.unauthorized))
            return
        }
        
        let request = ChatRequest(settings: settings, messages: messages)
        
        guard let url = URL(string: apiURL) else {
            onComplete(.failure(LLMError.invalidURL))
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "Authorization")
        
        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            onComplete(.failure(error))
            return
        }
        
        let session = URLSession(configuration: .default)
        
        if settings.stream {
            startStreamingSession(request: urlRequest, session: session, onToken: onToken, onComplete: onComplete)
        } else {
            startNonStreamingSession(request: urlRequest, session: session, onComplete: onComplete)
        }
    }
    
    private func startStreamingSession(
        request: URLRequest,
        session: URLSession,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        let delegate = StreamingDelegate(onToken: onToken, onComplete: onComplete)
        currentTask = session.dataTask(with: request)
        currentTask?.resume()
        
        // Для стриминга используем URLSession с delegate
        let streamingSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = streamingSession.dataTask(with: request)
        currentTask = task
        task.resume()
    }
    
    private func startNonStreamingSession(
        request: URLRequest,
        session: URLSession,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                onComplete(.failure(error))
                return
            }
            
            guard let data = data else {
                onComplete(.failure(LLMError.noData))
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let chatResponse = try decoder.decode(ChatResponse.self, from: data)
                
                if let content = chatResponse.content {
                    onComplete(.success(content))
                } else {
                    onComplete(.failure(LLMError.invalidResponse))
                }
            } catch {
                onComplete(.failure(error))
            }
        }
        
        currentTask = task
        task.resume()
    }
    
    func cancelStreaming() {
        currentTask?.cancel()
        currentTask = nil
    }
}

// MARK: - Streaming Delegate

private class StreamingDelegate: NSObject, URLSessionDataDelegate {
    let onToken: (String) -> Void
    let onComplete: (Result<String, Error>) -> Void
    
    private var accumulatedContent = ""
    
    init(onToken: @escaping (String) -> Void, onComplete: @escaping (Result<String, Error>) -> Void) {
        self.onToken = onToken
        self.onComplete = onComplete
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let responseString = String(decoding: data, as: UTF8.self)
        
        // Parse SSE (Server-Sent Events) format
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
                            onToken(content)
                        }
                        
                        // Check for finish reason
                        if let finishReason = chatResponse.choices?.first?.finish_reason,
                           finishReason == "stop" || finishReason == "length" {
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
                return // Ignore cancellation errors
            }
            onComplete(.failure(error))
        } else if !accumulatedContent.isEmpty {
            onComplete(.success(accumulatedContent))
        }
    }
}

// MARK: - LLM Errors

enum LLMError: LocalizedError {
    case unauthorized
    case invalidURL
    case noData
    case invalidResponse
    case streamingError
    
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
        case .streamingError:
            return "Ошибка стриминга"
        }
    }
}

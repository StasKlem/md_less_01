import Foundation

// MARK: - Logging URL Protocol
// Примечание: httpBody не доступен через URLProtocol на macOS,
// поэтому логирование запросов выполняется в NetworkManager

final class LoggingURLProtocol: URLProtocol {
    
    // MARK: - Properties
    
    private var sessionTask: URLSessionDataTask?
    private var responseData = Data()
    private var startTime: Date?
    
    private struct AssociatedKeys {
        static var requestKey = "LoggingURLProtocol.requestKey"
    }
    
    // MARK: - URLProtocol Methods
    
    override class func canInit(with request: URLRequest) -> Bool {
        // Проверяем, не обработан ли уже этот запрос
        if property(forKey: AssociatedKeys.requestKey, in: request) != nil {
            return false
        }
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        startTime = Date()
        
        // Помечаем запрос как обработанный
        let newRequest = NSMutableURLRequest(url: request.url!)
        newRequest.httpMethod = request.httpMethod ?? "GET"
        newRequest.allHTTPHeaderFields = request.allHTTPHeaderFields
        newRequest.httpBody = request.httpBody
        newRequest.setValue("true", forHTTPHeaderField: "X-Logged")
        LoggingURLProtocol.setProperty(true, forKey: AssociatedKeys.requestKey, in: newRequest)
        
        // Создаём новую сессию без этого протокола для избежания цикла
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = nil
        
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        sessionTask = session.dataTask(with: newRequest as URLRequest)
        sessionTask?.resume()
    }
    
    override func stopLoading() {
        sessionTask?.cancel()
        responseData.removeAll()
    }
}

// MARK: - URLSessionDataDelegate

extension LoggingURLProtocol: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        responseData.removeAll()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData.append(data)
        client?.urlProtocol(self, didLoad: data)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let duration = Date().timeIntervalSince(startTime ?? Date())
        
        if let error = error {
            Logger.shared.log("HTTP ошибка: \(error.localizedDescription)", type: .error)
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            if let response = task.response {
                Logger.shared.log("HTTP ответ: \(response.url?.absoluteString ?? "unknown"), статус: \((response as? HTTPURLResponse)?.statusCode ?? -1), время: \(String(format: "%.3f", duration))с, размер: \(formatBytes(responseData.count))", type: .response)
            }
            client?.urlProtocol(self, didLoad: responseData)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

//
//  NetworkError.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Ошибки сетевого слоя.
/// Детализируют ошибки, возникающие при работе с сетью.
enum NetworkError: LocalizedError {
    
    /// Некорректный URL
    case invalidURL(String)
    
    /// Ошибка HTTP статуса
    case httpStatus(Int, Data?)
    
    /// Таймаут запроса
    case timeout
    
    /// Отмена запроса
    case cancelled
    
    /// Ошибка подключения (нет сети, DNS, и т.д.)
    case connection(Error)
    
    /// Ошибка SSL/TLS
    case ssl(Error)
    
    /// Превышен размер ответа
    case responseTooLarge
    
    /// Ошибка парсинга ответа
    case decoding(String, Error?)
    
    /// SSE: ошибка парсинга события
    case sseParsing(String)
    
    /// SSE: пустой поток
    case sseEmptyStream
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Некорректный URL: \(url)"
        case .httpStatus(let code, _):
            return "Ошибка сервера: \(code) \(HTTPURLResponse.localizedString(forStatusCode: code))"
        case .timeout:
            return "Превышено время ожидания ответа"
        case .cancelled:
            return "Запрос отменён"
        case .connection:
            return "Ошибка подключения. Проверьте интернет-соединение"
        case .ssl:
            return "Ошибка защищённого соединения"
        case .responseTooLarge:
            return "Ответ сервера слишком большой"
        case .decoding(let message, _):
            return "Ошибка обработки ответа: \(message)"
        case .sseParsing(let message):
            return "Ошибка потока данных: \(message)"
        case .sseEmptyStream:
            return "Пустой поток данных от сервера"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            return "Проверьте корректность URL сервера в настройках"
        case .httpStatus(let code, _):
            return httpSuggestion(for: code)
        case .timeout:
            return "Попробуйте повторить запрос или проверьте скорость соединения"
        case .cancelled:
            return nil
        case .connection:
            return "Проверьте подключение к интернету и настройки брандмауэра"
        case .ssl:
            return "Убедитесь, что сервер использует_valid SSL-сертификат"
        case .responseTooLarge:
            return "Попробуйте уменьшить размер запроса"
        case .decoding:
            return "Возможно, сервер вернул данные в неожиданном формате"
        case .sseParsing, .sseEmptyStream:
            return "Проверьте, что сервер поддерживает SSE (Server-Sent Events)"
        }
    }
    
    private func httpSuggestion(for code: Int) -> String? {
        switch code {
        case 400:
            return "Некорректный запрос. Проверьте настройки"
        case 401:
            return "Неверный API Key. Проверьте настройки авторизации"
        case 403:
            return "Доступ запрещён. Проверьте права доступа"
        case 404:
            return "Эндпоинт не найден. Проверьте URL сервера"
        case 429:
            return "Превышен лимит запросов. Подождите немного"
        case 500, 502, 503:
            return "Проблема на стороне сервера. Попробуйте позже"
        default:
            return nil
        }
    }
}

// MARK: - From URLError

extension NetworkError {
    init(from urlError: URLError) {
        switch urlError.code {
        case .timedOut:
            self = .timeout
        case .cancelled:
            self = .cancelled
        case .notConnectedToInternet,
             .networkConnectionLost,
             .dnsLookupFailed,
             .dataNotAllowed:
            self = .connection(urlError)
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid:
            self = .ssl(urlError)
        default:
            self = .connection(urlError)
        }
    }
}

// MARK: - From Error

extension NetworkError {
    init(from error: Error, data: Data? = nil) {
        if let urlError = error as? URLError {
            self.init(from: urlError)
        } else if let httpError = error as? HTTPError {
            self = .httpStatus(httpError.code, data)
        } else {
            self = .connection(error)
        }
    }
}

// MARK: - HTTPError Helper

/// Внутренняя ошибка для HTTP статусов
struct HTTPError: Error {
    let code: Int
    let response: HTTPURLResponse
    
    init(response: HTTPURLResponse) {
        self.code = response.statusCode
        self.response = response
    }
}

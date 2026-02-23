//
//  Publisher+Utils.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Combine
import Foundation

/// Extension для упрощения работы с Combine Publishers.
extension Publisher {
    
    /// Erase тип до AnyPublisher и отправить на MainActor
    func eraseToAnyPublisher() -> AnyPublisher<Output, Failure> {
        receive(on: RunLoop.main).eraseToAnyPublisher()
    }
    
    /// Обернуть в Optional для обработки nil-значений
    func eraseToOptional() -> AnyPublisher<Output?, Failure> {
        map { $0 }.eraseToAnyPublisher()
    }
}

// MARK: - Error Handling

extension Publisher where Failure == Error {
    
    /// Преобразовать ошибку в AppError
    func mapErrorToAppError() -> AnyPublisher<Output, AppError> {
        mapError { error -> AppError in
            if let appError = error as? AppError {
                return appError
            } else if let networkError = error as? NetworkError {
                return .network(networkError)
            } else {
                return .unknown(error)
            }
        }.eraseToAnyPublisher()
    }
    
    /// Заменить ошибку на default значение
    func replaceError(with defaultValue: Output) -> AnyPublisher<Output, Never> {
        replaceError(with: defaultValue)
            .eraseToAnyPublisher()
    }
    
    /// Логировать ошибку перед propagating
    func logError(_ logger: @escaping (Error) -> Void) -> Publishers.HandleEvents<Self> {
        handleEvents(receiveCompletion: { completion in
            if case .failure(let error) = completion {
                logger(error)
            }
        })
    }
}

// MARK: - Throttling & Debouncing

extension Publisher {
    
    /// Debounce с указанным интервалом на MainActor
    func debounce<S>(for dueTime: S, scheduler: RunLoop = .main) -> Publishers.Debounce<Self, S>
    where S: Scheduler {
        debounce(for: dueTime, scheduler: scheduler)
    }
    
    /// Throttle с указанным интервалом на MainActor
    func throttle<S>(
        for dueTime: S,
        scheduler: RunLoop = .main,
        latest: Bool = true
    ) -> Publishers.Throttle<Self, S>
    where S: Scheduler {
        throttle(for: dueTime, scheduler: scheduler, latest: latest)
    }
}

// MARK: - Retry Logic

extension Publisher {
    
    /// Повторить подписку указанное количество раз при ошибке
    func retry(_ count: Int, delay: TimeInterval = 0, scheduler: RunLoop = .main) -> Publishers.Retry<Self> {
        if delay > 0 {
            return retry(count)
        } else {
            return retry(count)
        }
    }
    
    /// Экспоненциальный backoff при retry
    func retryWithExponentialBackoff(
        maxRetries: Int = 3,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        scheduler: RunLoop = .main
    ) -> AnyPublisher<Output, Failure> {
        var retryCount = 0
        var currentDelay = initialDelay
        
        return self.catch { error -> AnyPublisher<Output, Failure> in
            guard retryCount < maxRetries else {
                return Fail(outputType: Output.self, failure: error).eraseToAnyPublisher()
            }
            
            retryCount += 1
            let delayInterval = Swift.min(currentDelay, maxDelay)
            currentDelay *= 2
            
            return Just(())
                .delay(for: .seconds(delayInterval), scheduler: scheduler)
                .flatMap { self.retryWithExponentialBackoff(maxRetries: maxRetries, initialDelay: initialDelay, maxDelay: maxDelay, scheduler: scheduler) }
                .eraseToAnyPublisher()
        }.eraseToAnyPublisher()
    }
}

// MARK: - Timeout with Custom Error

extension Publisher where Failure == Error {

    /// Timeout с кастомной ошибкой
    func timeoutWithError(_ customError: @escaping () -> Failure, after interval: TimeInterval) -> Publishers.Timeout<Self, RunLoop> {
        timeout(.seconds(interval), scheduler: RunLoop.main, customError: customError)
    }
}

// MARK: - PassthroughSubject Extensions

extension PassthroughSubject {
    
    /// Отправить значение и автоматически завершить
    func sendAndFinish(_ value: Output) {
        send(value)
        send(completion: .finished)
    }
}

// MARK: - CurrentValueSubject Extensions

extension CurrentValueSubject {
    
    /// Получить текущее значение
    var currentValue: Output {
        value
    }
}

// MARK: - Cancellables Helper

/// Helper для управления подписками в ViewModels
final class Cancellables {
    private var cancellables = Set<AnyCancellable>()
    
    func store(_ cancellable: AnyCancellable) {
        cancellable.store(in: &cancellables)
    }
    
    func store<S>(_ publishers: S) where S: Sequence, S.Element == AnyCancellable {
        publishers.forEach { $0.store(in: &cancellables) }
    }
    
    func cancelAll() {
        cancellables.removeAll()
    }
}

import Foundation

/// Общий контракт для команд управления task-агентом.
protocol TaskAgentControlProtocol {
    var title: String { get }
    var command: String { get }
}

/// Общий контракт task-агента для построения UI-кнопок.
protocol TaskAgentDescriptorProtocol {
    var id: TaskAgentID { get }
    var name: String { get }
    var startCommand: String { get }
    var controls: [TaskAgentControl] { get }
}

enum TaskAgentID: String, Equatable {
    case mock
    case counter
    case hackerNews
}

struct TaskAgentControl: TaskAgentControlProtocol, Equatable {
    let title: String
    let command: String
}

struct TaskAgentDescriptor: TaskAgentDescriptorProtocol, Equatable {
    let id: TaskAgentID
    let name: String
    let startCommand: String
    let controls: [TaskAgentControl]
}

enum TaskAgentCatalog {
    static let all: [TaskAgentDescriptor] = [
        TaskAgentDescriptor(
            id: .mock,
            name: "Mock Task Agent",
            startCommand: "/task start",
            controls: [
                TaskAgentControl(title: "Стоп", command: "/task stop")
            ]
        ),
        TaskAgentDescriptor(
            id: .counter,
            name: "Counter Task Agent",
            startCommand: "/counter start",
            controls: [
                TaskAgentControl(title: "Стоп", command: "/counter stop"),
                TaskAgentControl(title: "Интервал 1с", command: "/counter interval 1"),
                TaskAgentControl(title: "Интервал 5с", command: "/counter interval 5")
            ]
        ),
        TaskAgentDescriptor(
            id: .hackerNews,
            name: "Hacker News Task Agent",
            startCommand: "/hn start",
            controls: [
                TaskAgentControl(title: "Стоп", command: "/hn stop"),
                TaskAgentControl(title: "Интервал 5с", command: "/hn interval 5"),
                TaskAgentControl(title: "Интервал 10с", command: "/hn interval 10")
            ]
        )
    ]
}

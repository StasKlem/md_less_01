import Foundation

protocol GetCurrentGitBranchUseCaseProtocol: Sendable {
    func execute() throws -> String
}

struct GetCurrentGitBranchUseCase: GetCurrentGitBranchUseCaseProtocol {
    private let repository: ProjectRepositoryProtocol

    init(repository: ProjectRepositoryProtocol) {
        self.repository = repository
    }

    func execute() throws -> String {
        try repository.currentGitBranch()
    }
}

protocol ListProjectFilesUseCaseProtocol: Sendable {
    func execute() throws -> [ProjectFile]
}

struct ListProjectFilesUseCase: ListProjectFilesUseCaseProtocol {
    private let repository: ProjectRepositoryProtocol

    init(repository: ProjectRepositoryProtocol) {
        self.repository = repository
    }

    func execute() throws -> [ProjectFile] {
        try repository.listProjectFiles()
    }
}

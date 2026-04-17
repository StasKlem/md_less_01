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

protocol ReadProjectFileUseCaseProtocol: Sendable {
    func execute(relativePath: String) throws -> ProjectFileReadResult
}

struct ReadProjectFileUseCase: ReadProjectFileUseCaseProtocol {
    private let repository: ProjectWorkspaceRepositoryProtocol

    init(repository: ProjectWorkspaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(relativePath: String) throws -> ProjectFileReadResult {
        try repository.readFile(relativePath: relativePath)
    }
}

protocol SearchProjectFilesUseCaseProtocol: Sendable {
    func execute(query: String) throws -> ProjectFileSearchResult
}

struct SearchProjectFilesUseCase: SearchProjectFilesUseCaseProtocol {
    private let projectRepository: ProjectRepositoryProtocol
    private let workspaceRepository: ProjectWorkspaceRepositoryProtocol

    init(
        projectRepository: ProjectRepositoryProtocol,
        workspaceRepository: ProjectWorkspaceRepositoryProtocol
    ) {
        self.projectRepository = projectRepository
        self.workspaceRepository = workspaceRepository
    }

    func execute(query: String) throws -> ProjectFileSearchResult {
        let files = try projectRepository.listProjectFiles()
        return try workspaceRepository.searchFiles(query: query, files: files)
    }
}

protocol WriteProjectFileUseCaseProtocol: Sendable {
    func execute(relativePath: String, contents: String) throws -> ProjectFileWriteResult
}

struct WriteProjectFileUseCase: WriteProjectFileUseCaseProtocol {
    private let repository: ProjectWorkspaceRepositoryProtocol

    init(repository: ProjectWorkspaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(relativePath: String, contents: String) throws -> ProjectFileWriteResult {
        try repository.writeFile(relativePath: relativePath, contents: contents)
    }
}

protocol GetUncommittedChangesUseCaseProtocol: Sendable {
    func execute() throws -> ProjectUncommittedChanges
}

struct GetUncommittedChangesUseCase: GetUncommittedChangesUseCaseProtocol {
    private let repository: ProjectRepositoryProtocol

    init(repository: ProjectRepositoryProtocol) {
        self.repository = repository
    }

    func execute() throws -> ProjectUncommittedChanges {
        try repository.uncommittedChanges()
    }
}

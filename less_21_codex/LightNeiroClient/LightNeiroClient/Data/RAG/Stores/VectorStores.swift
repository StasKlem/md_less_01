import Foundation
import SQLite3
import Darwin

actor SQLiteVSSVectorStore: VectorStore {
    private let databaseURL: URL
    private let vssExtensionPath: String?

    private var db: OpaquePointer?
    private var vssEnabled = false

    init(
        databaseURL: URL = SQLiteVSSVectorStore.defaultDatabaseURL(),
        vssExtensionPath: String? = ProcessInfo.processInfo.environment["SQLITE_VSS_EXTENSION_PATH"]
    ) {
        self.databaseURL = databaseURL
        self.vssExtensionPath = vssExtensionPath
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func reset() async throws {
        try openIfNeeded()
        try execute("DELETE FROM document_chunks;")
        if vssEnabled {
            try? execute("DELETE FROM vss_document_chunks;")
        }
    }

    func upsert(chunks: [DocumentChunk]) async throws {
        guard !chunks.isEmpty else { return }
        try openIfNeeded()

        try execute("BEGIN TRANSACTION;")
        defer { try? execute("COMMIT;") }

        let sql = """
            INSERT OR REPLACE INTO document_chunks
            (id, content, embedding_blob, source, title, section, chunk_offset, embedding_dim, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(message: "Failed to prepare upsert statement")
        }
        defer { sqlite3_finalize(statement) }

        for chunk in chunks {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)

            bindText(chunk.id.uuidString, to: statement, index: 1)
            bindText(chunk.content, to: statement, index: 2)
            bindBlob(serialize(vector: chunk.embedding), to: statement, index: 3)
            bindText(chunk.source, to: statement, index: 4)
            bindNullableText(chunk.title, to: statement, index: 5)
            bindNullableText(chunk.section, to: statement, index: 6)
            sqlite3_bind_int64(statement, 7, sqlite3_int64(chunk.offset))
            sqlite3_bind_int(statement, 8, Int32(chunk.embedding.count))
            sqlite3_bind_double(statement, 9, Date().timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw sqliteError(message: "Failed to execute upsert")
            }

            if vssEnabled {
                let rowID = sqlite3_last_insert_rowid(db)
                try upsertIntoVSS(rowID: rowID, embedding: chunk.embedding)
            }
        }
    }

    func search(queryEmbedding: [Float], topK: Int) async throws -> [SearchResult] {
        guard !queryEmbedding.isEmpty, topK > 0 else { return [] }
        try openIfNeeded()

        if vssEnabled, let results = try searchUsingVSS(queryEmbedding: queryEmbedding, topK: topK) {
            return results
        }
        return try searchUsingFallbackScan(queryEmbedding: queryEmbedding, topK: topK)
    }

    private func openIfNeeded() throws {
        if db != nil { return }

        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            throw sqliteError(message: "Failed to open SQLite database")
        }

        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
        try createSchema()
        try configureVSSIfAvailable()
    }

    private func createSchema() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS document_chunks (
                id TEXT PRIMARY KEY,
                content TEXT NOT NULL,
                embedding_blob BLOB NOT NULL,
                source TEXT NOT NULL,
                title TEXT,
                section TEXT,
                chunk_offset INTEGER NOT NULL,
                embedding_dim INTEGER NOT NULL,
                created_at REAL NOT NULL
            );
            """
        )
        try execute("CREATE INDEX IF NOT EXISTS idx_document_chunks_source ON document_chunks(source);")
    }

    private func configureVSSIfAvailable() throws {
        if let vssExtensionPath {
            try loadSQLiteExtensionIfNeeded(path: vssExtensionPath)
        }

        let status = sqlite3_exec(
            db,
            "CREATE VIRTUAL TABLE IF NOT EXISTS vss_document_chunks USING vss0(embedding(768));",
            nil,
            nil,
            nil
        )
        vssEnabled = status == SQLITE_OK
    }

    private func loadSQLiteExtensionIfNeeded(path: String) throws {
        guard let handle = dlopen(nil, RTLD_NOW) else {
            throw RAGError.vectorStoreUnavailable("dlopen failed while loading sqlite-vss")
        }
        defer { dlclose(handle) }

        typealias EnableLoadExtensionFn = @convention(c) (OpaquePointer?, Int32) -> Int32
        typealias LoadExtensionFn = @convention(c) (
            OpaquePointer?,
            UnsafePointer<CChar>?,
            UnsafePointer<CChar>?,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        ) -> Int32

        guard
            let enableSymbol = dlsym(handle, "sqlite3_enable_load_extension"),
            let loadSymbol = dlsym(handle, "sqlite3_load_extension")
        else {
            throw RAGError.vectorStoreUnavailable("sqlite load_extension symbols are unavailable in this runtime")
        }

        let enableLoadExtension = unsafeBitCast(enableSymbol, to: EnableLoadExtensionFn.self)
        let loadExtension = unsafeBitCast(loadSymbol, to: LoadExtensionFn.self)

        guard enableLoadExtension(db, 1) == SQLITE_OK else {
            throw sqliteError(message: "Failed to enable sqlite extension loading")
        }

        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = path.withCString { cPath in
            loadExtension(db, cPath, nil, &errorPointer)
        }
        if status != SQLITE_OK {
            let reason = errorPointer.map { String(cString: $0) } ?? "Unknown sqlite-vss load error"
            if let errorPointer {
                sqlite3_free(errorPointer)
            }
            throw RAGError.vectorStoreUnavailable("Failed to load sqlite-vss extension: \(reason)")
        }
    }

    private func upsertIntoVSS(rowID: sqlite3_int64, embedding: [Float]) throws {
        let sql = "INSERT OR REPLACE INTO vss_document_chunks(rowid, embedding) VALUES (?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(message: "Failed to prepare VSS upsert statement")
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, rowID)
        bindText(serializeVectorToJSONString(embedding), to: statement, index: 2)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError(message: "Failed to execute VSS upsert")
        }
    }

    private func searchUsingVSS(queryEmbedding: [Float], topK: Int) throws -> [SearchResult]? {
        let sql = """
            SELECT c.id, c.content, c.embedding_blob, c.source, c.title, c.section, c.chunk_offset, v.distance
            FROM vss_document_chunks v
            JOIN document_chunks c ON c.rowid = v.rowid
            WHERE v.embedding MATCH ?
            LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        bindText(serializeVectorToJSONString(queryEmbedding), to: statement, index: 1)
        sqlite3_bind_int(statement, 2, Int32(topK))

        var rows: [SearchResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let chunk = decodeChunk(statement: statement)
            let distance = Float(sqlite3_column_double(statement, 7))
            rows.append(SearchResult(chunk: chunk, score: 1.0 / (1.0 + max(0, distance))))
        }
        if rows.isEmpty {
            return nil
        }
        return rows
    }

    private func searchUsingFallbackScan(queryEmbedding: [Float], topK: Int) throws -> [SearchResult] {
        let sql = "SELECT id, content, embedding_blob, source, title, section, chunk_offset FROM document_chunks;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(message: "Failed to prepare fallback search statement")
        }
        defer { sqlite3_finalize(statement) }

        var results: [SearchResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let chunk = decodeChunk(statement: statement)
            let score = cosineSimilarity(lhs: queryEmbedding, rhs: chunk.embedding)
            results.append(SearchResult(chunk: chunk, score: score))
        }
        return Array(results.sorted(by: { $0.score > $1.score }).prefix(topK))
    }

    private func decodeChunk(statement: OpaquePointer?) -> DocumentChunk {
        let idText = readString(statement: statement, index: 0) ?? UUID().uuidString
        let content = readString(statement: statement, index: 1) ?? ""
        let embeddingBlob = readData(statement: statement, index: 2) ?? Data()
        let source = readString(statement: statement, index: 3) ?? ""
        let title = readString(statement: statement, index: 4)
        let section = readString(statement: statement, index: 5)
        let offset = Int(sqlite3_column_int64(statement, 6))

        return DocumentChunk(
            id: UUID(uuidString: idText) ?? UUID(),
            content: content,
            embedding: deserializeVector(from: embeddingBlob),
            source: source,
            title: title,
            section: section,
            offset: offset
        )
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw sqliteError(message: "SQLite execution failed: \(sql)")
        }
    }

    private func sqliteError(message: String) -> Error {
        let sqliteMessage = db.flatMap { sqlite3_errmsg($0).map { String(cString: $0) } } ?? "Unknown SQLite error"
        return RAGError.vectorStoreUnavailable("\(message). \(sqliteMessage)")
    }

    private func bindText(_ text: String, to statement: OpaquePointer?, index: Int32) {
        sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT)
    }

    private func bindNullableText(_ text: String?, to statement: OpaquePointer?, index: Int32) {
        if let text {
            sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindBlob(_ data: Data, to statement: OpaquePointer?, index: Int32) {
        data.withUnsafeBytes { bytes in
            _ = sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
        }
    }

    private func readString(statement: OpaquePointer?, index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func readData(statement: OpaquePointer?, index: Int32) -> Data? {
        guard let pointer = sqlite3_column_blob(statement, index) else { return nil }
        let length = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: pointer, count: length)
    }

    private func serialize(vector: [Float]) -> Data {
        var local = vector
        return Data(bytes: &local, count: local.count * MemoryLayout<Float>.size)
    }

    private func deserializeVector(from data: Data) -> [Float] {
        guard !data.isEmpty else { return [] }
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { buffer in
            let pointer = buffer.bindMemory(to: Float.self)
            return Array(pointer.prefix(count))
        }
    }

    private func serializeVectorToJSONString(_ vector: [Float]) -> String {
        let body = vector.map { String($0) }.joined(separator: ",")
        return "[\(body)]"
    }

    private func cosineSimilarity(lhs: [Float], rhs: [Float]) -> Float {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return -1 }
        var dot: Float = 0
        var lhsNorm: Float = 0
        var rhsNorm: Float = 0

        for idx in lhs.indices {
            dot += lhs[idx] * rhs[idx]
            lhsNorm += lhs[idx] * lhs[idx]
            rhsNorm += rhs[idx] * rhs[idx]
        }

        let denominator = sqrt(lhsNorm) * sqrt(rhsNorm)
        guard denominator > 0 else { return -1 }
        return dot / denominator
    }

    nonisolated private static func defaultDatabaseURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = appSupport.appendingPathComponent("LightNeiroClient", isDirectory: true)
        return directory.appendingPathComponent("rag.sqlite")
    }
}

struct FAISSVectorStore: VectorStore {
    enum Mode: Equatable {
        case pythonKit
        case http(baseURL: URL)
    }

    let mode: Mode

    func reset() async throws {
        throw unsupportedError()
    }

    func upsert(chunks: [DocumentChunk]) async throws {
        _ = chunks
        throw unsupportedError()
    }

    func search(queryEmbedding: [Float], topK: Int) async throws -> [SearchResult] {
        _ = queryEmbedding
        _ = topK
        throw unsupportedError()
    }

    private func unsupportedError() -> Error {
        let reason: String
        switch mode {
        case .pythonKit:
            reason = "FAISS via PythonKit is not wired in this target yet."
        case let .http(baseURL):
            reason = "FAISS HTTP adapter is not implemented. Endpoint: \(baseURL.absoluteString)"
        }
        return RAGError.vectorStoreUnavailable(reason)
    }
}

actor InMemoryVectorStore: VectorStore {
    private var chunks: [DocumentChunk] = []

    func reset() async throws {
        chunks = []
    }

    func upsert(chunks: [DocumentChunk]) async throws {
        self.chunks.removeAll { old in
            chunks.contains(where: { $0.id == old.id })
        }
        self.chunks.append(contentsOf: chunks)
    }

    func search(queryEmbedding: [Float], topK: Int) async throws -> [SearchResult] {
        guard topK > 0 else { return [] }
        return Array(
            chunks
                .map { chunk in
                    SearchResult(chunk: chunk, score: cosineSimilarity(lhs: queryEmbedding, rhs: chunk.embedding))
                }
                .sorted(by: { $0.score > $1.score })
                .prefix(topK)
        )
    }

    private func cosineSimilarity(lhs: [Float], rhs: [Float]) -> Float {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return -1 }

        var dot: Float = 0
        var lhsNorm: Float = 0
        var rhsNorm: Float = 0

        for idx in lhs.indices {
            dot += lhs[idx] * rhs[idx]
            lhsNorm += lhs[idx] * lhs[idx]
            rhsNorm += rhs[idx] * rhs[idx]
        }

        let denominator = sqrt(lhsNorm) * sqrt(rhsNorm)
        guard denominator > 0 else { return -1 }
        return dot / denominator
    }
}

nonisolated(unsafe) private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

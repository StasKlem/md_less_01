import Foundation
import MCP

final class MCPToolDiscoveryService: MCPToolDiscoveryServiceProtocol {
    private let clientFactory: @Sendable () -> Client

    init(clientFactory: @escaping @Sendable () -> Client = {
        Client(name: "LightNeiroClient", version: "1.0.0")
    }) {
        self.clientFactory = clientFactory
    }

    func fetchTools(serverURL: URL) async throws -> [MCPToolSummary] {
        let client = clientFactory()
        let transport = HTTPClientTransport(endpoint: serverURL, streaming: false)

        do {
            _ = try await client.connect(transport: transport)
            let result = try await client.listTools()
            await client.disconnect()
            return result.tools
                .map { MCPToolSummary(name: $0.name, description: $0.description) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            await client.disconnect()
            throw error
        }
    }
}

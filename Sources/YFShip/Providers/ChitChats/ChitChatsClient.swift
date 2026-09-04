import Foundation

struct ChitChatsClient: Sendable {
    static let productionBaseURL = URL(string: "https://chitchats.com/api/v1")!

    private let configuration: ChitChatsConfiguration
    private let httpClient: any HTTPClient
    private let baseURL: URL

    init(
        configuration: ChitChatsConfiguration,
        httpClient: any HTTPClient,
        baseURL: URL = productionBaseURL
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.baseURL = baseURL
    }

    func createShipment(
        for shipment: Shipment
    ) async throws -> ChitChatsShipmentResponse {
        var request = authorizedRequest(url: shipmentsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            request.httpBody = try JSONEncoder().encode(
                ChitChatsShipmentRequest(
                    shipment: shipment,
                    packageType: configuration.packageType
                )
            )
        } catch {
            throw ProviderFailure(
                provider: .chitchats,
                code: "invalid_request",
                message: "Chit Chats shipment data could not be encoded."
            )
        }

        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(
                ChitChatsShipmentResponse.self,
                from: data
            )
        } catch {
            throw ProviderFailure(
                provider: .chitchats,
                code: "malformed_response",
                message: "Chit Chats returned an unreadable shipment response."
            )
        }
    }

    func deleteShipment(id: String) async throws {
        var request = authorizedRequest(
            url: shipmentsURL.appendingPathComponent(id)
        )
        request.httpMethod = "DELETE"
        _ = try await perform(request)
    }

    private var shipmentsURL: URL {
        baseURL
            .appendingPathComponent("clients")
            .appendingPathComponent(configuration.clientID)
            .appendingPathComponent("shipments")
    }

    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(
            configuration.accessToken,
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch let error as HTTPError {
            throw Self.failure(for: error)
        } catch {
            throw ProviderFailure(
                provider: .chitchats,
                code: "transport",
                message: "Chit Chats network request failed."
            )
        }

        guard (200...299).contains(response.statusCode) else {
            throw Self.failure(forStatus: response.statusCode)
        }
        return data
    }

    private static func failure(for error: HTTPError) -> ProviderFailure {
        switch error {
        case let .invalidStatus(code, _):
            failure(forStatus: code)
        case .nonHTTPResponse, .transport:
            ProviderFailure(
                provider: .chitchats,
                code: "transport",
                message: "Chit Chats network request failed."
            )
        }
    }

    private static func failure(forStatus statusCode: Int) -> ProviderFailure {
        switch statusCode {
        case 401, 403:
            ProviderFailure(
                provider: .chitchats,
                code: "authentication_failed",
                message: "Chit Chats authentication failed."
            )
        case 400, 422:
            ProviderFailure(
                provider: .chitchats,
                code: "validation_failed",
                message: "Chit Chats rejected the shipment request."
            )
        default:
            ProviderFailure(
                provider: .chitchats,
                code: "http_\(statusCode)",
                message: "Chit Chats request failed with HTTP status \(statusCode)."
            )
        }
    }
}

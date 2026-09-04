import Foundation

struct StallionClient: Sendable {
    static let productionBaseURL = URL(string: "https://ship.stallion.ca/api/v5")!

    private let configuration: StallionConfiguration
    private let httpClient: any HTTPClient
    private let baseURL: URL

    init(
        configuration: StallionConfiguration,
        httpClient: any HTTPClient,
        baseURL: URL = productionBaseURL
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.baseURL = baseURL
    }

    func fetchRates(for shipment: Shipment) async throws -> StallionRatesResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("rates"))
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(configuration.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            request.httpBody = try JSONEncoder().encode(
                StallionRatesRequest(shipment: shipment)
            )
        } catch {
            throw ProviderFailure(
                provider: .stallion,
                code: "invalid_request",
                message: "Stallion shipment data could not be encoded."
            )
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch let error as HTTPError {
            throw Self.failure(for: error)
        } catch {
            throw ProviderFailure(
                provider: .stallion,
                code: "transport",
                message: "Stallion network request failed."
            )
        }

        guard (200...299).contains(response.statusCode) else {
            throw Self.failure(forStatus: response.statusCode)
        }

        do {
            return try JSONDecoder().decode(StallionRatesResponse.self, from: data)
        } catch {
            throw ProviderFailure(
                provider: .stallion,
                code: "malformed_response",
                message: "Stallion returned an unreadable rate response."
            )
        }
    }

    private static func failure(for error: HTTPError) -> ProviderFailure {
        switch error {
        case let .invalidStatus(code, _):
            failure(forStatus: code)
        case .nonHTTPResponse, .transport:
            ProviderFailure(
                provider: .stallion,
                code: "transport",
                message: "Stallion network request failed."
            )
        }
    }

    private static func failure(forStatus statusCode: Int) -> ProviderFailure {
        switch statusCode {
        case 401, 403:
            ProviderFailure(
                provider: .stallion,
                code: "authentication_failed",
                message: "Stallion authentication failed."
            )
        case 400, 422:
            ProviderFailure(
                provider: .stallion,
                code: "validation_failed",
                message: "Stallion rejected the shipment request."
            )
        default:
            ProviderFailure(
                provider: .stallion,
                code: "http_\(statusCode)",
                message: "Stallion request failed with HTTP status \(statusCode)."
            )
        }
    }
}

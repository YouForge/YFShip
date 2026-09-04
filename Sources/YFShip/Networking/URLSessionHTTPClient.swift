import Foundation

struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPError.nonHTTPResponse
            }
            return (data, httpResponse)
        } catch let error as HTTPError {
            throw error
        } catch {
            throw HTTPError.transport(underlying: error)
        }
    }
}

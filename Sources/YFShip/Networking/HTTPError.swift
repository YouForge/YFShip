import Foundation

enum HTTPError: Error {
    case nonHTTPResponse
    case invalidStatus(code: Int, body: Data)
    case transport(underlying: any Error)
}

import Foundation
import Testing
@testable import YFShip

@Suite("Chit Chats provider")
struct ChitChatsProviderTests {
    @Test("Creates, maps, and deletes a temporary shipment")
    func performsTemporaryShipmentLifecycle() async throws {
        let creationData = try ProviderFixture.data("ChitChats", "create_success")
        let deletionData = try ProviderFixture.data("ChitChats", "delete_success")
        let recorder = RequestRecorder()
        let httpClient = MockHTTPClient { request in
            await recorder.record(request)

            switch request.httpMethod {
            case "POST":
                return (
                    creationData,
                    try testHTTPResponse(for: request, statusCode: 201)
                )
            case "DELETE":
                return (
                    deletionData,
                    try testHTTPResponse(for: request, statusCode: 204)
                )
            default:
                throw ProviderTestError.unexpectedRequest
            }
        }
        let provider = makeProvider(httpClient: httpClient)

        let response = try await provider.ratesWithWarning(for: testShipment())
        let rates = response.rates

        #expect(response.warning == nil)
        #expect(rates.count == 5)

        let tracked = try #require(
            rates.first { $0.serviceID == "chitchats-tracked-fast" }
        )
        #expect(tracked.total == Decimal(string: "13.45"))
        #expect(tracked.currency == "cad")
        #expect(tracked.isTrackable == true)
        #expect(tracked.estimatedDeliveryBusinessDays == 6)

        let fallbackTotal = try #require(
            rates.first { $0.serviceID == "chitchats-untracked" }
        )
        #expect(fallbackTotal.total == Decimal(string: "9.10"))
        #expect(fallbackTotal.isTrackable == false)

        let ranged = try #require(
            rates.first { $0.serviceID == "chitchats-slow" }
        )
        #expect(ranged.total == Decimal(string: "7.25"))
        #expect(ranged.estimatedDeliveryBusinessDays == 22)

        let boundary = try #require(
            rates.first { $0.serviceID == "chitchats-boundary" }
        )
        #expect(boundary.estimatedDeliveryBusinessDays == 20)

        let unknown = try #require(
            rates.first { $0.serviceID == "chitchats-unknown" }
        )
        #expect(unknown.isTrackable == nil)
        #expect(unknown.estimatedDeliveryBusinessDays == nil)
        #expect(unknown.currency == "CAD")

        let requests = await recorder.snapshot()
        #expect(requests.count == 2)
        let createRequest = try #require(requests.first)
        let deleteRequest = try #require(requests.last)

        #expect(createRequest.httpMethod == "POST")
        #expect(
            createRequest.url?.absoluteString
                == "https://example.test/api/v1/clients/client-123/shipments"
        )
        #expect(
            createRequest.value(forHTTPHeaderField: "Authorization")
                == "synthetic-token"
        )

        let bodyData = try #require(createRequest.httpBody)
        let body = try #require(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        #expect(body["postage_type"] as? String == "unknown")
        #expect(body["package_type"] as? String == "parcel")
        #expect(body["weight_unit"] as? String == "lb")
        #expect(body["size_unit"] as? String == "in")
        #expect(body["value"] as? String == "20.00")
        #expect(body["value_currency"] as? String == "cad")
        #expect(body["insurance_requested"] as? Bool == false)
        #expect(body["signature_requested"] as? Bool == false)
        #expect(body["duties_paid_requested"] as? Bool == false)

        let lineItems = try #require(body["line_items"] as? [[String: Any]])
        let lineItem = try #require(lineItems.first)
        #expect(lineItem["currency_code"] as? String == "cad")
        #expect(lineItem["value_amount"] as? String == "20.00")
        #expect(lineItem["weight_unit"] as? String == "lb")

        #expect(deleteRequest.httpMethod == "DELETE")
        #expect(
            deleteRequest.url?.absoluteString
                == "https://example.test/api/v1/clients/client-123/shipments/shipment-456"
        )
        #expect(
            deleteRequest.value(forHTTPHeaderField: "Authorization")
                == "synthetic-token"
        )
    }

    @Test("Reports both mapping and cleanup failures")
    func reportsMappingAndCleanupFailures() async throws {
        let creationData = try ProviderFixture.data("ChitChats", "partial")
        let deletionData = try ProviderFixture.data("ChitChats", "delete_failure")
        let recorder = RequestRecorder()
        let httpClient = MockHTTPClient { request in
            await recorder.record(request)

            switch request.httpMethod {
            case "POST":
                return (
                    creationData,
                    try testHTTPResponse(for: request, statusCode: 201)
                )
            case "DELETE":
                return (
                    deletionData,
                    try testHTTPResponse(for: request, statusCode: 500)
                )
            default:
                throw ProviderTestError.unexpectedRequest
            }
        }

        do {
            _ = try await makeProvider(httpClient: httpClient)
                .ratesWithWarning(for: testShipment())
            Issue.record("Expected mapping and cleanup failure")
        } catch let failure as ProviderFailure {
            #expect(failure.code == "malformed_response_cleanup_failed")
            #expect(!failure.message.contains("Synthetic cleanup failure marker."))
        }

        #expect(await recorder.snapshot().count == 2)
    }

    @Test("Returns usable rates with a cleanup warning")
    func returnsCleanupWarning() async throws {
        let creationData = try ProviderFixture.data("ChitChats", "create_success")
        let deletionData = try ProviderFixture.data("ChitChats", "delete_failure")
        let httpClient = MockHTTPClient { request in
            switch request.httpMethod {
            case "POST":
                return (
                    creationData,
                    try testHTTPResponse(for: request, statusCode: 201)
                )
            case "DELETE":
                return (
                    deletionData,
                    try testHTTPResponse(for: request, statusCode: 500)
                )
            default:
                throw ProviderTestError.unexpectedRequest
            }
        }

        let provider: any ShippingProvider = makeProvider(httpClient: httpClient)
        let response = try await provider.ratesWithWarning(for: testShipment())

        #expect(response.rates.count == 5)
        #expect(response.warning?.code == "cleanup_failed")
        #expect(
            response.warning?.message
                == "Chit Chats temporary shipment cleanup failed."
        )
        #expect(
            response.warning?.message.contains("Synthetic cleanup failure marker.")
                == false
        )
    }

    @Test("Does not delete when shipment creation authentication fails")
    func handlesCreationAuthenticationFailure() async throws {
        let data = try ProviderFixture.data("ChitChats", "auth_error")
        let recorder = RequestRecorder()
        let httpClient = MockHTTPClient { request in
            await recorder.record(request)
            return (
                data,
                try testHTTPResponse(for: request, statusCode: 401)
            )
        }

        do {
            _ = try await makeProvider(httpClient: httpClient)
                .ratesWithWarning(for: testShipment())
            Issue.record("Expected authentication failure")
        } catch let failure as ProviderFailure {
            #expect(failure.code == "authentication_failed")
            #expect(!failure.message.contains("Synthetic authentication failure."))
        }

        #expect(await recorder.snapshot().count == 1)
    }

    @Test("Maps shipment validation failures safely")
    func handlesCreationValidationFailure() async throws {
        let data = try ProviderFixture.data("ChitChats", "validation_error")
        let httpClient = MockHTTPClient { request in
            (
                data,
                try testHTTPResponse(for: request, statusCode: 422)
            )
        }

        do {
            _ = try await makeProvider(httpClient: httpClient)
                .ratesWithWarning(for: testShipment())
            Issue.record("Expected validation failure")
        } catch let failure as ProviderFailure {
            #expect(failure.code == "validation_failed")
            #expect(!failure.message.contains("Synthetic shipment validation failure."))
        }
    }

    @Test("Rejects malformed creation JSON safely")
    func rejectsMalformedCreationResponse() async throws {
        let data = try ProviderFixture.data("ChitChats", "malformed")
        let recorder = RequestRecorder()
        let httpClient = MockHTTPClient { request in
            await recorder.record(request)
            return (
                data,
                try testHTTPResponse(for: request, statusCode: 201)
            )
        }

        do {
            _ = try await makeProvider(httpClient: httpClient)
                .ratesWithWarning(for: testShipment())
            Issue.record("Expected malformed response failure")
        } catch let failure as ProviderFailure {
            #expect(failure.code == "malformed_response")
            #expect(!failure.message.contains("13.45"))
        }

        #expect(await recorder.snapshot().count == 1)
    }

    @Test("Preserves non-validation HTTP status categories")
    func mapsHTTPStatusFailure() async throws {
        let data = try ProviderFixture.data("ChitChats", "validation_error")
        let httpClient = MockHTTPClient { request in
            (
                data,
                try testHTTPResponse(for: request, statusCode: 503)
            )
        }

        do {
            _ = try await makeProvider(httpClient: httpClient)
                .ratesWithWarning(for: testShipment())
            Issue.record("Expected HTTP status failure")
        } catch let failure as ProviderFailure {
            #expect(failure.code == "http_503")
            #expect(failure.message.contains("503"))
        }
    }

    @Test("Attempts cleanup when a returned rate is incomplete")
    func cleansUpAfterRateMappingFailure() async throws {
        let creationData = try ProviderFixture.data("ChitChats", "partial")
        let deletionData = try ProviderFixture.data("ChitChats", "delete_success")
        let recorder = RequestRecorder()
        let httpClient = MockHTTPClient { request in
            await recorder.record(request)

            switch request.httpMethod {
            case "POST":
                return (
                    creationData,
                    try testHTTPResponse(for: request, statusCode: 201)
                )
            case "DELETE":
                return (
                    deletionData,
                    try testHTTPResponse(for: request, statusCode: 204)
                )
            default:
                throw ProviderTestError.unexpectedRequest
            }
        }

        do {
            _ = try await makeProvider(httpClient: httpClient)
                .ratesWithWarning(for: testShipment())
            Issue.record("Expected incomplete rate failure")
        } catch let failure as ProviderFailure {
            #expect(failure.code == "malformed_response")
        }

        let requests = await recorder.snapshot()
        #expect(requests.count == 2)
        #expect(requests.last?.httpMethod == "DELETE")
        #expect(requests.last?.url?.lastPathComponent == "shipment-partial")
    }

    @Test("Deletes an empty shipment response with a numeric identifier")
    func handlesEmptyRatesAndNumericIdentifier() async throws {
        let creationData = try ProviderFixture.data("ChitChats", "empty")
        let deletionData = try ProviderFixture.data("ChitChats", "delete_success")
        let recorder = RequestRecorder()
        let httpClient = MockHTTPClient { request in
            await recorder.record(request)
            let isDelete = request.httpMethod == "DELETE"
            return (
                isDelete ? deletionData : creationData,
                try testHTTPResponse(
                    for: request,
                    statusCode: isDelete ? 204 : 201
                )
            )
        }

        let response = try await makeProvider(httpClient: httpClient)
            .ratesWithWarning(for: testShipment())

        #expect(response.rates.isEmpty)
        #expect(response.warning == nil)
        let requests = await recorder.snapshot()
        #expect(requests.last?.url?.lastPathComponent == "789")
    }

    @Test("Maps transport failures safely")
    func mapsTransportFailureSafely() async {
        let httpClient = MockHTTPClient { _ in
            throw HTTPError.transport(underlying: URLError(.timedOut))
        }

        do {
            _ = try await makeProvider(httpClient: httpClient)
                .ratesWithWarning(for: testShipment())
            Issue.record("Expected transport failure")
        } catch let failure as ProviderFailure {
            #expect(failure.code == "transport")
            #expect(!failure.message.contains("synthetic-token"))
        } catch {
            Issue.record("Expected ProviderFailure")
        }
    }

    private func makeProvider(
        httpClient: any HTTPClient
    ) -> ChitChatsProvider {
        ChitChatsProvider(
            configuration: ChitChatsConfiguration(
                clientID: "client-123",
                accessToken: "synthetic-token",
                packageType: "parcel"
            ),
            httpClient: httpClient,
            baseURL: URL(string: "https://example.test/api/v1")!
        )
    }
}

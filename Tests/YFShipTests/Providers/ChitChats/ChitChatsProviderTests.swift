import Foundation
import Testing
@testable import YFShip

@Suite("Chit Chats provider")
struct ChitChatsProviderTests {
    @Test("Decodes the shipment envelope, maps rates, and deletes the temporary shipment")
    func performsTemporaryShipmentLifecycle() async throws {
        let creationData = try ProviderFixture.data("ChitChats", "create_success")
        let envelope = try #require(
            JSONSerialization.jsonObject(with: creationData) as? [String: Any]
        )
        let shipment = try #require(envelope["shipment"] as? [String: Any])
        #expect(envelope["id"] == nil)
        #expect(envelope["rates"] == nil)
        #expect(shipment["id"] as? String == "shipment-456")
        #expect((shipment["rates"] as? [[String: Any]])?.count == 5)
        let fixtureRates = try #require(shipment["rates"] as? [[String: Any]])
        for rate in fixtureRates {
            #expect(rate["currency"] == nil)
            #expect(rate["currency_code"] == nil)
            #expect(rate["tracking"] == nil)
            #expect(rate["trackable"] == nil)
        }
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
            rates.first { $0.serviceID == "chit_chats_select" }
        )
        #expect(tracked.total == Decimal(string: "6.77"))
        #expect(rates.allSatisfy { $0.currency == "CAD" })
        #expect(tracked.isTrackable == true)
        #expect(tracked.estimatedDeliveryBusinessDays == 2)
        #expect(RateEligibility.evaluate(tracked).eligible)

        let canadaTracked = try #require(
            rates.first { $0.serviceID == "chit_chats_canada_tracked" }
        )
        #expect(canadaTracked.total == Decimal(string: "12.36"))
        #expect(canadaTracked.isTrackable == true)
        #expect(canadaTracked.estimatedDeliveryBusinessDays == 8)

        let ranged = try #require(
            rates.first { $0.serviceID == "chitchats-slow" }
        )
        #expect(ranged.total == Decimal(string: "7.25"))
        #expect(ranged.estimatedDeliveryBusinessDays == 22)
        #expect(RateEligibility.evaluate(ranged).ineligibilityReasons == [.deliveryTooSlow])

        let boundary = try #require(
            rates.first { $0.serviceID == "chitchats-boundary" }
        )
        #expect(boundary.estimatedDeliveryBusinessDays == 20)
        #expect(RateEligibility.evaluate(boundary).eligible)

        let unknown = try #require(
            rates.first { $0.serviceID == "chitchats-unknown" }
        )
        #expect(unknown.isTrackable == nil)
        #expect(unknown.total == Decimal(string: "1.00"))
        #expect(unknown.estimatedDeliveryBusinessDays == 2)
        #expect(unknown.currency == "CAD")
        #expect(!RateEligibility.evaluate(unknown).eligible)
        #expect(RateEligibility.evaluate(unknown).ineligibilityReasons == [.unknownTracking])

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

        let requests = await recorder.snapshot()
        #expect(requests.count == 2)
        #expect(requests.last?.httpMethod == "DELETE")
        #expect(requests.last?.url?.lastPathComponent == "shipment-partial")
    }

    @Test("Returns usable rates with a cleanup warning")
    func returnsCleanupWarning() async throws {
        let creationData = try ProviderFixture.data("ChitChats", "create_success")
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
        let requests = await recorder.snapshot()
        #expect(requests.count == 2)
        #expect(requests.last?.httpMethod == "DELETE")
        #expect(requests.last?.url?.lastPathComponent == "shipment-456")
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

    @Test("Rejects a bare shipment response without the required envelope")
    func rejectsBareShipmentResponse() async throws {
        let creationData = try ProviderFixture.data("ChitChats", "create_success")
        let envelope = try #require(
            JSONSerialization.jsonObject(with: creationData) as? [String: Any]
        )
        let shipment = try #require(envelope["shipment"] as? [String: Any])
        let bareData = try JSONSerialization.data(withJSONObject: shipment)
        let recorder = RequestRecorder()
        let httpClient = MockHTTPClient { request in
            await recorder.record(request)
            return (
                bareData,
                try testHTTPResponse(for: request, statusCode: 201)
            )
        }

        do {
            _ = try await makeProvider(httpClient: httpClient)
                .ratesWithWarning(for: testShipment())
            Issue.record("Expected response without shipment envelope to fail")
        } catch let failure as ProviderFailure {
            #expect(failure.provider == .chitchats)
            #expect(failure.code == "malformed_response")
            #expect(
                failure.message == "Chit Chats returned an unreadable shipment response."
            )
        }

        let requests = await recorder.snapshot()
        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "POST")
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
        #expect(requests.count == 2)
        #expect(requests.last?.httpMethod == "DELETE")
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

    @Test("Live-shaped rates without currency produce an eligible selection")
    func selectsLiveShapedRate() async throws {
        let creationData = try ProviderFixture.data("ChitChats", "create_success")
        let recorder = RequestRecorder()
        let httpClient = MockHTTPClient { request in
            await recorder.record(request)
            let isDelete = request.httpMethod == "DELETE"
            return (
                isDelete ? Data() : creationData,
                try testHTTPResponse(for: request, statusCode: isDelete ? 204 : 201)
            )
        }

        let result = await RateEngine(providers: [makeProvider(httpClient: httpClient)])
            .rates(for: testShipment())

        #expect(result.status == .success)
        #expect(result.providerFailures.isEmpty)
        let selectedRate = try #require(result.selectedRate)
        #expect(selectedRate.serviceID == "chit_chats_select")
        #expect(selectedRate.currency == "CAD")
        #expect(selectedRate.total == Decimal(string: "6.77"))
        #expect(selectedRate.isTrackable == true)
        let requests = await recorder.snapshot()
        #expect(requests.count == 2)
        #expect(requests.last?.httpMethod == "DELETE")
        #expect(requests.last?.url?.lastPathComponent == "shipment-456")
    }

    @Test("Explicit currency fields retain precedence over the CAD fallback")
    func preservesExplicitCurrency() async throws {
        let cases: [([String: String], String)] = [
            ([:], "CAD"),
            (["currency": "USD"], "USD"),
            (["currency_code": "cad", "currency": "USD"], "cad"),
            (["currency_code": " ", "currency": "USD"], "USD"),
            (["currency_code": "", "currency": " "], "CAD")
        ]
        for (fields, expected) in cases {
            var rate: [String: Any] = [
                "postage_type": "synthetic-rate",
                "payment_amount": "10.00",
                "tracking_type_description": "Full tracking included",
                "delivery_time_description": "2 business days"
            ]
            for (key, value) in fields {
                rate[key] = value
            }
            let response = try await providerReturning(rate: rate).rates(for: testShipment())
            let mapped = try #require(response.first)
            #expect(mapped.currency == expected)
            if expected == "USD" {
                #expect(RateEligibility.evaluate(mapped).ineligibilityReasons == [.incompatibleCurrency])
            }
        }
    }

    @Test("Tracking booleans take precedence and descriptions handle positive, negative, and unknown evidence")
    func mapsTrackingEvidence() async throws {
        let cases: [([String: Any], Bool?)] = [
            (["tracking_type_description": "Full tracking included"], true),
            (["tracking_type_description": "TRACKING"], true),
            (["tracking_type_description": "No Tracking included"], false),
            (["tracking_type_description": "UNTRACKED"], false),
            (["tracking_type_description": "Without tracking"], false),
            (["tracking_type_description": "Delivery confirmation"], nil),
            (["tracking_type_description": ""], nil),
            ([:], nil),
            (["tracking": false, "trackable": true, "tracking_type_description": "Full tracking included"], false),
            (["tracking": true, "trackable": false, "tracking_type_description": "No tracking"], true),
            (["trackable": false, "tracking_type_description": "Full tracking included"], false),
            (["trackable": true, "tracking_type_description": "No tracking"], true)
        ]
        for (fields, expected) in cases {
            var rate = fields
            rate["postage_type"] = "synthetic-rate"
            rate["purchase_amount"] = "10.00"
            rate["delivery_time_description"] = "2 business days"
            let response = try await providerReturning(rate: rate).rates(for: testShipment())
            let mapped = try #require(response.first)
            #expect(mapped.isTrackable == expected)
            #expect(RateEligibility.evaluate(mapped).eligible == (expected == true))
        }
    }

    @Test("Missing cost or service identity still fails mapping and attempts cleanup")
    func requiresCostAndServiceIdentity() async throws {
        let cases: [[String: Any]] = [
            ["postage_type": "synthetic-rate"],
            ["payment_amount": "10.00"]
        ]
        for rate in cases {
            let recorder = RequestRecorder()
            let provider = try providerReturning(rate: rate, recorder: recorder)
            do {
                _ = try await provider.rates(for: testShipment())
                Issue.record("Expected missing cost or service identity to fail")
            } catch let failure as ProviderFailure {
                #expect(failure.code == "malformed_response")
                #expect(failure.message == "Chit Chats returned an incomplete rate.")
            }
            let requests = await recorder.snapshot()
            #expect(requests.count == 2)
            #expect(requests.last?.httpMethod == "DELETE")
            #expect(requests.last?.url?.lastPathComponent == "synthetic-shipment")
        }
    }

    private func providerReturning(
        rate: [String: Any],
        recorder: RequestRecorder = RequestRecorder()
    ) throws -> ChitChatsProvider {
        let data = try JSONSerialization.data(withJSONObject: [
            "shipment": ["id": "synthetic-shipment", "rates": [rate]]
        ])
        return makeProvider(httpClient: MockHTTPClient { request in
            await recorder.record(request)
            let isDelete = request.httpMethod == "DELETE"
            return (
                isDelete ? Data() : data,
                try testHTTPResponse(for: request, statusCode: isDelete ? 204 : 201)
            )
        })
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

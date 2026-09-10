import Foundation
import Testing
@testable import YFShip

@Suite("Stallion provider")
struct StallionProviderTests {
    @Test("Builds the rate request and maps all-in rates")
    func buildsRequestAndMapsRates() async throws {
        let responseData = try ProviderFixture.data("Stallion", "success")
        let recorder = RequestRecorder()
        let httpClient = MockHTTPClient { request in
            await recorder.record(request)
            return (
                responseData,
                try testHTTPResponse(for: request, statusCode: 200)
            )
        }
        let provider = StallionProvider(
            configuration: StallionConfiguration(
                accessToken: "synthetic-token"
            ),
            httpClient: httpClient,
            baseURL: URL(string: "https://example.test/api/v5")!
        )

        let response = try await provider.ratesWithWarning(for: testShipment())
        let rates = response.rates

        #expect(response.warning == nil)
        #expect(rates.count == 3)
        #expect(rates.map(\.serviceID) == ["200", "82", "81"])

        let tracked = try #require(
            rates.first { $0.serviceID == "200" }
        )
        #expect(tracked.serviceName == "Intelcom Standard")
        #expect(tracked.carrier == "Intelcom")
        #expect(tracked.currency == "CAD")
        #expect(tracked.total == Decimal(string: "7.13"))
        #expect(tracked.isTrackable == true)
        #expect(tracked.estimatedDeliveryBusinessDays == 1)
        #expect(tracked.costComponents?.base == Decimal(string: "6.31"))

        let expedited = try #require(
            rates.first { $0.serviceID == "82" }
        )
        #expect(expedited.total == Decimal(string: "7.24"))
        #expect(expedited.isTrackable == true)
        #expect(expedited.estimatedDeliveryBusinessDays == 2)

        let priority = try #require(
            rates.first { $0.serviceID == "81" }
        )
        #expect(priority.total == Decimal(string: "24.26"))
        #expect(priority.isTrackable == true)
        #expect(priority.estimatedDeliveryBusinessDays == 2)

        let requests = await recorder.snapshot()
        let request = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://example.test/api/v5/rates")
        #expect(
            request.value(forHTTPHeaderField: "Authorization")
                == "Bearer synthetic-token"
        )

        let bodyData = try #require(request.httpBody)
        let body = try #require(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        #expect(body["type"] as? String == "regular")
        #expect(body["timeout"] as? Int == 15)

        let packages = try #require(body["packages"] as? [[String: Any]])
        let package = try #require(packages.first)
        #expect(package["weight_unit"] as? String == "lbs")
        #expect(package["size_unit"] as? String == "in")

        let items = try #require(body["items"] as? [[String: Any]])
        let item = try #require(items.first)
        #expect(item["currency"] as? String == "CAD")
        #expect(item["customs_description"] as? String == "Synthetic accessory")
        #expect(item["country_of_origin"] as? String == "CA")
        #expect(item["hs_code"] as? String == "0000.00")

        let destination = try #require(body["to_address"] as? [String: Any])
        #expect(destination["country_code"] as? String == "US")
        #expect(destination["is_residential"] as? Bool == true)
    }

    @Test("Maps authentication failures without exposing response content")
    func mapsAuthenticationFailureSafely() async throws {
        let marker = "Synthetic authentication failure."
        let data = try ProviderFixture.data("Stallion", "auth_error")
        let provider = makeProvider(data: data, statusCode: 401)

        do {
            _ = try await provider.rates(for: testShipment())
            Issue.record("Expected authentication failure")
        } catch let failure as ProviderFailure {
            #expect(failure.provider == .stallion)
            #expect(failure.code == "authentication_failed")
            #expect(!failure.message.contains(marker))
        }
    }

    @Test("Maps validation failures safely")
    func mapsValidationFailureSafely() async throws {
        let marker = "Synthetic shipment validation failure."
        let data = try ProviderFixture.data("Stallion", "validation_error")
        let provider = makeProvider(data: data, statusCode: 422)

        do {
            _ = try await provider.rates(for: testShipment())
            Issue.record("Expected validation failure")
        } catch let failure as ProviderFailure {
            #expect(failure.code == "validation_failed")
            #expect(!failure.message.contains(marker))
        }
    }

    @Test("Rejects malformed JSON safely")
    func rejectsMalformedJSONSafely() async throws {
        let data = try ProviderFixture.data("Stallion", "malformed")
        let provider = makeProvider(data: data)

        do {
            _ = try await provider.rates(for: testShipment())
            Issue.record("Expected malformed response failure")
        } catch let failure as ProviderFailure {
            #expect(failure.code == "malformed_response")
            #expect(!failure.message.contains("12.34"))
        }
    }

    @Test("Preserves non-validation HTTP status categories")
    func mapsHTTPStatusFailure() async throws {
        let data = try ProviderFixture.data("Stallion", "validation_error")
        let provider = makeProvider(data: data, statusCode: 503)

        do {
            _ = try await provider.rates(for: testShipment())
            Issue.record("Expected HTTP status failure")
        } catch let failure as ProviderFailure {
            #expect(failure.code == "http_503")
            #expect(failure.message.contains("503"))
        }
    }

    @Test("Rejects an incomplete rate")
    func rejectsIncompleteRate() async throws {
        let data = try ProviderFixture.data("Stallion", "partial")
        let provider = makeProvider(data: data)

        do {
            _ = try await provider.rates(for: testShipment())
            Issue.record("Expected incomplete rate failure")
        } catch let failure as ProviderFailure {
            #expect(failure.code == "malformed_response")
        }
    }

    @Test("Returns an empty service list")
    func returnsEmptyRates() async throws {
        let data = try ProviderFixture.data("Stallion", "empty")
        let rates = try await makeProvider(data: data).rates(for: testShipment())

        #expect(rates.isEmpty)
    }

    @Test("Maps transport failures safely")
    func mapsTransportFailureSafely() async {
        let httpClient = MockHTTPClient { _ in
            throw HTTPError.transport(underlying: URLError(.timedOut))
        }
        let provider = StallionProvider(
            configuration: StallionConfiguration(
                accessToken: "synthetic-token"
            ),
            httpClient: httpClient
        )

        do {
            _ = try await provider.rates(for: testShipment())
            Issue.record("Expected transport failure")
        } catch let failure as ProviderFailure {
            #expect(failure.code == "transport")
            #expect(!failure.message.contains("synthetic-token"))
        } catch {
            Issue.record("Expected ProviderFailure")
        }
    }

    @Test("String service identifiers still map unchanged", arguments: ["200", "stallion-tracked-fast"])
    func mapsStringServiceIdentifier(identifier: String) async throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "data": [[
                "postage_type_id": identifier,
                "service_name": "Synthetic Service",
                "total": "12.34",
                "currency": "CAD"
            ]]
        ])
        let rates = try await makeProvider(data: data).rates(for: testShipment())
        let rate = try #require(rates.first)
        #expect(rate.serviceID == identifier)
        #expect(rate.total == Decimal(string: "12.34"))
    }

    @Test("Missing and null service identifiers remain optional", arguments: ["{}", "{\"postage_type_id\":null}"])
    func decodesOptionalServiceIdentifier(json: String) throws {
        let rate = try JSONDecoder().decode(StallionRate.self, from: Data(json.utf8))
        #expect(rate.postageTypeID == nil)
    }

    @Test("Unsupported and empty service identifiers fail decoding", arguments: ["true", "1.5", "{}", "[]", "\"\"", "\" \""])
    func rejectsInvalidServiceIdentifier(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(StallionServiceID.self, from: Data(json.utf8))
        }
    }

    @Test("Preserves untracked, delivery-boundary, and unknown evidence mapping")
    func preservesEligibilityEvidence() async throws {
        let data = Data(#"{"data":[{"postage_type_id":1,"service_name":"Untracked","trackable":false,"total":8.25,"currency":"CAD","estimated_delivery_days":4},{"postage_type_id":2,"service_name":"Slow","trackable":true,"total":"7.00","currency":"CAD","estimated_delivery_days":21},{"postage_type_id":3,"service_name":"Boundary","trackable":true,"total":"14.00","currency":"CAD","estimated_delivery_days":20},{"postage_type_id":4,"service_name":"Unknown","total":"15.00","currency":"CAD"}]}"#.utf8)
        let rates = try await makeProvider(data: data).rates(for: testShipment())
        #expect(rates.count == 4)
        let untracked = try #require(rates.first { $0.serviceID == "1" })
        #expect(untracked.total == Decimal(string: "8.25"))
        #expect(untracked.isTrackable == false)
        #expect(untracked.estimatedDeliveryBusinessDays == 4)
        let slow = try #require(rates.first { $0.serviceID == "2" })
        #expect(slow.isTrackable == true)
        #expect(slow.estimatedDeliveryBusinessDays == 21)
        let boundary = try #require(rates.first { $0.serviceID == "3" })
        #expect(boundary.isTrackable == true)
        #expect(boundary.estimatedDeliveryBusinessDays == 20)
        let unknown = try #require(rates.first { $0.serviceID == "4" })
        #expect(unknown.isTrackable == nil)
        #expect(unknown.estimatedDeliveryBusinessDays == nil)
    }

    private func makeProvider(
        data: Data,
        statusCode: Int = 200
    ) -> StallionProvider {
        StallionProvider(
            configuration: StallionConfiguration(
                accessToken: "synthetic-token"
            ),
            httpClient: MockHTTPClient { request in
                (
                    data,
                    try testHTTPResponse(for: request, statusCode: statusCode)
                )
            },
            baseURL: URL(string: "https://example.test/api/v5")!
        )
    }
}

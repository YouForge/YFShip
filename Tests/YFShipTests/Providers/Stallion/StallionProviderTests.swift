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
        #expect(rates.count == 5)

        let tracked = try #require(
            rates.first { $0.serviceID == "stallion-tracked-fast" }
        )
        #expect(tracked.total == Decimal(string: "12.34"))
        #expect(tracked.isTrackable == true)
        #expect(tracked.estimatedDeliveryBusinessDays == 5)
        #expect(tracked.costComponents?.base == Decimal(string: "10.00"))

        let numeric = try #require(
            rates.first { $0.serviceID == "stallion-untracked" }
        )
        #expect(numeric.total == Decimal(string: "8.25"))
        #expect(numeric.isTrackable == false)

        let boundary = try #require(
            rates.first { $0.serviceID == "stallion-boundary" }
        )
        #expect(boundary.estimatedDeliveryBusinessDays == 20)

        let unknown = try #require(
            rates.first { $0.serviceID == "stallion-unknown" }
        )
        #expect(unknown.isTrackable == nil)
        #expect(unknown.estimatedDeliveryBusinessDays == nil)

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

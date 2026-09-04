import Testing
@testable import YFShip

@Suite("Canonical benchmark destinations")
struct BenchmarkDestinationTests {
    @Test("Contains the locked v1 population")
    func hasCanonicalPopulation() throws {
        let destinations = try BenchmarkDestinationLoader.load()

        #expect(destinations.count == 63)
        #expect(destinations.count { $0.countryCode == "CA" } == 12)
        #expect(destinations.count { $0.countryCode == "US" } == 51)
        #expect(Set(destinations.map(\.id)).count == destinations.count)
        #expect(destinations.allSatisfy { $0.weight == 1.0 })
    }

    @Test("Every destination has required address data")
    func hasRequiredAddressData() throws {
        let destinations = try BenchmarkDestinationLoader.load()

        #expect(destinations.allSatisfy { destination in
            [
                destination.id,
                destination.countryCode,
                destination.country,
                destination.regionCode,
                destination.region,
                destination.city,
                destination.address1,
                destination.postalCode
            ].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        })
    }

    @Test("Benchmark addresses use the benign recipient name")
    func usesBenchmarkRecipientName() throws {
        let destination = try #require(BenchmarkDestinationLoader.load().first)

        #expect(destination.shippingAddress.name == "YouForge Benchmark")
        #expect(destination.shippingAddress.isResidential)
    }
}

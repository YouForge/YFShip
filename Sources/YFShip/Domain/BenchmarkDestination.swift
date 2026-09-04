struct BenchmarkDestination: Codable, Sendable, Equatable {
    let id: String
    let weight: Double
    let countryCode: String
    let country: String
    let regionCode: String
    let region: String
    let city: String
    let address1: String
    let postalCode: String

    var shippingAddress: Address {
        Address(
            name: "YouForge Benchmark",
            company: nil,
            address1: address1,
            address2: nil,
            city: city,
            regionCode: regionCode,
            postalCode: postalCode,
            countryCode: countryCode,
            isResidential: true,
            email: nil,
            phone: nil
        )
    }
}

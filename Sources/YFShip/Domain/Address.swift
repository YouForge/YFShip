struct Address: Codable, Sendable, Equatable {
    let name: String?
    let company: String?
    let address1: String
    let address2: String?
    let city: String
    let regionCode: String
    let postalCode: String
    let countryCode: String
    let isResidential: Bool
    let email: String?
    let phone: String?
}

struct ShippingPackage: Codable, Sendable, Equatable {
    let weightLb: Double
    let lengthIn: Double
    let widthIn: Double
    let heightIn: Double
}

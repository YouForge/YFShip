struct Shipment: Codable, Sendable, Equatable {
    let origin: Address
    let destination: Address
    let package: ShippingPackage
    let items: [ShipmentItem]
}

protocol ShippingProvider: Sendable {
    var id: ProviderID { get }

    func rates(for shipment: Shipment) async throws -> [ShippingRate]
}

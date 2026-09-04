struct ProviderRatesResponse: Sendable, Equatable {
    let rates: [ShippingRate]
    let warning: ProviderWarning?
}

protocol ShippingProvider: Sendable {
    var id: ProviderID { get }

    func rates(for shipment: Shipment) async throws -> [ShippingRate]
    // This keeps cleanup warnings attached to their request instead of shared mutable state.
    func ratesWithWarning(for shipment: Shipment) async throws -> ProviderRatesResponse
}

extension ShippingProvider {
    func ratesWithWarning(for shipment: Shipment) async throws -> ProviderRatesResponse {
        ProviderRatesResponse(
            rates: try await rates(for: shipment),
            warning: nil
        )
    }
}

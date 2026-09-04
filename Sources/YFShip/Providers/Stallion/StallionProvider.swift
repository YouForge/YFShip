import Foundation

struct StallionProvider: ShippingProvider {
    let id: ProviderID = .stallion

    private let client: StallionClient

    init(
        configuration: StallionConfiguration,
        httpClient: any HTTPClient,
        baseURL: URL = StallionClient.productionBaseURL
    ) {
        client = StallionClient(
            configuration: configuration,
            httpClient: httpClient,
            baseURL: baseURL
        )
    }

    func rates(for shipment: Shipment) async throws -> [ShippingRate] {
        let response = try await client.fetchRates(for: shipment)
        return try response.data.map(mapRate)
    }

    private func mapRate(_ rate: StallionRate) throws -> ShippingRate {
        guard let total = rate.total?.value,
              let currency = rate.currency?.nonEmpty,
              let serviceName = rate.serviceName?.nonEmpty
                ?? rate.service?.nonEmpty else {
            throw ProviderFailure(
                provider: .stallion,
                code: "malformed_response",
                message: "Stallion returned an incomplete rate."
            )
        }

        let costComponents: CostComponents?
        if let base = rate.baseRate?.value {
            costComponents = CostComponents(
                base: base,
                tax: nil,
                mandatoryFees: nil,
                duty: nil
            )
        } else {
            costComponents = nil
        }

        return ShippingRate(
            provider: .stallion,
            carrier: rate.carrier?.nonEmpty,
            serviceID: rate.postageTypeID?.nonEmpty,
            serviceName: serviceName,
            total: total,
            currency: currency,
            isTrackable: rate.trackable,
            estimatedDeliveryBusinessDays: rate.estimatedDeliveryDays,
            costComponents: costComponents
        )
    }
}

private extension String {
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

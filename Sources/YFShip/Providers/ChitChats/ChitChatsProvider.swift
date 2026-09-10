import Foundation

struct ChitChatsProvider: ShippingProvider {
    let id: ProviderID = .chitchats

    private let client: ChitChatsClient

    init(
        configuration: ChitChatsConfiguration,
        httpClient: any HTTPClient,
        baseURL: URL = ChitChatsClient.productionBaseURL
    ) {
        client = ChitChatsClient(
            configuration: configuration,
            httpClient: httpClient,
            baseURL: baseURL
        )
    }

    func rates(for shipment: Shipment) async throws -> [ShippingRate] {
        try await ratesWithWarning(for: shipment).rates
    }

    func ratesWithWarning(
        for shipment: Shipment
    ) async throws -> ProviderRatesResponse {
        let response = try await client.createShipment(for: shipment)

        let mappedRates: Result<[ShippingRate], ProviderFailure>
        do {
            mappedRates = .success(try response.rates.map(mapRate))
        } catch let failure as ProviderFailure {
            mappedRates = .failure(failure)
        } catch {
            mappedRates = .failure(Self.malformedRateFailure)
        }

        let cleanupFailure: ProviderFailure?
        do {
            try await client.deleteShipment(id: response.id.value)
            cleanupFailure = nil
        } catch let failure as ProviderFailure {
            cleanupFailure = failure
        } catch {
            cleanupFailure = ProviderFailure(
                provider: .chitchats,
                code: "cleanup_failed",
                message: "Chit Chats temporary shipment cleanup failed."
            )
        }

        switch mappedRates {
        case let .success(rates):
            return ProviderRatesResponse(
                rates: rates,
                warning: cleanupFailure.map { _ in
                    ProviderWarning(
                        code: "cleanup_failed",
                        message: "Chit Chats temporary shipment cleanup failed."
                    )
                }
            )
        case let .failure(mappingFailure):
            if cleanupFailure != nil {
                throw ProviderFailure(
                    provider: .chitchats,
                    code: "malformed_response_cleanup_failed",
                    message: "Chit Chats returned an incomplete rate and temporary shipment cleanup also failed."
                )
            }
            throw mappingFailure
        }
    }

    private func mapRate(_ rate: ChitChatsRate) throws -> ShippingRate {
        guard let total = (rate.paymentAmount ?? rate.purchaseAmount)?.value,
              let serviceName = rate.postageDescription?.nonEmpty
                ?? rate.postageType?.nonEmpty else {
            throw Self.malformedRateFailure
        }

        // Chit Chats' Canadian rate API omits currency on CAD account rates.
        let currency = rate.currencyCode?.nonEmpty ?? rate.currency?.nonEmpty ?? "CAD"

        return ShippingRate(
            provider: .chitchats,
            carrier: rate.carrier?.nonEmpty,
            serviceID: rate.postageType?.nonEmpty,
            serviceName: serviceName,
            total: total,
            currency: currency,
            isTrackable: trackingEvidence(for: rate),
            estimatedDeliveryBusinessDays: rate.normalizedDeliveryBusinessDays,
            costComponents: nil
        )
    }

    private func trackingEvidence(for rate: ChitChatsRate) -> Bool? {
        if let tracking = rate.tracking ?? rate.trackable {
            return tracking
        }
        guard let description = rate.trackingTypeDescription?.lowercased() else {
            return nil
        }
        if description.contains("no tracking")
            || description.contains("untracked")
            || description.contains("without tracking") {
            return false
        }
        return description.contains("tracking") ? true : nil
    }

    private static var malformedRateFailure: ProviderFailure {
        ProviderFailure(
            provider: .chitchats,
            code: "malformed_response",
            message: "Chit Chats returned an incomplete rate."
        )
    }
}

private extension String {
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

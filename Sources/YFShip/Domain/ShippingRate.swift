import Foundation

struct CostComponents: Codable, Sendable, Equatable {
    let base: Decimal?
    let tax: Decimal?
    let mandatoryFees: Decimal?
    let duty: Decimal?
}

struct ShippingRate: Codable, Sendable, Equatable {
    let provider: ProviderID
    let carrier: String?
    let serviceID: String?
    let serviceName: String
    let total: Decimal
    let currency: String
    // A missing value means the provider did not prove tracking, so the rate is ineligible.
    let isTrackable: Bool?
    let estimatedDeliveryBusinessDays: Int?
    let costComponents: CostComponents?
}

enum IneligibilityReason: String, Codable, Sendable, Equatable {
    case untracked
    case unknownTracking
    case deliveryTooSlow
    case unknownDeliveryEstimate
    case incompatibleCurrency
}

struct EvaluatedRate: Codable, Sendable, Equatable {
    let rate: ShippingRate
    let eligible: Bool
    let ineligibilityReasons: [IneligibilityReason]
}

struct ProviderWarning: Codable, Sendable, Equatable {
    let code: String
    let message: String
}

struct ProviderRateResult: Codable, Sendable, Equatable {
    let provider: ProviderID
    let evaluatedRates: [EvaluatedRate]
    let selectedRate: ShippingRate?
    let warning: ProviderWarning?
}

struct ProviderFailure: Error, Codable, Sendable, Equatable {
    let provider: ProviderID
    let code: String
    let message: String
}

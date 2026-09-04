import Foundation

struct RateEligibility {
    static let maximumDeliveryBusinessDays = 20

    static func evaluate(
        _ rate: ShippingRate,
        comparisonCurrency: String = "CAD"
    ) -> EvaluatedRate {
        var reasons: [IneligibilityReason] = []

        switch rate.isTrackable {
        case true:
            break
        case false:
            reasons.append(.untracked)
        case nil:
            reasons.append(.unknownTracking)
        }

        if let deliveryDays = rate.estimatedDeliveryBusinessDays {
            if deliveryDays > maximumDeliveryBusinessDays {
                reasons.append(.deliveryTooSlow)
            }
        } else {
            reasons.append(.unknownDeliveryEstimate)
        }

        if rate.currency.caseInsensitiveCompare(comparisonCurrency) != .orderedSame {
            reasons.append(.incompatibleCurrency)
        }

        return EvaluatedRate(
            rate: rate,
            eligible: reasons.isEmpty,
            ineligibilityReasons: reasons
        )
    }
}

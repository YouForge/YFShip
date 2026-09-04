import Foundation
import Testing
@testable import YFShip

@Suite("Rate eligibility")
struct RateEligibilityTests {
    @Test("Accepts tracked rates at 19 and 20 business days")
    func acceptsBoundaryRates() {
        for days in [19, 20] {
            let evaluated = RateEligibility.evaluate(makeRate(deliveryDays: days))

            #expect(evaluated.eligible)
            #expect(evaluated.ineligibilityReasons.isEmpty)
        }
    }

    @Test("Rejects delivery over 20 business days")
    func rejectsSlowDelivery() {
        let evaluated = RateEligibility.evaluate(makeRate(deliveryDays: 21))

        #expect(!evaluated.eligible)
        #expect(evaluated.ineligibilityReasons == [.deliveryTooSlow])
    }

    @Test("Rejects explicitly untracked rates")
    func rejectsUntrackedRate() {
        let evaluated = RateEligibility.evaluate(makeRate(isTrackable: false))

        #expect(!evaluated.eligible)
        #expect(evaluated.ineligibilityReasons == [.untracked])
    }

    @Test("Rejects rates with unknown tracking")
    func rejectsUnknownTracking() {
        let evaluated = RateEligibility.evaluate(makeRate(isTrackable: nil))

        #expect(!evaluated.eligible)
        #expect(evaluated.ineligibilityReasons == [.unknownTracking])
    }

    @Test("Rejects rates with no delivery estimate")
    func rejectsMissingEstimate() {
        let evaluated = RateEligibility.evaluate(makeRate(deliveryDays: nil))

        #expect(!evaluated.eligible)
        #expect(evaluated.ineligibilityReasons == [.unknownDeliveryEstimate])
    }

    @Test("Compares currency case-insensitively")
    func comparesCurrencyCaseInsensitively() {
        #expect(RateEligibility.evaluate(makeRate(currency: "cad")).eligible)

        let incompatible = RateEligibility.evaluate(makeRate(currency: "USD"))
        #expect(!incompatible.eligible)
        #expect(incompatible.ineligibilityReasons == [.incompatibleCurrency])
    }

    @Test("Returns every applicable rejection reason")
    func returnsAllReasons() {
        let evaluated = RateEligibility.evaluate(
            makeRate(
                isTrackable: nil,
                deliveryDays: nil,
                currency: "USD"
            )
        )

        #expect(
            evaluated.ineligibilityReasons == [
                .unknownTracking,
                .unknownDeliveryEstimate,
                .incompatibleCurrency
            ]
        )
    }

    @Test("A cheaper ineligible rate never beats an eligible rate")
    func ineligibleRateCannotWin() {
        let rates = [
            makeRate(
                serviceName: "Cheap Untracked",
                total: Decimal(string: "1.00")!,
                isTrackable: false
            ),
            makeRate(
                serviceName: "Eligible",
                total: Decimal(string: "9.00")!
            )
        ]

        let selected = rates
            .map { RateEligibility.evaluate($0) }
            .filter(\.eligible)
            .map(\.rate)
            .min { $0.total < $1.total }

        #expect(selected?.serviceName == "Eligible")
    }

    private func makeRate(
        serviceName: String = "Tracked Service",
        total: Decimal = Decimal(10),
        isTrackable: Bool? = true,
        deliveryDays: Int? = 20,
        currency: String = "CAD"
    ) -> ShippingRate {
        ShippingRate(
            provider: .stallion,
            carrier: "Example Carrier",
            serviceID: "service-id",
            serviceName: serviceName,
            total: total,
            currency: currency,
            isTrackable: isTrackable,
            estimatedDeliveryBusinessDays: deliveryDays,
            costComponents: nil
        )
    }
}

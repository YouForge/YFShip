import Foundation
import Testing
@testable import YFShip

@Suite("Human output")
struct HumanOutputTests {
    @Test("Compare output shows selection, unknowns, warnings, and failures")
    func compareSmokeTest() {
        let selectedRate = humanRate(
            provider: .stallion,
            serviceName: "Tracked Standard",
            total: 12,
            tracking: true,
            deliveryDays: 5
        )
        let unknownRate = humanRate(
            provider: .stallion,
            serviceName: "Mystery Service",
            total: 4,
            tracking: nil,
            deliveryDays: nil
        )
        let result = RateComparisonResult(
            status: .partialSuccess,
            providerOutcomes: [
                .success(
                    ProviderRateResult(
                        provider: .stallion,
                        evaluatedRates: [
                            EvaluatedRate(
                                rate: selectedRate,
                                eligible: true,
                                ineligibilityReasons: []
                            ),
                            EvaluatedRate(
                                rate: unknownRate,
                                eligible: false,
                                ineligibilityReasons: [
                                    .unknownTracking,
                                    .unknownDeliveryEstimate
                                ]
                            )
                        ],
                        selectedRate: selectedRate,
                        warning: ProviderWarning(
                            code: "cleanup_failed",
                            message: "Temporary cleanup failed."
                        )
                    )
                ),
                .failure(
                    ProviderFailure(
                        provider: .chitchats,
                        code: "transport",
                        message: "Chit Chats network request failed."
                    )
                )
            ],
            selectedRate: selectedRate
        )

        let output = HumanOutput.compare(result, shipment: testShipment())

        #expect(output.contains("Destination: 20 Destination Ave, Unit 2, Buffalo"))
        #expect(output.contains("Package: 0.5 lb; 6 × 4 × 1 in"))
        #expect(output.contains("Providers queried: Stallion, Chit Chats"))
        #expect(output.contains("Mystery Service\tUnknown\tUnknown"))
        #expect(output.contains("tracking unknown, delivery estimate unknown"))
        #expect(output.contains("Warning [Stallion] cleanup_failed"))
        #expect(output.contains("Failure [Chit Chats] transport"))
        #expect(output.contains("Selected: Stallion / Tracked Standard — CAD 12.00"))
    }

    @Test("Compare output states when no eligible option exists")
    func compareNoEligible() {
        let result = RateComparisonResult(
            status: .noEligibleOption,
            providerOutcomes: [],
            selectedRate: nil
        )

        let output = HumanOutput.compare(result, shipment: testShipment())

        #expect(output.contains("No eligible shipping option."))
    }

    @Test("Benchmark output reports coverage, warnings, and missing destination IDs")
    func benchmarkSmokeTest() {
        let rate = humanRate(
            provider: .chitchats,
            serviceName: "Tracked Parcel",
            total: 10,
            tracking: true,
            deliveryDays: 3
        )
        let result = BenchmarkResult(
            destinationCount: 3,
            providerResults: [
                ProviderBenchmarkResult(
                    provider: .chitchats,
                    totalDestinationCount: 3,
                    qualifyingDestinationCount: 1,
                    failedDestinationCount: 1,
                    noEligibleDestinationCount: 1,
                    destinationOutcomes: [
                        BenchmarkDestinationOutcome(
                            benchmarkID: "D1",
                            result: .selected(
                                rate,
                                warning: ProviderWarning(
                                    code: "cleanup_failed",
                                    message: "Temporary cleanup failed."
                                )
                            )
                        ),
                        BenchmarkDestinationOutcome(
                            benchmarkID: "D2",
                            result: .failure(
                                ProviderFailure(
                                    provider: .chitchats,
                                    code: "transport",
                                    message: "Request failed."
                                )
                            )
                        ),
                        BenchmarkDestinationOutcome(
                            benchmarkID: "D3",
                            result: .noEligible(warning: nil)
                        )
                    ],
                    average: BenchmarkAverage(amount: 10, currency: "CAD")
                )
            ]
        )

        let output = HumanOutput.benchmark(result)

        #expect(output.contains("Provider: Chit Chats"))
        #expect(output.contains("Qualifying destinations: 1 / 3"))
        #expect(output.contains("Average eligible shipping cost: CAD 10.00"))
        #expect(output.contains("Failed destinations: 1"))
        #expect(output.contains("No-eligible destinations: 1"))
        #expect(output.contains("Warning [D1] cleanup_failed"))
        #expect(output.contains("D2 — failed (transport)"))
        #expect(output.contains("D3 — no eligible rate"))
    }
}

private func humanRate(
    provider: ProviderID,
    serviceName: String,
    total: Decimal,
    tracking: Bool?,
    deliveryDays: Int?
) -> ShippingRate {
    ShippingRate(
        provider: provider,
        carrier: "Synthetic Carrier",
        serviceID: "synthetic-service",
        serviceName: serviceName,
        total: total,
        currency: "CAD",
        isTrackable: tracking,
        estimatedDeliveryBusinessDays: deliveryDays,
        costComponents: nil
    )
}

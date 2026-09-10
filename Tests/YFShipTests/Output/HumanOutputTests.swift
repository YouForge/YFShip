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
        #expect(output.contains("Mystery Service   Unknown   Unknown"))
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

    @Test("Compare aligns all six columns across providers and service lengths")
    func compareTableAlignment() throws {
        let rates = [
            humanRate(provider: .chitchats, serviceName: "Chit Chats U.S. Select",
                      total: Decimal(string: "22.37")!, tracking: true, deliveryDays: 8),
            humanRate(provider: .chitchats, serviceName: "Short",
                      total: Decimal(string: "6.77")!, tracking: false, deliveryDays: 8),
            humanRate(provider: .stallion, serviceName: "PostNL International Packet Tracked",
                      total: Decimal(string: "25.02")!, tracking: true, deliveryDays: 8)
        ]
        let result = RateComparisonResult(
            status: .success,
            providerOutcomes: [ProviderID.chitchats, .stallion].map { provider in
                .success(ProviderRateResult(
                    provider: provider,
                    evaluatedRates: rates.filter { $0.provider == provider }.map {
                        EvaluatedRate(rate: $0, eligible: $0.isTrackable == true,
                                      ineligibilityReasons: $0.isTrackable == true ? [] : [.untracked])
                    },
                    selectedRate: rates.first { $0.provider == provider },
                    warning: nil
                ))
            },
            selectedRate: rates[0]
        )
        let output = HumanOutput.compare(result, shipment: testShipment())
        let lines = Array(output.components(separatedBy: "\n").dropFirst(4).prefix(4))
        let cells = [
            ["Provider", "Service", "Tracking", "ETA", "Total", "Eligibility"],
            ["Chit Chats", "Chit Chats U.S. Select", "Yes", "8 days", "CAD 22.37", "Eligible"],
            ["Chit Chats", "Short", "No", "8 days", "CAD 6.77", "Ineligible (untracked)"],
            ["Stallion", "PostNL International Packet Tracked", "Yes", "8 days", "CAD 25.02", "Eligible"]
        ]
        let starts = [0, 12, 49, 59, 67, 78]
        #expect(lines.count == cells.count)
        for (line, fields) in zip(lines, cells) {
            #expect(!line.contains("\t"))
            for (column, field) in fields.enumerated() {
                let range = try #require(line.range(of: field))
                #expect(line.distance(from: line.startIndex, to: range.lowerBound) == starts[column])
                if column < fields.count - 1 {
                    let next = line.index(line.startIndex, offsetBy: starts[column + 1])
                    #expect(line[range.upperBound..<next].allSatisfy { $0 == " " })
                } else {
                    #expect(range.upperBound == line.endIndex)
                }
            }
        }
    }

    @Test("Compare preserves free-text lines and their order", arguments: [true, false])
    func compareNonTabularLines(emptyFirst: Bool) throws {
        let rate = humanRate(provider: .stallion, serviceName: "Standard",
                             total: 10, tracking: true, deliveryDays: 5)
        let warning = ProviderWarning(code: "cleanup_failed", message: "Cleanup failed.")
        let empty = ProviderRateOutcome.success(ProviderRateResult(
            provider: .chitchats, evaluatedRates: [], selectedRate: nil, warning: warning
        ))
        let populated = ProviderRateOutcome.success(ProviderRateResult(
            provider: .stallion,
            evaluatedRates: [EvaluatedRate(rate: rate, eligible: true, ineligibilityReasons: [])],
            selectedRate: rate, warning: warning
        ))
        let failure = ProviderRateOutcome.failure(ProviderFailure(
            provider: .stallion, code: "transport", message: "Request failed."
        ))
        let result = RateComparisonResult(
            status: .partialSuccess,
            providerOutcomes: emptyFirst ? [empty, failure, populated] : [populated, failure, empty],
            selectedRate: rate
        )
        let lines = HumanOutput.compare(result, shipment: testShipment()).components(separatedBy: "\n")
        let row = try #require(lines.first { $0.hasPrefix("Stallion  ") })
        let emptyLines = ["Chit Chats\tNo rates returned.", "Warning [Chit Chats] cleanup_failed: Cleanup failed."]
        let rateLines = [row, "Warning [Stallion] cleanup_failed: Cleanup failed."]
        let failureLines = ["Failure [Stallion] transport: Request failed."]
        let expected = emptyFirst
            ? emptyLines + failureLines + rateLines
            : rateLines + failureLines + emptyLines
        #expect(Array(lines.dropFirst(5).prefix(5)) == expected)
        #expect(lines[10].isEmpty)
    }

    @Test("Compare does not round individual rate totals", arguments: ["6.77", "6.777"])
    func comparePreservesRateTotal(amount: String) {
        let rate = humanRate(provider: .chitchats, serviceName: "Standard",
                             total: Decimal(string: amount)!, tracking: true, deliveryDays: 5)
        let result = RateComparisonResult(
            status: .success,
            providerOutcomes: [.success(ProviderRateResult(
                provider: .chitchats,
                evaluatedRates: [EvaluatedRate(rate: rate, eligible: true, ineligibilityReasons: [])],
                selectedRate: rate, warning: nil
            ))],
            selectedRate: rate
        )
        let lines = HumanOutput.compare(result, shipment: testShipment()).components(separatedBy: "\n")
        #expect(lines[5].contains("CAD \(amount)  Eligible"))
        #expect(lines.last?.hasSuffix("CAD \(amount)") == true)
    }

    @Test("Human benchmark rounds only the presented average to cents", arguments: [
        ("22.749909098098089", "22.75"),
        ("22.1728571428571428571428571428571428571", "22.17"),
        ("22.1", "22.10"),
        ("22", "22.00"),
        ("22.005", "22.01"),
        ("-22.005", "-22.01")
    ])
    func benchmarkAverageRounding(input: String, expected: String) {
        let amount = Decimal(string: input)!
        let average = BenchmarkAverage(amount: amount, currency: "CAD")
        let result = BenchmarkResult(destinationCount: 1, providerResults: [
            ProviderBenchmarkResult(
                provider: .chitchats, totalDestinationCount: 1,
                qualifyingDestinationCount: 1, failedDestinationCount: 0,
                noEligibleDestinationCount: 0, destinationOutcomes: [], average: average
            )
        ])
        let lines = HumanOutput.benchmark(result).components(separatedBy: "\n")
        #expect(lines[2] == "Average eligible shipping cost: CAD \(expected)")
        #expect(result.providerResults[0].average?.amount == amount)
        #expect(average.amount == amount)
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

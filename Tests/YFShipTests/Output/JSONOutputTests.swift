import Foundation
import Testing
@testable import YFShip

@Suite("JSON output contract")
struct JSONOutputTests {
    @Test("Compare success contract")
    func compareSuccess() throws {
        let selectedRate = outputRate(
            provider: .stallion,
            carrier: "Synthetic Carrier",
            serviceID: "tracked",
            serviceName: "Tracked",
            total: "12.3",
            tracking: true,
            deliveryDays: 6
        )
        let unknownRate = outputRate(
            provider: .stallion,
            carrier: nil,
            serviceID: nil,
            serviceName: "Unknown",
            total: "5",
            currency: "USD",
            tracking: nil,
            deliveryDays: nil
        )
        let result = RateComparisonResult(
            status: .success,
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
                                    .unknownDeliveryEstimate,
                                    .incompatibleCurrency
                                ]
                            )
                        ],
                        selectedRate: selectedRate,
                        warning: nil
                    )
                )
            ],
            selectedRate: selectedRate
        )

        let output = try JSONOutput.compare(result)

        let expected = #"{"command":"compare","providers":[{"provider":"stallion","rates":[{"carrier":"Synthetic Carrier","currency":"CAD","eligible":true,"estimatedDeliveryBusinessDays":6,"ineligibilityReasons":[],"serviceID":"tracked","serviceName":"Tracked","total":"12.30","tracking":true},{"carrier":null,"currency":"USD","eligible":false,"estimatedDeliveryBusinessDays":null,"ineligibilityReasons":["unknown_tracking","unknown_delivery_estimate","incompatible_currency"],"serviceID":null,"serviceName":"Unknown","total":"5.00","tracking":null}],"selectedRate":{"currency":"CAD","serviceID":"tracked","total":"12.30"},"status":"success"}],"schemaVersion":1,"selectedRate":{"currency":"CAD","provider":"stallion","serviceID":"tracked","serviceName":"Tracked","total":"12.30"},"status":"success"}"#
        #expect(output == expected)
    }

    @Test("Compare partial-success contract")
    func comparePartialSuccess() throws {
        let selectedRate = outputRate(
            provider: .stallion,
            serviceID: "standard",
            serviceName: "Standard",
            total: "10"
        )
        let warning = ProviderWarning(
            code: "cleanup_failed",
            message: "Temporary shipment cleanup failed."
        )
        let failure = ProviderFailure(
            provider: .chitchats,
            code: "authentication_failed",
            message: "Chit Chats authentication failed."
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
                            )
                        ],
                        selectedRate: selectedRate,
                        warning: warning
                    )
                ),
                .failure(failure)
            ],
            selectedRate: selectedRate
        )

        let output = try JSONOutput.compare(result)

        let expected = #"{"command":"compare","providers":[{"provider":"stallion","rates":[{"carrier":"Synthetic Carrier","currency":"CAD","eligible":true,"estimatedDeliveryBusinessDays":5,"ineligibilityReasons":[],"serviceID":"standard","serviceName":"Standard","total":"10.00","tracking":true}],"selectedRate":{"currency":"CAD","serviceID":"standard","total":"10.00"},"status":"success","warning":{"code":"cleanup_failed","message":"Temporary shipment cleanup failed."}},{"error":{"code":"authentication_failed","message":"Chit Chats authentication failed."},"provider":"chitchats","rates":[],"selectedRate":null,"status":"failed"}],"schemaVersion":1,"selectedRate":{"currency":"CAD","provider":"stallion","serviceID":"standard","serviceName":"Standard","total":"10.00"},"status":"partial_success"}"#
        #expect(output == expected)
    }

    @Test("Compare no-eligible contract")
    func compareNoEligible() throws {
        let result = RateComparisonResult(
            status: .noEligibleOption,
            providerOutcomes: [
                .success(
                    ProviderRateResult(
                        provider: .chitchats,
                        evaluatedRates: [],
                        selectedRate: nil,
                        warning: nil
                    )
                )
            ],
            selectedRate: nil
        )

        let output = try JSONOutput.compare(result)

        let expected = #"{"command":"compare","providers":[{"provider":"chitchats","rates":[],"selectedRate":null,"status":"success"}],"schemaVersion":1,"selectedRate":null,"status":"no_eligible_option"}"#
        #expect(output == expected)
    }

    @Test("Compare complete-failure contract")
    func compareCompleteFailure() throws {
        let result = RateComparisonResult(
            status: .completeProviderFailure,
            providerOutcomes: [
                .failure(
                    ProviderFailure(
                        provider: .stallion,
                        code: "transport",
                        message: "Stallion network request failed."
                    )
                )
            ],
            selectedRate: nil
        )

        let output = try JSONOutput.compare(result)

        let expected = #"{"command":"compare","providers":[{"error":{"code":"transport","message":"Stallion network request failed."},"provider":"stallion","rates":[],"selectedRate":null,"status":"failed"}],"schemaVersion":1,"selectedRate":null,"status":"complete_provider_failure"}"#
        #expect(output == expected)
    }

    @Test("Benchmark success contract")
    func benchmarkSuccess() throws {
        let rate = outputRate(
            provider: .stallion,
            serviceName: "Tracked",
            total: "10",
            deliveryDays: 3
        )
        let result = BenchmarkResult(
            destinationCount: 1,
            providerResults: [
                ProviderBenchmarkResult(
                    provider: .stallion,
                    totalDestinationCount: 1,
                    qualifyingDestinationCount: 1,
                    failedDestinationCount: 0,
                    noEligibleDestinationCount: 0,
                    destinationOutcomes: [
                        BenchmarkDestinationOutcome(
                            benchmarkID: "D1",
                            result: .selected(rate, warning: nil)
                        )
                    ],
                    average: BenchmarkAverage(amount: 10, currency: "CAD")
                )
            ]
        )

        let output = try JSONOutput.benchmark(result)

        let expected = #"{"command":"benchmark","destinationCount":1,"providers":[{"average":{"amount":"10.00","currency":"CAD"},"destinations":[{"benchmarkID":"D1","selectedRate":{"amount":"10.00","currency":"CAD","estimatedDeliveryBusinessDays":3,"serviceName":"Tracked","tracking":true},"status":"success"}],"failedDestinationCount":0,"noEligibleDestinationCount":0,"provider":"stallion","qualifyingDestinationCount":1,"warningCount":0}],"schemaVersion":1,"status":"success"}"#
        #expect(output == expected)
    }

    @Test("Benchmark failure contract")
    func benchmarkWithFailure() throws {
        let rate = outputRate(
            provider: .chitchats,
            serviceName: "Tracked Parcel",
            total: "12.34",
            deliveryDays: 4
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
                                    message: "Temporary shipment cleanup failed."
                                )
                            )
                        ),
                        BenchmarkDestinationOutcome(
                            benchmarkID: "D2",
                            result: .failure(
                                ProviderFailure(
                                    provider: .chitchats,
                                    code: "transport",
                                    message: "Chit Chats network request failed."
                                )
                            )
                        ),
                        BenchmarkDestinationOutcome(
                            benchmarkID: "D3",
                            result: .noEligible(warning: nil)
                        )
                    ],
                    average: BenchmarkAverage(amount: Decimal(string: "12.34")!, currency: "CAD")
                )
            ]
        )

        let output = try JSONOutput.benchmark(result)

        let expected = #"{"command":"benchmark","destinationCount":3,"providers":[{"average":{"amount":"12.34","currency":"CAD"},"destinations":[{"benchmarkID":"D1","selectedRate":{"amount":"12.34","currency":"CAD","estimatedDeliveryBusinessDays":4,"serviceName":"Tracked Parcel","tracking":true},"status":"success"},{"benchmarkID":"D2","error":{"code":"transport","message":"Chit Chats network request failed."},"selectedRate":null,"status":"failed"},{"benchmarkID":"D3","selectedRate":null,"status":"no_eligible"}],"failedDestinationCount":1,"noEligibleDestinationCount":1,"provider":"chitchats","qualifyingDestinationCount":1,"warningCount":1}],"schemaVersion":1,"status":"partial_success"}"#
        #expect(output == expected)
    }

    @Test("JSON benchmark rounds only the presented average to cents", arguments: [
        ("22.749909098098089", "22.75"),
        ("22.1728571428571428571428571428571428571", "22.17"),
        ("22.1", "22.10"),
        ("22", "22.00"),
        ("22.005", "22.01"),
        ("-22.005", "-22.01")
    ])
    func benchmarkAverageRounding(input: String, expected: String) throws {
        let amount = Decimal(string: input)!
        let average = BenchmarkAverage(amount: amount, currency: "CAD")
        let rate = outputRate(provider: .stallion, serviceName: "Standard", total: "6.777")
        let result = BenchmarkResult(destinationCount: 1, providerResults: [
            ProviderBenchmarkResult(
                provider: .stallion, totalDestinationCount: 1,
                qualifyingDestinationCount: 1, failedDestinationCount: 0,
                noEligibleDestinationCount: 0,
                destinationOutcomes: [BenchmarkDestinationOutcome(
                    benchmarkID: "D1", result: .selected(rate, warning: nil)
                )],
                average: average
            )
        ])
        let output = try JSONOutput.benchmark(result)
        let document = try #require(
            JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
        )
        let providers = try #require(document["providers"] as? [[String: Any]])
        let provider = try #require(providers.first)
        let encodedAverage = try #require(provider["average"] as? [String: String])
        #expect(encodedAverage == ["amount": expected, "currency": "CAD"])
        let destinations = try #require(provider["destinations"] as? [[String: Any]])
        let selectedRate = try #require(destinations.first?["selectedRate"] as? [String: Any])
        #expect(selectedRate["amount"] as? String == "6.777")
        #expect(result.providerResults[0].average?.amount == amount)
        #expect(average.amount == amount)
    }

    @Test("Money strings are POSIX, ungrouped, exact, and have at least two decimals")
    func moneyFormatting() throws {
        #expect(try OutputMoneyFormatter.string(0) == "0.00")
        #expect(try OutputMoneyFormatter.string(1) == "1.00")
        #expect(
            try OutputMoneyFormatter.string(Decimal(string: "1.2")!) == "1.20"
        )
        #expect(
            try OutputMoneyFormatter.string(Decimal(string: "1.234")!) == "1.234"
        )
        #expect(
            try OutputMoneyFormatter.string(Decimal(string: "0.001")!) == "0.001"
        )
        #expect(try OutputMoneyFormatter.string(1_234_567_890) == "1234567890.00")
    }
}

private func outputRate(
    provider: ProviderID,
    carrier: String? = "Synthetic Carrier",
    serviceID: String? = "tracked",
    serviceName: String,
    total: String,
    currency: String = "CAD",
    tracking: Bool? = true,
    deliveryDays: Int? = 5
) -> ShippingRate {
    ShippingRate(
        provider: provider,
        carrier: carrier,
        serviceID: serviceID,
        serviceName: serviceName,
        total: Decimal(string: total, locale: Locale(identifier: "en_US_POSIX"))!,
        currency: currency,
        isTrackable: tracking,
        estimatedDeliveryBusinessDays: deliveryDays,
        costComponents: nil
    )
}

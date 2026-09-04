import Foundation

enum HumanOutput {
    static func compare(
        _ result: RateComparisonResult,
        shipment: Shipment
    ) -> String {
        var lines = [
            "Destination: \(destinationDescription(shipment.destination))",
            "Package: \(measurement(shipment.package.weightLb)) lb; "
                + "\(measurement(shipment.package.lengthIn)) × "
                + "\(measurement(shipment.package.widthIn)) × "
                + "\(measurement(shipment.package.heightIn)) in",
            "Providers queried: "
                + result.providerOutcomes.map { $0.provider.displayName }.joined(separator: ", "),
            "",
            "Provider\tService\tTracking\tETA\tTotal\tEligibility"
        ]

        for outcome in result.providerOutcomes {
            switch outcome {
            case .success(let providerResult):
                if providerResult.evaluatedRates.isEmpty {
                    lines.append(
                        "\(providerResult.provider.displayName)\tNo rates returned."
                    )
                }

                for evaluatedRate in providerResult.evaluatedRates {
                    let rate = evaluatedRate.rate
                    let eligibility: String
                    if evaluatedRate.eligible {
                        eligibility = "Eligible"
                    } else {
                        let reasons = evaluatedRate.ineligibilityReasons
                            .map(humanReason)
                            .joined(separator: ", ")
                        eligibility = "Ineligible (\(reasons))"
                    }

                    lines.append(
                        [
                            providerResult.provider.displayName,
                            rate.serviceName,
                            trackingDescription(rate.isTrackable),
                            etaDescription(rate.estimatedDeliveryBusinessDays),
                            "\(rate.currency.uppercased()) \(money(rate.total))",
                            eligibility
                        ].joined(separator: "\t")
                    )
                }

                if let warning = providerResult.warning {
                    lines.append(
                        "Warning [\(providerResult.provider.displayName)] "
                            + "\(warning.code): \(warning.message)"
                    )
                }
            case .failure(let failure):
                lines.append(
                    "Failure [\(failure.provider.displayName)] "
                        + "\(failure.code): \(failure.message)"
                )
            }
        }

        lines.append("")
        if let selectedRate = result.selectedRate {
            lines.append(
                "Selected: \(selectedRate.provider.displayName) / "
                    + "\(selectedRate.serviceName) — "
                    + "\(selectedRate.currency.uppercased()) \(money(selectedRate.total))"
            )
        } else {
            lines.append("No eligible shipping option.")
        }

        return lines.joined(separator: "\n")
    }

    static func benchmark(_ result: BenchmarkResult) -> String {
        var sections: [String] = []

        for providerResult in result.providerResults {
            var lines = [
                "Provider: \(providerResult.provider.displayName)",
                "Qualifying destinations: "
                    + "\(providerResult.qualifyingDestinationCount) / \(result.destinationCount)",
                averageDescription(providerResult.average),
                "Failed destinations: \(providerResult.failedDestinationCount)",
                "No-eligible destinations: \(providerResult.noEligibleDestinationCount)"
            ]

            let warnings = warnings(in: providerResult.destinationOutcomes)
            lines.append("Cleanup warnings: \(warnings.count)")
            for warning in warnings {
                lines.append(
                    "Warning [\(warning.benchmarkID)] "
                        + "\(warning.warning.code): \(warning.warning.message)"
                )
            }

            let missingDestinations = providerResult.destinationOutcomes.compactMap {
                missingDestinationDescription($0)
            }
            if !missingDestinations.isEmpty {
                lines.append("Missing destinations:")
                lines.append(contentsOf: missingDestinations.map { "- \($0)" })
            }

            sections.append(lines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    private static func destinationDescription(_ address: Address) -> String {
        var components = [address.address1]
        if let address2 = address.address2 {
            components.append(address2)
        }
        components.append(address.city)
        components.append("\(address.regionCode) \(address.postalCode)")
        components.append(address.countryCode)
        return components.joined(separator: ", ")
    }

    private static func measurement(_ value: Double) -> String {
        String(
            format: "%g",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    private static func trackingDescription(_ tracking: Bool?) -> String {
        switch tracking {
        case true:
            "Yes"
        case false:
            "No"
        case nil:
            "Unknown"
        }
    }

    private static func etaDescription(_ days: Int?) -> String {
        guard let days else {
            return "Unknown"
        }
        return days == 1 ? "1 day" : "\(days) days"
    }

    private static func humanReason(_ reason: IneligibilityReason) -> String {
        switch reason {
        case .untracked:
            "untracked"
        case .unknownTracking:
            "tracking unknown"
        case .deliveryTooSlow:
            "delivery exceeds 20 business days"
        case .unknownDeliveryEstimate:
            "delivery estimate unknown"
        case .incompatibleCurrency:
            "incompatible currency"
        }
    }

    private static func averageDescription(_ average: BenchmarkAverage?) -> String {
        guard let average else {
            return "Average eligible shipping cost: Unavailable"
        }
        return "Average eligible shipping cost: "
            + "\(average.currency.uppercased()) \(money(average.amount))"
    }

    private static func warnings(
        in outcomes: [BenchmarkDestinationOutcome]
    ) -> [(benchmarkID: String, warning: ProviderWarning)] {
        outcomes.compactMap { outcome in
            let warning: ProviderWarning?
            switch outcome.result {
            case .selected(_, warning: let value),
                 .noEligible(warning: let value):
                warning = value
            case .failure:
                warning = nil
            }

            guard let warning else {
                return nil
            }
            return (outcome.benchmarkID, warning)
        }
    }

    private static func missingDestinationDescription(
        _ outcome: BenchmarkDestinationOutcome
    ) -> String? {
        switch outcome.result {
        case .selected:
            nil
        case .noEligible:
            "\(outcome.benchmarkID) — no eligible rate"
        case .failure(let failure):
            "\(outcome.benchmarkID) — failed (\(failure.code)): \(failure.message)"
        }
    }

    private static func money(_ amount: Decimal) -> String {
        (try? OutputMoneyFormatter.string(amount)) ?? "Unavailable"
    }
}

enum OutputMoneyFormatter {
    static func string(_ amount: Decimal) throws -> String {
        guard !amount.isNaN else {
            throw JSONOutputError.invalidMoney
        }

        var amount = amount
        var value = NSDecimalString(
            &amount,
            Locale(identifier: "en_US_POSIX")
        )

        if amount == .zero, value.hasPrefix("-") {
            value.removeFirst()
        }

        if let decimalSeparator = value.firstIndex(of: ".") {
            let fractionalCount = value.distance(
                from: value.index(after: decimalSeparator),
                to: value.endIndex
            )
            if fractionalCount == 0 {
                value.append("00")
            } else if fractionalCount == 1 {
                value.append("0")
            }
        } else {
            value.append(".00")
        }

        return value
    }
}

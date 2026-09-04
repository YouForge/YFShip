import Foundation

enum RateComparisonStatus: String, Codable, Sendable, Equatable {
    case success
    case partialSuccess = "partial_success"
    case noEligibleOption = "no_eligible_option"
    case completeProviderFailure = "complete_provider_failure"
}

enum ProviderRateOutcome: Sendable, Equatable {
    case success(ProviderRateResult)
    case failure(ProviderFailure)

    var provider: ProviderID {
        switch self {
        case .success(let result):
            result.provider
        case .failure(let failure):
            failure.provider
        }
    }
}

struct RateComparisonResult: Sendable, Equatable {
    let status: RateComparisonStatus
    let providerOutcomes: [ProviderRateOutcome]
    let selectedRate: ShippingRate?

    var providerResults: [ProviderRateResult] {
        providerOutcomes.compactMap { outcome in
            guard case .success(let result) = outcome else {
                return nil
            }
            return result
        }
    }

    var providerFailures: [ProviderFailure] {
        providerOutcomes.compactMap { outcome in
            guard case .failure(let failure) = outcome else {
                return nil
            }
            return failure
        }
    }
}

struct RateEngine: Sendable {
    let providers: [any ShippingProvider]

    func rates(for shipment: Shipment) async -> RateComparisonResult {
        let indexedOutcomes = await withTaskGroup(
            of: IndexedProviderOutcome.self,
            returning: [IndexedProviderOutcome].self
        ) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    let outcome: ProviderRateOutcome

                    do {
                        let response = try await provider.ratesWithWarning(for: shipment)
                        let evaluatedRates = response.rates.map {
                            RateEligibility.evaluate($0)
                        }
                        let selectedRate = evaluatedRates
                            .filter(\.eligible)
                            .map(\.rate)
                            .min(by: Self.ratePrecedes)

                        outcome = .success(
                            ProviderRateResult(
                                provider: provider.id,
                                evaluatedRates: evaluatedRates,
                                selectedRate: selectedRate,
                                warning: response.warning
                            )
                        )
                    } catch let failure as ProviderFailure {
                        outcome = .failure(failure)
                    } catch {
                        outcome = .failure(
                            ProviderFailure(
                                provider: provider.id,
                                code: "provider_request_failed",
                                message: "The provider request failed."
                            )
                        )
                    }

                    return IndexedProviderOutcome(index: index, outcome: outcome)
                }
            }

            var outcomes: [IndexedProviderOutcome] = []
            outcomes.reserveCapacity(providers.count)

            for await outcome in group {
                outcomes.append(outcome)
            }

            return outcomes
        }

        let providerOutcomes = indexedOutcomes
            .sorted { $0.index < $1.index }
            .map(\.outcome)
        let candidates = providerOutcomes.compactMap { outcome -> SelectedCandidate? in
            guard case .success(let result) = outcome,
                  let selectedRate = result.selectedRate else {
                return nil
            }
            return SelectedCandidate(provider: result.provider, rate: selectedRate)
        }
        let selectedRate = candidates.min(by: Self.candidatePrecedes)?.rate
        let successfulProviderCount = providerOutcomes.reduce(into: 0) { count, outcome in
            if case .success = outcome {
                count += 1
            }
        }
        let failedProviderCount = providerOutcomes.count - successfulProviderCount

        let status: RateComparisonStatus
        if selectedRate != nil {
            status = failedProviderCount == 0 ? .success : .partialSuccess
        } else if successfulProviderCount > 0 || providerOutcomes.isEmpty {
            status = .noEligibleOption
        } else {
            status = .completeProviderFailure
        }

        return RateComparisonResult(
            status: status,
            providerOutcomes: providerOutcomes,
            selectedRate: selectedRate
        )
    }

    private static func ratePrecedes(_ lhs: ShippingRate, _ rhs: ShippingRate) -> Bool {
        if lhs.total != rhs.total {
            return lhs.total < rhs.total
        }
        if lhs.serviceName != rhs.serviceName {
            return lhs.serviceName < rhs.serviceName
        }
        return (lhs.serviceID ?? "") < (rhs.serviceID ?? "")
    }

    private static func candidatePrecedes(
        _ lhs: SelectedCandidate,
        _ rhs: SelectedCandidate
    ) -> Bool {
        if lhs.rate.total != rhs.rate.total {
            return lhs.rate.total < rhs.rate.total
        }
        if lhs.provider.rawValue != rhs.provider.rawValue {
            return lhs.provider.rawValue < rhs.provider.rawValue
        }
        return ratePrecedes(lhs.rate, rhs.rate)
    }
}

private struct IndexedProviderOutcome: Sendable {
    let index: Int
    let outcome: ProviderRateOutcome
}

private struct SelectedCandidate: Sendable {
    let provider: ProviderID
    let rate: ShippingRate
}

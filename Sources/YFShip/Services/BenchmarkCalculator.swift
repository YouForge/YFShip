import Foundation

struct BenchmarkAverage: Codable, Sendable, Equatable {
    let amount: Decimal
    let currency: String
}

enum BenchmarkDestinationResult: Sendable, Equatable {
    case selected(ShippingRate, warning: ProviderWarning?)
    case noEligible(warning: ProviderWarning?)
    case failure(ProviderFailure)
}

struct BenchmarkDestinationOutcome: Sendable, Equatable {
    let benchmarkID: String
    let result: BenchmarkDestinationResult
}

struct ProviderBenchmarkResult: Sendable, Equatable {
    let provider: ProviderID
    let totalDestinationCount: Int
    let qualifyingDestinationCount: Int
    let failedDestinationCount: Int
    let noEligibleDestinationCount: Int
    let destinationOutcomes: [BenchmarkDestinationOutcome]
    let average: BenchmarkAverage?
}

struct BenchmarkResult: Sendable, Equatable {
    let destinationCount: Int
    let providerResults: [ProviderBenchmarkResult]
}

struct BenchmarkCalculator: Sendable {
    static let maximumConcurrentDestinations = 5

    let providers: [any ShippingProvider]

    func calculate(
        origin: Address,
        package: ShippingPackage,
        items: [ShipmentItem],
        destinations: [BenchmarkDestination]
    ) async -> BenchmarkResult {
        let rateEngine = RateEngine(providers: providers)
        let destinationEvaluations = await evaluateDestinations(
            origin: origin,
            package: package,
            items: items,
            destinations: destinations,
            rateEngine: rateEngine
        )

        let providerResults = providers.enumerated().map { providerIndex, provider in
            aggregate(
                provider: provider.id,
                providerIndex: providerIndex,
                destinationEvaluations: destinationEvaluations
            )
        }

        return BenchmarkResult(
            destinationCount: destinations.count,
            providerResults: providerResults
        )
    }

    private func evaluateDestinations(
        origin: Address,
        package: ShippingPackage,
        items: [ShipmentItem],
        destinations: [BenchmarkDestination],
        rateEngine: RateEngine
    ) async -> [IndexedDestinationEvaluation] {
        await withTaskGroup(
            of: IndexedDestinationEvaluation.self,
            returning: [IndexedDestinationEvaluation].self
        ) { group in
            var nextDestinationIndex = 0
            let initialCount = min(
                Self.maximumConcurrentDestinations,
                destinations.count
            )

            while nextDestinationIndex < initialCount {
                addDestinationTask(
                    at: nextDestinationIndex,
                    origin: origin,
                    package: package,
                    items: items,
                    destinations: destinations,
                    rateEngine: rateEngine,
                    to: &group
                )
                nextDestinationIndex += 1
            }

            var evaluations: [IndexedDestinationEvaluation] = []
            evaluations.reserveCapacity(destinations.count)

            while let evaluation = await group.next() {
                evaluations.append(evaluation)

                if nextDestinationIndex < destinations.count {
                    addDestinationTask(
                        at: nextDestinationIndex,
                        origin: origin,
                        package: package,
                        items: items,
                        destinations: destinations,
                        rateEngine: rateEngine,
                        to: &group
                    )
                    nextDestinationIndex += 1
                }
            }

            return evaluations.sorted { $0.index < $1.index }
        }
    }

    private func addDestinationTask(
        at index: Int,
        origin: Address,
        package: ShippingPackage,
        items: [ShipmentItem],
        destinations: [BenchmarkDestination],
        rateEngine: RateEngine,
        to group: inout TaskGroup<IndexedDestinationEvaluation>
    ) {
        let destination = destinations[index]
        group.addTask {
            let shipment = Shipment(
                origin: origin,
                destination: destination.shippingAddress,
                package: package,
                items: items
            )
            let result = await rateEngine.rates(for: shipment)
            return IndexedDestinationEvaluation(
                index: index,
                benchmarkID: destination.id,
                comparison: result
            )
        }
    }

    private func aggregate(
        provider: ProviderID,
        providerIndex: Int,
        destinationEvaluations: [IndexedDestinationEvaluation]
    ) -> ProviderBenchmarkResult {
        var total = Decimal.zero
        var qualifyingCount = 0
        var failedCount = 0
        var noEligibleCount = 0
        var outcomes: [BenchmarkDestinationOutcome] = []
        outcomes.reserveCapacity(destinationEvaluations.count)

        for evaluation in destinationEvaluations {
            let result: BenchmarkDestinationResult

            switch evaluation.comparison.providerOutcomes[providerIndex] {
            case .success(let providerResult):
                if let selectedRate = providerResult.selectedRate {
                    total += selectedRate.total
                    qualifyingCount += 1
                    result = .selected(
                        selectedRate,
                        warning: providerResult.warning
                    )
                } else {
                    noEligibleCount += 1
                    result = .noEligible(warning: providerResult.warning)
                }
            case .failure(let failure):
                failedCount += 1
                result = .failure(failure)
            }

            outcomes.append(
                BenchmarkDestinationOutcome(
                    benchmarkID: evaluation.benchmarkID,
                    result: result
                )
            )
        }

        let average: BenchmarkAverage?
        if qualifyingCount > 0 {
            average = BenchmarkAverage(
                amount: total / Decimal(qualifyingCount),
                currency: "CAD"
            )
        } else {
            average = nil
        }

        return ProviderBenchmarkResult(
            provider: provider,
            totalDestinationCount: destinationEvaluations.count,
            qualifyingDestinationCount: qualifyingCount,
            failedDestinationCount: failedCount,
            noEligibleDestinationCount: noEligibleCount,
            destinationOutcomes: outcomes,
            average: average
        )
    }
}

private struct IndexedDestinationEvaluation: Sendable {
    let index: Int
    let benchmarkID: String
    let comparison: RateComparisonResult
}

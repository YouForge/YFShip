import Foundation
import Testing
@testable import YFShip

@Suite("Benchmark calculator")
struct BenchmarkCalculatorTests {
    @Test("Calculates an exact arithmetic mean from representative rates")
    func calculatesArithmeticMean() async {
        let destinations = benchmarkDestinations(count: 3)
        let totals = ["P0": Decimal(10), "P1": Decimal(20), "P2": Decimal(30)]
        let provider = StubShippingProvider(id: .stallion) { shipment in
            let selectedRate = stubRate(
                provider: .stallion,
                total: totals[shipment.destination.postalCode]!
            )
            let rates: [ShippingRate]
            if shipment.destination.postalCode == "P0" {
                rates = [
                    stubRate(
                        provider: .stallion,
                        serviceName: "Cheaper Untracked",
                        total: 1,
                        isTrackable: false
                    ),
                    stubRate(
                        provider: .stallion,
                        serviceName: "Expensive Tracked",
                        total: 100
                    ),
                    selectedRate
                ]
            } else {
                rates = [selectedRate]
            }
            return ProviderRatesResponse(
                rates: rates,
                warning: nil
            )
        }

        let result = await calculateBenchmark(
            providers: [provider],
            destinations: destinations
        )
        let aggregate = result.providerResults[0]

        #expect(result.destinationCount == 3)
        #expect(aggregate.totalDestinationCount == 3)
        #expect(aggregate.qualifyingDestinationCount == 3)
        #expect(aggregate.failedDestinationCount == 0)
        #expect(aggregate.noEligibleDestinationCount == 0)
        #expect(aggregate.average == BenchmarkAverage(amount: 20, currency: "CAD"))
        guard case .selected(let selectedRate, warning: nil) =
                aggregate.destinationOutcomes[0].result else {
            Issue.record("Expected a representative eligible rate")
            return
        }
        #expect(selectedRate.total == Decimal(10))
    }

    @Test("Failed destinations are reported and excluded from the denominator")
    func failuresAreExcludedFromMean() async {
        let destinations = benchmarkDestinations(count: 3)
        let failure = ProviderFailure(
            provider: .stallion,
            code: "destination_failed",
            message: "The destination request failed."
        )
        let provider = StubShippingProvider(id: .stallion) { shipment in
            switch shipment.destination.postalCode {
            case "P0":
                ProviderRatesResponse(
                    rates: [stubRate(provider: .stallion, total: 10)],
                    warning: nil
                )
            case "P1":
                throw failure
            default:
                ProviderRatesResponse(
                    rates: [stubRate(provider: .stallion, total: 20)],
                    warning: nil
                )
            }
        }

        let result = await calculateBenchmark(
            providers: [provider],
            destinations: destinations
        )
        let aggregate = result.providerResults[0]

        #expect(aggregate.qualifyingDestinationCount == 2)
        #expect(aggregate.failedDestinationCount == 1)
        #expect(aggregate.noEligibleDestinationCount == 0)
        #expect(aggregate.average?.amount == Decimal(15))
        #expect(
            aggregate.qualifyingDestinationCount
                + aggregate.failedDestinationCount
                + aggregate.noEligibleDestinationCount
                == aggregate.totalDestinationCount
        )
        #expect(aggregate.destinationOutcomes.count == aggregate.totalDestinationCount)
        #expect(aggregate.destinationOutcomes.map(\.benchmarkID) == ["D0", "D1", "D2"])

        guard case .failure(let recordedFailure) = aggregate.destinationOutcomes[1].result else {
            Issue.record("Expected the second destination to preserve its provider failure")
            return
        }
        #expect(recordedFailure == failure)
    }

    @Test("No-eligible destinations are distinct and a zero-qualifying average is nil")
    func zeroQualifyingHasNoAverage() async {
        let destinations = benchmarkDestinations(count: 3)
        let failure = ProviderFailure(
            provider: .chitchats,
            code: "request_failed",
            message: "The request failed."
        )
        let provider = StubShippingProvider(id: .chitchats) { shipment in
            if shipment.destination.postalCode == "P0" {
                throw failure
            }
            if shipment.destination.postalCode == "P1" {
                return ProviderRatesResponse(rates: [], warning: nil)
            }
            return ProviderRatesResponse(
                rates: [
                    stubRate(
                        provider: .chitchats,
                        total: 1,
                        isTrackable: false
                    )
                ],
                warning: nil
            )
        }

        let result = await calculateBenchmark(
            providers: [provider],
            destinations: destinations
        )
        let aggregate = result.providerResults[0]

        #expect(aggregate.qualifyingDestinationCount == 0)
        #expect(aggregate.failedDestinationCount == 1)
        #expect(aggregate.noEligibleDestinationCount == 2)
        #expect(aggregate.average == nil)

        guard case .noEligible = aggregate.destinationOutcomes[1].result else {
            Issue.record("Expected an explicit no-eligible destination outcome")
            return
        }
    }

    @Test("Each provider receives an independent deterministic aggregate")
    func aggregatesProvidersIndependently() async {
        let destinations = benchmarkDestinations(count: 2)
        let stallion = StubShippingProvider(id: .stallion) { shipment in
            let total = shipment.destination.postalCode == "P0" ? Decimal(8) : Decimal(12)
            return ProviderRatesResponse(
                rates: [stubRate(provider: .stallion, total: total)],
                warning: nil
            )
        }
        let chitChats = StubShippingProvider(id: .chitchats) { shipment in
            let total = shipment.destination.postalCode == "P0" ? Decimal(20) : Decimal(30)
            return ProviderRatesResponse(
                rates: [stubRate(provider: .chitchats, total: total)],
                warning: nil
            )
        }

        let result = await calculateBenchmark(
            providers: [stallion, chitChats],
            destinations: destinations
        )

        #expect(result.providerResults.map(\.provider) == [.stallion, .chitchats])
        #expect(result.providerResults[0].average?.amount == Decimal(10))
        #expect(result.providerResults[1].average?.amount == Decimal(25))
        #expect(result.providerResults.allSatisfy { $0.qualifyingDestinationCount == 2 })
    }

    @Test("Builds shipments from canonical destination mapping without changing the profile")
    func buildsExpectedShipment() async {
        let destination = benchmarkDestinations(count: 1)[0]
        let profile = testShipment()
        let recorder = ShipmentRecorder()
        let warning = ProviderWarning(
            code: "cleanup_failed",
            message: "Temporary shipment cleanup failed."
        )
        let provider = StubShippingProvider(id: .chitchats) { shipment in
            await recorder.record(shipment)
            return ProviderRatesResponse(
                rates: [stubRate(provider: .chitchats, total: 12)],
                warning: warning
            )
        }
        let calculator = BenchmarkCalculator(providers: [provider])

        let result = await calculator.calculate(
            origin: profile.origin,
            package: profile.package,
            items: profile.items,
            destinations: [destination]
        )
        let shipments = await recorder.snapshot()

        #expect(shipments.count == 1)
        #expect(shipments[0].origin == profile.origin)
        #expect(shipments[0].package == profile.package)
        #expect(shipments[0].items == profile.items)
        #expect(shipments[0].destination == destination.shippingAddress)
        #expect(shipments[0].destination.name == "YouForge Benchmark")
        #expect(result.providerResults[0].failedDestinationCount == 0)

        guard case .selected(_, warning: let recordedWarning) =
                result.providerResults[0].destinationOutcomes[0].result else {
            Issue.record("Expected a selected destination rate")
            return
        }
        #expect(recordedWarning == warning)
    }

    @Test("Runs no more than five destinations at once and preserves loaded order")
    func boundsDestinationConcurrency() async {
        let destinations = benchmarkDestinations(count: 13)
        let gate = ConcurrencyGate(
            expectedEntrants: BenchmarkCalculator.maximumConcurrentDestinations
        )
        let provider = StubShippingProvider(id: .stallion) { shipment in
            await gate.enterAndWait()
            await gate.leave()
            return ProviderRatesResponse(
                rates: [stubRate(provider: .stallion, total: 10)],
                warning: nil
            )
        }
        let watchdog = concurrencyWatchdog(for: gate)

        let result = await calculateBenchmark(
            providers: [provider],
            destinations: destinations
        )
        watchdog.cancel()
        await watchdog.value
        let maximumInFlight = await gate.maximumObserved()

        #expect(maximumInFlight <= BenchmarkCalculator.maximumConcurrentDestinations)
        #expect(maximumInFlight == 5)
        #expect(
            result.providerResults[0].destinationOutcomes.map(\.benchmarkID)
                == destinations.map(\.id)
        )
    }
}

actor ShipmentRecorder {
    private var shipments: [Shipment] = []

    func record(_ shipment: Shipment) {
        shipments.append(shipment)
    }

    func snapshot() -> [Shipment] {
        shipments
    }
}

private func calculateBenchmark(
    providers: [any ShippingProvider],
    destinations: [BenchmarkDestination]
) async -> BenchmarkResult {
    let profile = testShipment()
    return await BenchmarkCalculator(providers: providers).calculate(
        origin: profile.origin,
        package: profile.package,
        items: profile.items,
        destinations: destinations
    )
}

private func benchmarkDestinations(count: Int) -> [BenchmarkDestination] {
    (0..<count).map { index in
        BenchmarkDestination(
            id: "D\(index)",
            weight: 1,
            countryCode: "CA",
            country: "Canada",
            regionCode: "ON",
            region: "Ontario",
            city: "City \(index)",
            address1: "\(index + 1) Benchmark Street",
            postalCode: "P\(index)"
        )
    }
}

import Foundation
import Testing
@testable import YFShip

@Suite("Rate engine")
struct RateEngineTests {
    @Test("A provider success evaluates every rate and selects its cheapest eligible rate")
    func oneProviderSucceeds() async {
        let provider = StubShippingProvider(id: .stallion) { _ in
            ProviderRatesResponse(
                rates: [
                    stubRate(
                        provider: .stallion,
                        serviceName: "Untracked Economy",
                        total: 2,
                        isTrackable: false
                    ),
                    stubRate(
                        provider: .stallion,
                        serviceName: "Tracked Standard",
                        total: 8
                    ),
                    stubRate(
                        provider: .stallion,
                        serviceName: "Tracked Express",
                        total: 12
                    )
                ],
                warning: nil
            )
        }

        let result = await RateEngine(providers: [provider]).rates(for: testShipment())

        #expect(result.status == .success)
        #expect(result.selectedRate?.serviceName == "Tracked Standard")
        #expect(result.providerResults.count == 1)
        #expect(result.providerFailures.isEmpty)
        #expect(result.providerResults[0].evaluatedRates.count == 3)
        #expect(
            result.providerResults[0].evaluatedRates[0].ineligibilityReasons == [.untracked]
        )
    }

    @Test("Two providers are queried concurrently and the cheapest overall rate wins")
    func twoProvidersSucceedConcurrently() async {
        let gate = ConcurrencyGate(expectedEntrants: 2)
        let stallion = gatedProvider(
            id: .stallion,
            total: 9,
            gate: gate
        )
        let chitChats = gatedProvider(
            id: .chitchats,
            total: 7,
            gate: gate
        )
        let watchdog = concurrencyWatchdog(for: gate)

        let result = await RateEngine(providers: [stallion, chitChats])
            .rates(for: testShipment())
        watchdog.cancel()
        await watchdog.value
        let maximumInFlight = await gate.maximumObserved()

        #expect(result.status == .success)
        #expect(result.selectedRate?.provider == .chitchats)
        #expect(result.selectedRate?.total == Decimal(7))
        #expect(result.providerResults.map(\.provider) == [.stallion, .chitchats])
        #expect(maximumInFlight == 2)
    }

    @Test("A no-eligible provider does not suppress another provider's usable result")
    func noEligibleAndSuccessProducesWinner() async {
        let noEligible = StubShippingProvider(id: .stallion) { _ in
            ProviderRatesResponse(
                rates: [
                    stubRate(
                        provider: .stallion,
                        total: 1,
                        isTrackable: false
                    )
                ],
                warning: nil
            )
        }
        let eligible = StubShippingProvider(id: .chitchats) { _ in
            ProviderRatesResponse(
                rates: [stubRate(provider: .chitchats, total: 10)],
                warning: nil
            )
        }

        let result = await RateEngine(providers: [noEligible, eligible])
            .rates(for: testShipment())

        #expect(result.status == .success)
        #expect(result.selectedRate?.provider == .chitchats)
        #expect(result.providerResults.count == 2)
        #expect(result.providerResults[0].selectedRate == nil)
        #expect(result.providerFailures.isEmpty)
    }

    @Test("One provider failure is preserved alongside a usable winner")
    func partialSuccessPreservesFailure() async {
        let failure = ProviderFailure(
            provider: .chitchats,
            code: "authentication_failed",
            message: "Chit Chats authentication failed."
        )
        let failing = StubShippingProvider(id: .chitchats) { _ in
            throw failure
        }
        let succeeding = StubShippingProvider(id: .stallion) { _ in
            ProviderRatesResponse(
                rates: [stubRate(provider: .stallion, total: 11)],
                warning: nil
            )
        }

        let result = await RateEngine(providers: [failing, succeeding])
            .rates(for: testShipment())

        #expect(result.status == .partialSuccess)
        #expect(result.selectedRate?.provider == .stallion)
        #expect(result.providerFailures == [failure])
        #expect(result.providerResults.map(\.provider) == [.stallion])
    }

    @Test("An empty provider response is successful but has no eligible selection")
    func emptyResponseIsNotFailure() async {
        let provider = StubShippingProvider(id: .stallion) { _ in
            ProviderRatesResponse(rates: [], warning: nil)
        }

        let result = await RateEngine(providers: [provider]).rates(for: testShipment())

        #expect(result.status == .noEligibleOption)
        #expect(result.selectedRate == nil)
        #expect(result.providerResults.count == 1)
        #expect(result.providerResults[0].evaluatedRates.isEmpty)
        #expect(result.providerResults[0].selectedRate == nil)
        #expect(result.providerFailures.isEmpty)
    }

    @Test("No eligible rate across responding providers is explicit")
    func noProviderHasEligibleRate() async {
        let untracked = StubShippingProvider(id: .stallion) { _ in
            ProviderRatesResponse(
                rates: [
                    stubRate(
                        provider: .stallion,
                        total: 3,
                        isTrackable: false
                    )
                ],
                warning: nil
            )
        }
        let tooSlow = StubShippingProvider(id: .chitchats) { _ in
            ProviderRatesResponse(
                rates: [
                    stubRate(
                        provider: .chitchats,
                        total: 4,
                        deliveryDays: 21
                    )
                ],
                warning: nil
            )
        }

        let result = await RateEngine(providers: [untracked, tooSlow])
            .rates(for: testShipment())

        #expect(result.status == .noEligibleOption)
        #expect(result.selectedRate == nil)
        #expect(result.providerResults.count == 2)
        #expect(result.providerFailures.isEmpty)
    }

    @Test("A failure plus a responding provider with no eligible rate is no eligible option")
    func failureWithoutUsableResultIsNoEligible() async {
        let failure = ProviderFailure(
            provider: .stallion,
            code: "service_unavailable",
            message: "Stallion is unavailable."
        )
        let failing = StubShippingProvider(id: .stallion) { _ in
            throw failure
        }
        let responding = StubShippingProvider(id: .chitchats) { _ in
            ProviderRatesResponse(rates: [], warning: nil)
        }

        let result = await RateEngine(providers: [failing, responding])
            .rates(for: testShipment())

        #expect(result.status == .noEligibleOption)
        #expect(result.providerFailures == [failure])
        #expect(result.providerResults.count == 1)
    }

    @Test("All provider failures produce complete provider failure")
    func allProvidersFail() async {
        let stallionFailure = ProviderFailure(
            provider: .stallion,
            code: "stallion_failed",
            message: "Stallion failed."
        )
        let chitChatsFailure = ProviderFailure(
            provider: .chitchats,
            code: "chitchats_failed",
            message: "Chit Chats failed."
        )
        let stallion = StubShippingProvider(id: .stallion) { _ in
            throw stallionFailure
        }
        let chitChats = StubShippingProvider(id: .chitchats) { _ in
            throw chitChatsFailure
        }

        let result = await RateEngine(providers: [stallion, chitChats])
            .rates(for: testShipment())

        #expect(result.status == .completeProviderFailure)
        #expect(result.selectedRate == nil)
        #expect(result.providerResults.isEmpty)
        #expect(result.providerFailures == [stallionFailure, chitChatsFailure])
    }

    @Test("Provider cleanup warnings are carried without changing success status")
    func warningIsPropagated() async {
        let warning = ProviderWarning(
            code: "cleanup_failed",
            message: "Temporary shipment cleanup failed."
        )
        let provider = StubShippingProvider(id: .chitchats) { _ in
            ProviderRatesResponse(
                rates: [stubRate(provider: .chitchats, total: 10)],
                warning: warning
            )
        }

        let result = await RateEngine(providers: [provider]).rates(for: testShipment())

        #expect(result.status == .success)
        #expect(result.providerResults[0].warning == warning)
        #expect(result.providerFailures.isEmpty)
    }

    @Test("Equal totals use provider then service name for deterministic selection")
    func tiesAreDeterministic() async {
        let stallion = StubShippingProvider(id: .stallion) { _ in
            ProviderRatesResponse(
                rates: [stubRate(provider: .stallion, serviceName: "A Service", total: 10)],
                warning: nil
            )
        }
        let chitChats = StubShippingProvider(id: .chitchats) { _ in
            ProviderRatesResponse(
                rates: [
                    stubRate(provider: .chitchats, serviceName: "Zulu Service", total: 10),
                    stubRate(provider: .chitchats, serviceName: "Alpha Service", total: 10)
                ],
                warning: nil
            )
        }

        let result = await RateEngine(providers: [stallion, chitChats])
            .rates(for: testShipment())

        #expect(result.selectedRate?.provider == .chitchats)
        #expect(result.selectedRate?.serviceName == "Alpha Service")
        #expect(result.providerResults.map(\.provider) == [.stallion, .chitchats])
    }
}

struct StubShippingProvider: ShippingProvider {
    typealias Handler = @Sendable (Shipment) async throws -> ProviderRatesResponse

    let id: ProviderID
    let handler: Handler

    func rates(for shipment: Shipment) async throws -> [ShippingRate] {
        try await handler(shipment).rates
    }

    func ratesWithWarning(for shipment: Shipment) async throws -> ProviderRatesResponse {
        try await handler(shipment)
    }
}

actor ConcurrencyGate {
    private let expectedEntrants: Int
    private var current = 0
    private var maximum = 0
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(expectedEntrants: Int) {
        self.expectedEntrants = expectedEntrants
    }

    func enterAndWait() async {
        current += 1
        maximum = max(maximum, current)

        guard !isOpen else {
            return
        }

        if current >= expectedEntrants {
            open()
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func leave() {
        current -= 1
    }

    func maximumObserved() -> Int {
        maximum
    }

    func open() {
        guard !isOpen else {
            return
        }
        isOpen = true
        let currentWaiters = waiters
        waiters.removeAll()
        for waiter in currentWaiters {
            waiter.resume()
        }
    }
}

func stubRate(
    provider: ProviderID,
    serviceName: String = "Tracked Service",
    total: Decimal,
    isTrackable: Bool? = true,
    deliveryDays: Int? = 5,
    currency: String = "CAD"
) -> ShippingRate {
    ShippingRate(
        provider: provider,
        carrier: "Synthetic Carrier",
        serviceID: serviceName.lowercased().replacingOccurrences(of: " ", with: "-"),
        serviceName: serviceName,
        total: total,
        currency: currency,
        isTrackable: isTrackable,
        estimatedDeliveryBusinessDays: deliveryDays,
        costComponents: nil
    )
}

func concurrencyWatchdog(for gate: ConcurrencyGate) -> Task<Void, Never> {
    Task {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard !Task.isCancelled else {
            return
        }
        await gate.open()
    }
}

private func gatedProvider(
    id: ProviderID,
    total: Decimal,
    gate: ConcurrencyGate
) -> StubShippingProvider {
    StubShippingProvider(id: id) { _ in
        await gate.enterAndWait()
        await gate.leave()
        return ProviderRatesResponse(
            rates: [stubRate(provider: id, total: total)],
            warning: nil
        )
    }
}

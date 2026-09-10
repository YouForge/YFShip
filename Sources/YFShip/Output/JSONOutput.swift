import Foundation

enum JSONOutputError: Error, Equatable, Sendable {
    case invalidEncoding
    case invalidMoney
}

enum JSONOutput {
    static func compare(_ result: RateComparisonResult) throws -> String {
        try encode(CompareDocument(result: result))
    }

    static func benchmark(_ result: BenchmarkResult) throws -> String {
        try encode(BenchmarkDocument(result: result))
    }

    private static func encode<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard let output = String(data: data, encoding: .utf8) else {
            throw JSONOutputError.invalidEncoding
        }
        return output
    }
}

private enum JSONNullable<Value: Encodable>: Encodable {
    case value(Value)
    case null

    init(_ value: Value?) {
        if let value {
            self = .value(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

private struct ErrorDocument: Encodable {
    let code: String
    let message: String

    init(_ failure: ProviderFailure) {
        code = failure.code
        message = failure.message
    }
}

private struct WarningDocument: Encodable {
    let code: String
    let message: String

    init(_ warning: ProviderWarning) {
        code = warning.code
        message = warning.message
    }
}

private struct CompareDocument: Encodable {
    let schemaVersion = 1
    let command = "compare"
    let status: String
    let providers: [CompareProviderDocument]
    let selectedRate: JSONNullable<CompareSelectedRateDocument>

    init(result: RateComparisonResult) throws {
        status = result.status.rawValue
        providers = try result.providerOutcomes.map(CompareProviderDocument.init)
        selectedRate = JSONNullable(
            try result.selectedRate.map(CompareSelectedRateDocument.init)
        )
    }
}

private struct CompareProviderDocument: Encodable {
    let provider: String
    let status: String
    let rates: [CompareRateDocument]
    let selectedRate: JSONNullable<ProviderSelectedRateDocument>
    let error: ErrorDocument?
    let warning: WarningDocument?

    init(_ outcome: ProviderRateOutcome) throws {
        switch outcome {
        case .success(let result):
            provider = result.provider.rawValue
            status = "success"
            rates = try result.evaluatedRates.map(CompareRateDocument.init)
            selectedRate = JSONNullable(
                try result.selectedRate.map(ProviderSelectedRateDocument.init)
            )
            error = nil
            warning = result.warning.map(WarningDocument.init)
        case .failure(let failure):
            provider = failure.provider.rawValue
            status = "failed"
            rates = []
            selectedRate = .null
            error = ErrorDocument(failure)
            warning = nil
        }
    }
}

private struct CompareRateDocument: Encodable {
    let carrier: JSONNullable<String>
    let serviceID: JSONNullable<String>
    let serviceName: String
    let total: String
    let currency: String
    let tracking: JSONNullable<Bool>
    let estimatedDeliveryBusinessDays: JSONNullable<Int>
    let eligible: Bool
    let ineligibilityReasons: [String]

    init(_ evaluatedRate: EvaluatedRate) throws {
        let rate = evaluatedRate.rate
        carrier = JSONNullable(rate.carrier)
        serviceID = JSONNullable(rate.serviceID)
        serviceName = rate.serviceName
        total = try OutputMoneyFormatter.string(rate.total)
        currency = rate.currency
        tracking = JSONNullable(rate.isTrackable)
        estimatedDeliveryBusinessDays = JSONNullable(
            rate.estimatedDeliveryBusinessDays
        )
        eligible = evaluatedRate.eligible
        ineligibilityReasons = evaluatedRate.ineligibilityReasons.map(
            JSONIneligibilityReason.init
        ).map(\.rawValue)
    }
}

private struct ProviderSelectedRateDocument: Encodable {
    let serviceID: JSONNullable<String>
    let total: String
    let currency: String

    init(_ rate: ShippingRate) throws {
        serviceID = JSONNullable(rate.serviceID)
        total = try OutputMoneyFormatter.string(rate.total)
        currency = rate.currency
    }
}

private struct CompareSelectedRateDocument: Encodable {
    let provider: String
    let serviceID: JSONNullable<String>
    let serviceName: String
    let total: String
    let currency: String

    init(_ rate: ShippingRate) throws {
        provider = rate.provider.rawValue
        serviceID = JSONNullable(rate.serviceID)
        serviceName = rate.serviceName
        total = try OutputMoneyFormatter.string(rate.total)
        currency = rate.currency
    }
}

private enum JSONIneligibilityReason: String {
    case untracked
    case unknownTracking = "unknown_tracking"
    case deliveryTooSlow = "delivery_too_slow"
    case unknownDeliveryEstimate = "unknown_delivery_estimate"
    case incompatibleCurrency = "incompatible_currency"

    init(_ reason: IneligibilityReason) {
        switch reason {
        case .untracked:
            self = .untracked
        case .unknownTracking:
            self = .unknownTracking
        case .deliveryTooSlow:
            self = .deliveryTooSlow
        case .unknownDeliveryEstimate:
            self = .unknownDeliveryEstimate
        case .incompatibleCurrency:
            self = .incompatibleCurrency
        }
    }
}

private struct BenchmarkDocument: Encodable {
    let schemaVersion = 1
    let command = "benchmark"
    let status: String
    let destinationCount: Int
    let providers: [BenchmarkProviderDocument]

    init(result: BenchmarkResult) throws {
        status = result.commandStatus.rawValue
        destinationCount = result.destinationCount
        providers = try result.providerResults.map(BenchmarkProviderDocument.init)
    }
}

private struct BenchmarkProviderDocument: Encodable {
    let provider: String
    let qualifyingDestinationCount: Int
    let failedDestinationCount: Int
    let noEligibleDestinationCount: Int
    let average: JSONNullable<BenchmarkAverageDocument>
    let warningCount: Int
    let destinations: [BenchmarkDestinationDocument]

    init(_ result: ProviderBenchmarkResult) throws {
        provider = result.provider.rawValue
        qualifyingDestinationCount = result.qualifyingDestinationCount
        failedDestinationCount = result.failedDestinationCount
        noEligibleDestinationCount = result.noEligibleDestinationCount
        average = JSONNullable(
            try result.average.map(BenchmarkAverageDocument.init)
        )
        warningCount = result.destinationOutcomes.reduce(into: 0) { count, outcome in
            switch outcome.result {
            case .selected(_, warning: .some),
                 .noEligible(warning: .some):
                count += 1
            case .selected(_, warning: .none),
                 .noEligible(warning: .none),
                 .failure:
                break
            }
        }
        destinations = try result.destinationOutcomes.map(
            BenchmarkDestinationDocument.init
        )
    }
}

private struct BenchmarkAverageDocument: Encodable {
    let amount: String
    let currency: String

    init(_ average: BenchmarkAverage) throws {
        amount = try OutputMoneyFormatter.string(
            OutputMoneyFormatter.roundedToCents(average.amount)
        )
        currency = average.currency
    }
}

private struct BenchmarkDestinationDocument: Encodable {
    let benchmarkID: String
    let status: String
    let selectedRate: JSONNullable<BenchmarkSelectedRateDocument>
    let error: ErrorDocument?

    init(_ outcome: BenchmarkDestinationOutcome) throws {
        benchmarkID = outcome.benchmarkID

        switch outcome.result {
        case .selected(let rate, warning: _):
            status = "success"
            selectedRate = .value(try BenchmarkSelectedRateDocument(rate))
            error = nil
        case .noEligible:
            status = "no_eligible"
            selectedRate = .null
            error = nil
        case .failure(let failure):
            status = "failed"
            selectedRate = .null
            error = ErrorDocument(failure)
        }
    }
}

private struct BenchmarkSelectedRateDocument: Encodable {
    let serviceName: String
    let amount: String
    let currency: String
    let tracking: JSONNullable<Bool>
    let estimatedDeliveryBusinessDays: JSONNullable<Int>

    init(_ rate: ShippingRate) throws {
        serviceName = rate.serviceName
        amount = try OutputMoneyFormatter.string(rate.total)
        currency = rate.currency
        tracking = JSONNullable(rate.isTrackable)
        estimatedDeliveryBusinessDays = JSONNullable(
            rate.estimatedDeliveryBusinessDays
        )
    }
}

import ArgumentParser
import Foundation

@main
struct YFShipCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "yfship",
        abstract: "Compare shipping rates and calculate benchmark shipping costs.",
        subcommands: [
            BenchmarkCommand.self,
            CompareCommand.self
        ]
    )
}

struct PackageOptions: ParsableArguments {
    @Option(
        name: .customLong("weight-lb"),
        parsing: .unconditional,
        help: "Package weight in pounds."
    )
    var weightLB: Double

    @Option(
        name: .customLong("length-in"),
        parsing: .unconditional,
        help: "Package length in inches."
    )
    var lengthIn: Double

    @Option(
        name: .customLong("width-in"),
        parsing: .unconditional,
        help: "Package width in inches."
    )
    var widthIn: Double

    @Option(
        name: .customLong("height-in"),
        parsing: .unconditional,
        help: "Package height in inches."
    )
    var heightIn: Double

    mutating func validate() throws {
        try Self.requirePositiveFinite(weightLB, option: "--weight-lb")
        try Self.requirePositiveFinite(lengthIn, option: "--length-in")
        try Self.requirePositiveFinite(widthIn, option: "--width-in")
        try Self.requirePositiveFinite(heightIn, option: "--height-in")
    }

    var shippingPackage: ShippingPackage {
        ShippingPackage(
            weightLb: weightLB,
            lengthIn: lengthIn,
            widthIn: widthIn,
            heightIn: heightIn
        )
    }

    private static func requirePositiveFinite(
        _ value: Double,
        option: String
    ) throws {
        guard value.isFinite, value > 0 else {
            throw ValidationError("\(option) must be greater than zero.")
        }
    }
}

struct ItemOptions: ParsableArguments {
    @Option(
        name: .customLong("item-description"),
        help: "Customs description for the item."
    )
    var itemDescription: String

    @Option(
        name: .customLong("item-value-cad"),
        parsing: .unconditional,
        help: "Declared item value in CAD.",
        transform: CLIValueParser.decimal
    )
    var itemValueCAD: Decimal

    @Option(
        name: .customLong("item-origin-country"),
        help: "Item country of origin code."
    )
    var itemOriginCountry: String

    @Option(
        name: .customLong("hs-code"),
        help: "Optional harmonized-system code."
    )
    var hsCode: String?

    @Option(
        name: .customLong("sku"),
        help: "Optional item SKU."
    )
    var sku: String?

    @Option(
        name: .customLong("quantity"),
        parsing: .unconditional,
        help: "Item quantity."
    )
    var quantity = 1

    mutating func validate() throws {
        guard !itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("--item-description must not be empty.")
        }
        guard itemValueCAD > 0 else {
            throw ValidationError("--item-value-cad must be greater than zero.")
        }
        guard !itemOriginCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("--item-origin-country must not be empty.")
        }
        guard quantity > 0 else {
            throw ValidationError("--quantity must be greater than zero.")
        }
    }

    var shipmentItem: ShipmentItem {
        ShipmentItem(
            description: itemDescription,
            quantity: quantity,
            valueCAD: itemValueCAD,
            originCountryCode: itemOriginCountry,
            hsCode: Self.nonEmpty(hsCode),
            sku: Self.nonEmpty(sku)
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

struct ProviderOptions: ParsableArguments {
    @Option(
        name: .customLong("provider"),
        parsing: .singleValue,
        help: "Provider to query; repeat for multiple providers."
    )
    var providerIDs: [ProviderID] = []
}

struct OutputOptions: ParsableArguments {
    @Flag(
        name: .customLong("json"),
        help: "Emit stable machine-readable JSON."
    )
    var json = false
}

enum CLIValueParser {
    static func decimal(_ argument: String) throws -> Decimal {
        var digits = argument[...]
        if digits.first == "+" || digits.first == "-" {
            digits = digits.dropFirst()
        }

        let components = digits.split(
            separator: ".",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let hasDigit = components.contains { !$0.isEmpty }
        let containsOnlyASCIIDigits = components.allSatisfy { component in
            component.allSatisfy { character in
                character >= "0" && character <= "9"
            }
        }

        guard !digits.isEmpty,
              hasDigit,
              containsOnlyASCIIDigits,
              let value = Decimal(
                  string: argument,
                  locale: Locale(identifier: "en_US_POSIX")
              ) else {
            throw ValidationError(
                "--item-value-cad must be a decimal number using a period as the separator."
            )
        }
        return value
    }
}

enum ProviderSelectionError: Error, Equatable, Sendable, LocalizedError {
    case providersNotConfigured([ProviderID])

    var errorDescription: String? {
        switch self {
        case .providersNotConfigured(let providers):
            let names = providers.map(\.rawValue).joined(separator: ", ")
            if providers.count == 1 {
                return "Requested provider '\(names)' is not configured."
            }
            return "Requested providers are not configured: \(names)."
        }
    }
}

struct CommandRuntime {
    static func load(
        requestedProviderIDs: [ProviderID]
    ) throws -> (configuration: AppConfiguration, providers: [any ShippingProvider]) {
        let environment = try EnvironmentLoader().load()
        let configuration: AppConfiguration
        do {
            configuration = try AppConfiguration(environment: environment)
        } catch AppConfigurationError.noProvidersConfigured
                    where !requestedProviderIDs.isEmpty {
            throw ProviderSelectionError.providersNotConfigured(
                unique(requestedProviderIDs)
            )
        }

        let providerIDs = try resolveProviderIDs(
            requestedProviderIDs,
            configuration: configuration
        )
        let httpClient = URLSessionHTTPClient()
        let providers = try makeProviders(
            configuration: configuration,
            providerIDs: providerIDs,
            httpClient: httpClient
        )
        return (configuration, providers)
    }

    static func resolveProviderIDs(
        _ requestedProviderIDs: [ProviderID],
        configuration: AppConfiguration
    ) throws -> [ProviderID] {
        guard !requestedProviderIDs.isEmpty else {
            return configuration.configuredProviderIDs
        }

        let requestedProviderIDs = unique(requestedProviderIDs)
        let missingProviderIDs = requestedProviderIDs.filter {
            !configuration.configuredProviderIDs.contains($0)
        }
        guard missingProviderIDs.isEmpty else {
            throw ProviderSelectionError.providersNotConfigured(missingProviderIDs)
        }
        return requestedProviderIDs
    }

    static func makeProviders(
        configuration: AppConfiguration,
        providerIDs: [ProviderID],
        httpClient: any HTTPClient
    ) throws -> [any ShippingProvider] {
        try providerIDs.map { providerID -> any ShippingProvider in
            switch providerID {
            case .chitchats:
                guard let providerConfiguration = configuration.chitChats else {
                    throw ProviderSelectionError.providersNotConfigured([providerID])
                }
                return ChitChatsProvider(
                    configuration: providerConfiguration,
                    httpClient: httpClient
                )
            case .stallion:
                guard let providerConfiguration = configuration.stallion else {
                    throw ProviderSelectionError.providersNotConfigured([providerID])
                }
                return StallionProvider(
                    configuration: providerConfiguration,
                    httpClient: httpClient
                )
            }
        }
    }

    static func configurationFailure(_ error: Error) -> ExitCode {
        let message: String
        switch error {
        case let error as EnvironmentLoaderError:
            message = error.description
        case let error as AppConfigurationError:
            message = error.description
        case let error as ProviderSelectionError:
            message = error.errorDescription ?? "Provider configuration is invalid."
        default:
            message = "YFShip configuration could not be loaded."
        }
        writeDiagnostic(message)
        return CommandExitCode.configurationFailure
    }

    static func writeDiagnostic(_ message: String) {
        guard let data = "\(message)\n".data(using: .utf8) else {
            return
        }
        FileHandle.standardError.write(data)
    }

    private static func unique(_ providerIDs: [ProviderID]) -> [ProviderID] {
        providerIDs.reduce(into: []) { uniqueProviderIDs, providerID in
            if !uniqueProviderIDs.contains(providerID) {
                uniqueProviderIDs.append(providerID)
            }
        }
    }
}

enum CommandExitCode {
    static let configurationFailure = ExitCode(3)

    static func result(_ status: RateComparisonStatus) -> ExitCode {
        switch status {
        case .success:
            .success
        case .partialSuccess:
            ExitCode(6)
        case .noEligibleOption:
            ExitCode(4)
        case .completeProviderFailure:
            ExitCode(5)
        }
    }
}

extension ProviderID {
    var displayName: String {
        switch self {
        case .chitchats:
            "Chit Chats"
        case .stallion:
            "Stallion"
        }
    }
}

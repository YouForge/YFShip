import ArgumentParser
import Foundation

struct CompareCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compare",
        abstract: "Compare eligible shipping rates for one destination."
    )

    @Option(
        name: .customLong("to-address1"),
        help: "Destination street address."
    )
    var toAddress1: String

    @Option(
        name: .customLong("to-address2"),
        help: "Optional second destination address line."
    )
    var toAddress2: String?

    @Option(
        name: .customLong("to-city"),
        help: "Destination city."
    )
    var toCity: String

    @Option(
        name: .customLong("to-region"),
        help: "Destination state or province code."
    )
    var toRegion: String

    @Option(
        name: .customLong("to-postal-code"),
        help: "Destination postal or ZIP code."
    )
    var toPostalCode: String

    @Option(
        name: .customLong("to-country"),
        help: "Destination country code."
    )
    var toCountry: String

    @Flag(
        name: .customLong("to-residential"),
        help: "Mark the destination as residential."
    )
    var toResidential = false

    @OptionGroup(title: "Package Options")
    var packageOptions: PackageOptions

    @OptionGroup(title: "Item Options")
    var itemOptions: ItemOptions

    @OptionGroup(title: "Provider Options")
    var providerOptions: ProviderOptions

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    mutating func validate() throws {
        try requireNonEmpty(toAddress1, option: "--to-address1")
        try requireNonEmpty(toCity, option: "--to-city")
        try requireNonEmpty(toRegion, option: "--to-region")
        try requireNonEmpty(toPostalCode, option: "--to-postal-code")
        try requireNonEmpty(toCountry, option: "--to-country")
    }

    mutating func run() async throws {
        let runtime: (
            configuration: AppConfiguration,
            providers: [any ShippingProvider]
        )
        do {
            runtime = try CommandRuntime.load(
                requestedProviderIDs: providerOptions.providerIDs
            )
        } catch {
            throw CommandRuntime.configurationFailure(error)
        }

        let shipment = Shipment(
            origin: runtime.configuration.origin,
            destination: destination,
            package: packageOptions.shippingPackage,
            items: [itemOptions.shipmentItem]
        )
        let result = await RateEngine(providers: runtime.providers).rates(for: shipment)

        if outputOptions.json {
            print(try JSONOutput.compare(result))
        } else {
            print(HumanOutput.compare(result, shipment: shipment))
        }

        let exitCode = CommandExitCode.result(result.status)
        if !exitCode.isSuccess {
            throw exitCode
        }
    }

    var destination: Address {
        Address(
            name: nil,
            company: nil,
            address1: toAddress1,
            address2: Self.nonEmpty(toAddress2),
            city: toCity,
            regionCode: toRegion,
            postalCode: toPostalCode,
            countryCode: toCountry,
            isResidential: toResidential,
            email: nil,
            phone: nil
        )
    }

    private func requireNonEmpty(_ value: String, option: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("\(option) must not be empty.")
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

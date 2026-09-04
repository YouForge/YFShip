import ArgumentParser

struct BenchmarkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "Calculate average eligible rates across canonical destinations."
    )

    @OptionGroup(title: "Package Options")
    var packageOptions: PackageOptions

    @OptionGroup(title: "Item Options")
    var itemOptions: ItemOptions

    @OptionGroup(title: "Provider Options")
    var providerOptions: ProviderOptions

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

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

        let destinations: [BenchmarkDestination]
        do {
            destinations = try BenchmarkDestinationLoader.load()
        } catch {
            CommandRuntime.writeDiagnostic(
                "The canonical benchmark destinations could not be loaded."
            )
            throw CommandExitCode.configurationFailure
        }

        let result = await BenchmarkCalculator(providers: runtime.providers).calculate(
            origin: runtime.configuration.origin,
            package: packageOptions.shippingPackage,
            items: [itemOptions.shipmentItem],
            destinations: destinations
        )

        if outputOptions.json {
            print(try JSONOutput.benchmark(result))
        } else {
            print(HumanOutput.benchmark(result))
        }

        let exitCode = CommandExitCode.result(result.commandStatus)
        if !exitCode.isSuccess {
            throw exitCode
        }
    }
}

extension BenchmarkResult {
    var commandStatus: RateComparisonStatus {
        let hasUsableResult = providerResults.contains { $0.average != nil }
        guard hasUsableResult else {
            return .completeProviderFailure
        }

        let hasFailure = providerResults.contains { providerResult in
            providerResult.average == nil || providerResult.failedDestinationCount > 0
        }
        return hasFailure ? .partialSuccess : .success
    }
}

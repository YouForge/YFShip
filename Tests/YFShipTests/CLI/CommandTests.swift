import ArgumentParser
import Foundation
import Testing
@testable import YFShip

@Suite("CLI commands")
struct CommandTests {
    @Test("Rejects zero and negative package values before execution")
    func rejectsInvalidPackageValues() {
        assertBenchmarkParseFails(
            benchmarkArguments(weight: "0"),
            containing: "--weight-lb must be greater than zero."
        )
        assertBenchmarkParseFails(
            benchmarkArguments(weight: "-1"),
            containing: "--weight-lb must be greater than zero."
        )
        assertBenchmarkParseFails(
            benchmarkArguments(length: "0"),
            containing: "--length-in must be greater than zero."
        )
    }

    @Test("Rejects zero, negative, and malformed item values")
    func rejectsInvalidItemValues() {
        assertBenchmarkParseFails(
            benchmarkArguments(itemValue: "0"),
            containing: "--item-value-cad must be greater than zero."
        )
        assertBenchmarkParseFails(
            benchmarkArguments(itemValue: "-0.01"),
            containing: "--item-value-cad must be greater than zero."
        )
        assertBenchmarkParseFails(
            benchmarkArguments(itemValue: "1,25"),
            containing: "must be a decimal number using a period"
        )
        assertBenchmarkParseFails(
            benchmarkArguments(itemValue: "12abc"),
            containing: "must be a decimal number using a period"
        )
    }

    @Test("Rejects empty descriptions and nonpositive quantities")
    func rejectsInvalidItemMetadata() {
        assertBenchmarkParseFails(
            benchmarkArguments(description: "   "),
            containing: "--item-description must not be empty."
        )
        assertBenchmarkParseFails(
            benchmarkArguments(quantity: "0"),
            containing: "--quantity must be greater than zero."
        )
    }

    @Test("Bad provider values list every valid choice")
    func rejectsUnknownProvider() {
        let arguments = benchmarkArguments() + ["--provider", "other"]

        do {
            _ = try BenchmarkCommand.parse(arguments)
            Issue.record("Expected an invalid provider parse failure")
        } catch {
            let message = BenchmarkCommand.fullMessage(for: error, columns: 120)
            #expect(message.contains("chitchats"))
            #expect(message.contains("stallion"))
        }
    }

    @Test("Compare builds a nameless destination and parses shared options")
    func compareBuildsDestination() throws {
        let command = try CompareCommand.parse(
            compareArguments() + [
                "--to-address2", "Unit 2",
                "--to-residential",
                "--provider", "STALLION",
                "--provider", "chitchats",
                "--json"
            ]
        )

        #expect(command.destination.name == nil)
        #expect(command.destination.address1 == "200 Mesnager St")
        #expect(command.destination.address2 == "Unit 2")
        #expect(command.destination.isResidential)
        #expect(command.packageOptions.shippingPackage.weightLb == 0.5)
        #expect(command.itemOptions.shipmentItem.quantity == 1)
        #expect(command.providerOptions.providerIDs == [.stallion, .chitchats])
        #expect(command.outputOptions.json)
    }

    @Test("Provider resolution defaults to configured providers and deduplicates requests")
    func resolvesProviders() throws {
        let configuration = try AppConfiguration(
            environment: configurationEnvironment(
                chitChats: true,
                stallion: true
            )
        )

        #expect(
            try CommandRuntime.resolveProviderIDs([], configuration: configuration)
                == [.chitchats, .stallion]
        )
        #expect(
            try CommandRuntime.resolveProviderIDs(
                [.stallion, .stallion, .chitchats],
                configuration: configuration
            ) == [.stallion, .chitchats]
        )
    }

    @Test("Explicitly requested unconfigured providers fail by provider name")
    func rejectsUnconfiguredProvider() throws {
        let configuration = try AppConfiguration(
            environment: configurationEnvironment(
                chitChats: false,
                stallion: true
            )
        )

        do {
            _ = try CommandRuntime.resolveProviderIDs(
                [.chitchats],
                configuration: configuration
            )
            Issue.record("Expected provider-scoped configuration failure")
        } catch let error as ProviderSelectionError {
            #expect(error == .providersNotConfigured([.chitchats]))
            #expect(error.errorDescription?.contains("chitchats") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Maps compare statuses to frozen exit codes")
    func mapsExitCodes() {
        #expect(CommandExitCode.configurationFailure.rawValue == 3)
        #expect(CommandExitCode.result(.success).rawValue == 0)
        #expect(CommandExitCode.result(.partialSuccess).rawValue == 6)
        #expect(CommandExitCode.result(.noEligibleOption).rawValue == 4)
        #expect(CommandExitCode.result(.completeProviderFailure).rawValue == 5)
        #expect(ExitCode.validationFailure.rawValue == 64)
    }

    @Test("Derives benchmark status from usable averages and failures")
    func derivesBenchmarkStatus() {
        let complete = benchmarkResult(
            providerResults: [benchmarkProvider(average: 10, failures: 0)]
        )
        let destinationFailure = benchmarkResult(
            providerResults: [benchmarkProvider(average: 10, failures: 1)]
        )
        let missingProviderAverage = benchmarkResult(
            providerResults: [
                benchmarkProvider(provider: .stallion, average: 10, failures: 0),
                benchmarkProvider(provider: .chitchats, average: nil, failures: 0)
            ]
        )
        let noUsableResult = benchmarkResult(
            providerResults: [benchmarkProvider(average: nil, failures: 0)]
        )

        #expect(complete.commandStatus == .success)
        #expect(destinationFailure.commandStatus == .partialSuccess)
        #expect(missingProviderAverage.commandStatus == .partialSuccess)
        #expect(noUsableResult.commandStatus == .completeProviderFailure)
        #expect(CommandExitCode.result(complete.commandStatus).rawValue == 0)
        #expect(CommandExitCode.result(destinationFailure.commandStatus).rawValue == 6)
        #expect(CommandExitCode.result(noUsableResult.commandStatus).rawValue == 5)
    }
}

private func assertBenchmarkParseFails(
    _ arguments: [String],
    containing expectedMessage: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    do {
        _ = try BenchmarkCommand.parse(arguments)
        Issue.record(
            "Expected argument validation to fail",
            sourceLocation: sourceLocation
        )
    } catch {
        let message = BenchmarkCommand.fullMessage(for: error, columns: 120)
        #expect(
            message.contains(expectedMessage),
            "Expected '\(message)' to contain '\(expectedMessage)'",
            sourceLocation: sourceLocation
        )
        #expect(
            BenchmarkCommand.exitCode(for: error).rawValue == 64,
            sourceLocation: sourceLocation
        )
    }
}

private func benchmarkArguments(
    weight: String = "0.5",
    length: String = "6",
    itemValue: String = "20.00",
    description: String = "Synthetic item",
    quantity: String = "1"
) -> [String] {
    [
        "--weight-lb", weight,
        "--length-in", length,
        "--width-in", "4",
        "--height-in", "1",
        "--item-description", description,
        "--item-value-cad", itemValue,
        "--item-origin-country", "CA",
        "--quantity", quantity
    ]
}

private func compareArguments() -> [String] {
    [
        "--to-address1", "200 Mesnager St",
        "--to-city", "Los Angeles",
        "--to-region", "CA",
        "--to-postal-code", "90012",
        "--to-country", "US"
    ] + benchmarkArguments()
}

private func configurationEnvironment(
    chitChats: Bool,
    stallion: Bool
) -> [String: String] {
    var environment = [
        "YFSHIP_ORIGIN_ADDRESS1": "10 Origin St",
        "YFSHIP_ORIGIN_CITY": "Hamilton",
        "YFSHIP_ORIGIN_REGION_CODE": "ON",
        "YFSHIP_ORIGIN_POSTAL_CODE": "L8P 1A1",
        "YFSHIP_ORIGIN_COUNTRY_CODE": "CA"
    ]
    if chitChats {
        environment["CHITCHATS_CLIENT_ID"] = "synthetic-client"
        environment["CHITCHATS_ACCESS_TOKEN"] = "synthetic-token"
        environment["CHITCHATS_PACKAGE_TYPE"] = "parcel"
    }
    if stallion {
        environment["STALLION_ACCESS_TOKEN"] = "synthetic-token"
    }
    return environment
}

private func benchmarkResult(
    providerResults: [ProviderBenchmarkResult]
) -> BenchmarkResult {
    BenchmarkResult(destinationCount: 1, providerResults: providerResults)
}

private func benchmarkProvider(
    provider: ProviderID = .stallion,
    average: Decimal?,
    failures: Int
) -> ProviderBenchmarkResult {
    ProviderBenchmarkResult(
        provider: provider,
        totalDestinationCount: 1,
        qualifyingDestinationCount: average == nil ? 0 : 1,
        failedDestinationCount: failures,
        noEligibleDestinationCount: average == nil && failures == 0 ? 1 : 0,
        destinationOutcomes: [],
        average: average.map { BenchmarkAverage(amount: $0, currency: "CAD") }
    )
}

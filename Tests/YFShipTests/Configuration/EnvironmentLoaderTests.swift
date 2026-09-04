import Foundation
import Testing
@testable import YFShip

@Suite("Environment loader")
struct EnvironmentLoaderTests {
    @Test("Parses the supported environment-file syntax")
    func parsesSupportedSyntax() throws {
        let values = try EnvironmentLoader.parse(
            """

              # comment
            FIRST=one
              SECOND=value with spaces
            WITH_EQUALS=alpha=beta=gamma
            SPACED=  keep both sides
            EMPTY=
            """
        )

        #expect(values["FIRST"] == "one")
        #expect(values["SECOND"] == "value with spaces")
        #expect(values["WITH_EQUALS"] == "alpha=beta=gamma")
        #expect(values["SPACED"] == "  keep both sides")
        #expect(values["EMPTY"] == "")
    }

    @Test("Rejects malformed lines without echoing their content")
    func rejectsMalformedLinesSafely() {
        let secret = "secret-value-that-must-not-appear"

        do {
            _ = try EnvironmentLoader.parse("VALID=yes\n\(secret)\n")
            Issue.record("Expected malformed input to throw")
        } catch {
            #expect(error as? EnvironmentLoaderError == .malformedLine(number: 2))
            #expect(!String(describing: error).contains(secret))
            #expect(!error.localizedDescription.contains(secret))
        }
    }

    @Test("Uses process, local, then user precedence")
    func resolvesPrecedence() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let currentDirectory = root.appendingPathComponent("work")
        let homeDirectory = root.appendingPathComponent("home")
        let userConfigDirectory = homeDirectory
            .appendingPathComponent(".config")
            .appendingPathComponent("yfship")
        try FileManager.default.createDirectory(
            at: currentDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: userConfigDirectory,
            withIntermediateDirectories: true
        )

        try """
        YFSHIP_ORIGIN_CITY=user
        USER_ONLY=user
        """.write(
            to: userConfigDirectory.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )
        try """
        YFSHIP_ORIGIN_CITY=local
        LOCAL_ONLY=local
        """.write(
            to: currentDirectory.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )

        let values = try EnvironmentLoader().load(
            processEnvironment: ["YFSHIP_ORIGIN_CITY": "process"],
            currentDirectory: currentDirectory,
            homeDirectory: homeDirectory
        )

        #expect(values["YFSHIP_ORIGIN_CITY"] == "process")
        #expect(values["LOCAL_ONLY"] == "local")
        #expect(values["USER_ONLY"] == "user")
    }

    @Test("Accepts process environment as the only configuration source")
    func loadsProcessEnvironmentOnly() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let values = try EnvironmentLoader().load(
            processEnvironment: ["STALLION_ACCESS_TOKEN": "synthetic-token"],
            currentDirectory: root.appendingPathComponent("work"),
            homeDirectory: root.appendingPathComponent("home")
        )

        #expect(values["STALLION_ACCESS_TOKEN"] == "synthetic-token")
    }

    @Test("Reports missing configuration")
    func reportsMissingConfiguration() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            _ = try EnvironmentLoader().load(
                processEnvironment: ["PATH": "/usr/bin"],
                currentDirectory: root.appendingPathComponent("work"),
                homeDirectory: root.appendingPathComponent("home")
            )
            Issue.record("Expected missing configuration to throw")
        } catch {
            #expect(error as? EnvironmentLoaderError == .noConfigurationFound)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("YFShipTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}

import Foundation

enum EnvironmentLoaderError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    case malformedLine(number: Int)
    case unreadableFile(path: String)
    case noConfigurationFound

    var errorDescription: String? {
        switch self {
        case let .malformedLine(number):
            "Malformed environment line \(number); expected KEY=value."
        case let .unreadableFile(path):
            "Unable to read configuration file at \(path)."
        case .noConfigurationFound:
            "No YFShip configuration found in the process environment, ./.env, or ~/.config/yfship/.env."
        }
    }

    var description: String {
        errorDescription ?? "Environment configuration error."
    }
}

struct EnvironmentLoader {
    private static let configurationKeyPrefixes = [
        "YFSHIP_",
        "CHITCHATS_",
        "STALLION_"
    ]

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    static func parse(_ contents: String) throws -> [String: String] {
        var values: [String: String] = [:]
        let lines = contents.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )

        for (offset, rawLine) in lines.enumerated() {
            var line = rawLine
            if line.last == "\r" {
                line = line.dropLast()
            }

            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else {
                continue
            }

            guard let separator = line.firstIndex(of: "=") else {
                throw EnvironmentLoaderError.malformedLine(number: offset + 1)
            }

            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                throw EnvironmentLoaderError.malformedLine(number: offset + 1)
            }

            let valueStart = line.index(after: separator)
            values[key] = String(line[valueStart...])
        }

        return values
    }

    func load(
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> [String: String] {
        let localURL = currentDirectory.appendingPathComponent(".env")
        let userURL = homeDirectory
            .appendingPathComponent(".config")
            .appendingPathComponent("yfship")
            .appendingPathComponent(".env")

        var values: [String: String] = [:]
        var foundConfigurationSource = processEnvironment.keys.contains { key in
            Self.configurationKeyPrefixes.contains { key.hasPrefix($0) }
        }

        if let userValues = try valuesIfPresent(at: userURL) {
            values.merge(userValues) { _, higherPrecedenceValue in
                higherPrecedenceValue
            }
            foundConfigurationSource = true
        }

        if let localValues = try valuesIfPresent(at: localURL) {
            values.merge(localValues) { _, higherPrecedenceValue in
                higherPrecedenceValue
            }
            foundConfigurationSource = true
        }

        guard foundConfigurationSource else {
            throw EnvironmentLoaderError.noConfigurationFound
        }

        values.merge(processEnvironment) { _, higherPrecedenceValue in
            higherPrecedenceValue
        }
        return values
    }

    private func valuesIfPresent(at url: URL) throws -> [String: String]? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let contents: String
        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw EnvironmentLoaderError.unreadableFile(path: url.path)
        }

        return try Self.parse(contents)
    }
}

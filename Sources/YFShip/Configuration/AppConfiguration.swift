import Foundation

enum AppConfigurationError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    case missingRequiredKeys([String])
    case invalidBoolean(key: String)
    case noProvidersConfigured

    var errorDescription: String? {
        switch self {
        case let .missingRequiredKeys(keys):
            "Missing required configuration keys: \(keys.sorted().joined(separator: ", "))."
        case let .invalidBoolean(key):
            "Configuration key \(key) must be true or false."
        case .noProvidersConfigured:
            "No shipping providers are configured."
        }
    }

    var description: String {
        errorDescription ?? "YFShip configuration error."
    }
}

struct ChitChatsConfiguration: Sendable, Equatable {
    let clientID: String
    let accessToken: String
    let packageType: String?
}

struct StallionConfiguration: Sendable, Equatable {
    let accessToken: String
    let packageType: String?
}

struct AppConfiguration: Sendable, Equatable {
    let origin: Address
    let chitChats: ChitChatsConfiguration?
    let stallion: StallionConfiguration?

    var configuredProviderIDs: [ProviderID] {
        ProviderID.allCases.filter { provider in
            switch provider {
            case .chitchats:
                chitChats != nil
            case .stallion:
                stallion != nil
            }
        }
    }

    init(environment: [String: String]) throws {
        let address1 = Self.configuredValue(
            for: "YFSHIP_ORIGIN_ADDRESS1",
            in: environment
        )
        let city = Self.configuredValue(
            for: "YFSHIP_ORIGIN_CITY",
            in: environment
        )
        let regionCode = Self.configuredValue(
            for: "YFSHIP_ORIGIN_REGION_CODE",
            in: environment
        )
        let postalCode = Self.configuredValue(
            for: "YFSHIP_ORIGIN_POSTAL_CODE",
            in: environment
        )
        let countryCode = Self.configuredValue(
            for: "YFSHIP_ORIGIN_COUNTRY_CODE",
            in: environment
        )
        let requiredOriginValues = [
            ("YFSHIP_ORIGIN_ADDRESS1", address1),
            ("YFSHIP_ORIGIN_CITY", city),
            ("YFSHIP_ORIGIN_REGION_CODE", regionCode),
            ("YFSHIP_ORIGIN_POSTAL_CODE", postalCode),
            ("YFSHIP_ORIGIN_COUNTRY_CODE", countryCode)
        ]
        let missingOriginKeys = requiredOriginValues.compactMap { key, value in
            value == nil ? key : nil
        }
        guard missingOriginKeys.isEmpty,
              let address1,
              let city,
              let regionCode,
              let postalCode,
              let countryCode else {
            throw AppConfigurationError.missingRequiredKeys(missingOriginKeys)
        }

        let residential = try Self.booleanValue(
            for: "YFSHIP_ORIGIN_RESIDENTIAL",
            in: environment,
            default: false
        )

        origin = Address(
            name: Self.configuredValue(for: "YFSHIP_ORIGIN_NAME", in: environment),
            company: Self.configuredValue(for: "YFSHIP_ORIGIN_COMPANY", in: environment),
            address1: address1,
            address2: Self.configuredValue(for: "YFSHIP_ORIGIN_ADDRESS2", in: environment),
            city: city,
            regionCode: regionCode,
            postalCode: postalCode,
            countryCode: countryCode,
            isResidential: residential,
            email: Self.configuredValue(for: "YFSHIP_ORIGIN_EMAIL", in: environment),
            phone: Self.configuredValue(for: "YFSHIP_ORIGIN_PHONE", in: environment)
        )

        chitChats = try Self.chitChatsConfiguration(from: environment)
        stallion = try Self.stallionConfiguration(from: environment)

        guard chitChats != nil || stallion != nil else {
            throw AppConfigurationError.noProvidersConfigured
        }
    }

    static func load() throws -> AppConfiguration {
        try AppConfiguration(environment: EnvironmentLoader().load())
    }

    private static func chitChatsConfiguration(
        from environment: [String: String]
    ) throws -> ChitChatsConfiguration? {
        let clientID = configuredValue(for: "CHITCHATS_CLIENT_ID", in: environment)
        let accessToken = configuredValue(for: "CHITCHATS_ACCESS_TOKEN", in: environment)
        let packageType = configuredValue(for: "CHITCHATS_PACKAGE_TYPE", in: environment)

        guard clientID != nil || accessToken != nil || packageType != nil else {
            return nil
        }

        var missingKeys: [String] = []
        if clientID == nil {
            missingKeys.append("CHITCHATS_CLIENT_ID")
        }
        if accessToken == nil {
            missingKeys.append("CHITCHATS_ACCESS_TOKEN")
        }
        guard missingKeys.isEmpty else {
            throw AppConfigurationError.missingRequiredKeys(missingKeys)
        }

        return ChitChatsConfiguration(
            clientID: clientID!,
            accessToken: accessToken!,
            packageType: packageType
        )
    }

    private static func stallionConfiguration(
        from environment: [String: String]
    ) throws -> StallionConfiguration? {
        let accessToken = configuredValue(for: "STALLION_ACCESS_TOKEN", in: environment)
        let packageType = configuredValue(for: "STALLION_PACKAGE_TYPE", in: environment)

        guard accessToken != nil || packageType != nil else {
            return nil
        }
        guard let accessToken else {
            throw AppConfigurationError.missingRequiredKeys([
                "STALLION_ACCESS_TOKEN"
            ])
        }

        return StallionConfiguration(
            accessToken: accessToken,
            packageType: packageType
        )
    }

    private static func configuredValue(
        for key: String,
        in environment: [String: String]
    ) -> String? {
        guard let value = environment[key],
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private static func booleanValue(
        for key: String,
        in environment: [String: String],
        default defaultValue: Bool
    ) throws -> Bool {
        guard let value = configuredValue(for: key, in: environment) else {
            return defaultValue
        }

        switch value.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            throw AppConfigurationError.invalidBoolean(key: key)
        }
    }
}

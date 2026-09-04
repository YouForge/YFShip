import Testing
@testable import YFShip

@Suite("Application configuration")
struct AppConfigurationTests {
    @Test("Builds exactly one configured provider")
    func buildsOneProvider() throws {
        var environment = originEnvironment()
        environment["STALLION_ACCESS_TOKEN"] = "stallion-token"

        let configuration = try AppConfiguration(environment: environment)

        #expect(configuration.configuredProviderIDs == [.stallion])
        #expect(configuration.chitChats == nil)
        #expect(configuration.origin.countryCode == "CA")
        #expect(!configuration.origin.isResidential)
    }

    @Test("Builds a complete Chit Chats configuration")
    func buildsChitChatsProvider() throws {
        var environment = originEnvironment()
        environment["CHITCHATS_CLIENT_ID"] = "client-id"
        environment["CHITCHATS_ACCESS_TOKEN"] = "access-token"
        environment["CHITCHATS_PACKAGE_TYPE"] = "parcel"

        let configuration = try AppConfiguration(environment: environment)

        #expect(configuration.configuredProviderIDs == [.chitchats])
        #expect(configuration.chitChats?.clientID == "client-id")
        #expect(configuration.chitChats?.packageType == "parcel")
        #expect(configuration.stallion == nil)
    }

    @Test("Rejects a partially configured provider without leaking values")
    func rejectsPartialProviderSafely() {
        let secret = "private-client-value"
        var environment = originEnvironment()
        environment["CHITCHATS_CLIENT_ID"] = secret

        do {
            _ = try AppConfiguration(environment: environment)
            Issue.record("Expected partial provider configuration to throw")
        } catch {
            let message = String(describing: error)
            #expect(message.contains("CHITCHATS_ACCESS_TOKEN"))
            #expect(!message.contains(secret))
        }
    }

    @Test("Requires a package type for configured Chit Chats credentials")
    func requiresChitChatsPackageType() {
        let secret = "synthetic-access-token"
        var environment = originEnvironment()
        environment["CHITCHATS_CLIENT_ID"] = "synthetic-client"
        environment["CHITCHATS_ACCESS_TOKEN"] = secret

        do {
            _ = try AppConfiguration(environment: environment)
            Issue.record("Expected a missing package type to throw")
        } catch {
            let message = String(describing: error)
            #expect(
                error as? AppConfigurationError == .missingRequiredKeys([
                    "CHITCHATS_PACKAGE_TYPE"
                ])
            )
            #expect(message.contains("CHITCHATS_PACKAGE_TYPE"))
            #expect(!message.contains(secret))
        }
    }

    @Test("Rejects zero configured providers")
    func rejectsZeroProviders() {
        do {
            _ = try AppConfiguration(environment: originEnvironment())
            Issue.record("Expected zero configured providers to throw")
        } catch {
            #expect(error as? AppConfigurationError == .noProvidersConfigured)
        }
    }

    @Test("Configuration errors never reveal secret values")
    func errorsDoNotRevealSecrets() {
        let secret = "top-secret-provider-token"
        let environment = [
            "STALLION_ACCESS_TOKEN": secret
        ]

        do {
            _ = try AppConfiguration(environment: environment)
            Issue.record("Expected missing origin configuration to throw")
        } catch {
            let message = String(describing: error)
            #expect(message.contains("YFSHIP_ORIGIN_ADDRESS1"))
            #expect(!message.contains(secret))
        }
    }

    @Test("Requires the origin country code")
    func requiresOriginCountryCode() {
        var environment = originEnvironment()
        environment["YFSHIP_ORIGIN_COUNTRY_CODE"] = nil
        environment["STALLION_ACCESS_TOKEN"] = "synthetic-token"

        do {
            _ = try AppConfiguration(environment: environment)
            Issue.record("Expected a missing origin country code to throw")
        } catch {
            #expect(
                error as? AppConfigurationError == .missingRequiredKeys([
                    "YFSHIP_ORIGIN_COUNTRY_CODE"
                ])
            )
        }
    }

    @Test("Rejects invalid booleans without echoing the value")
    func rejectsInvalidBooleanSafely() {
        let secret = "not-a-public-value"
        var environment = originEnvironment()
        environment["STALLION_ACCESS_TOKEN"] = "token"
        environment["YFSHIP_ORIGIN_RESIDENTIAL"] = secret

        do {
            _ = try AppConfiguration(environment: environment)
            Issue.record("Expected invalid boolean configuration to throw")
        } catch {
            let message = String(describing: error)
            #expect(message.contains("YFSHIP_ORIGIN_RESIDENTIAL"))
            #expect(!message.contains(secret))
        }
    }

    private func originEnvironment() -> [String: String] {
        [
            "YFSHIP_ORIGIN_ADDRESS1": "123 Example St",
            "YFSHIP_ORIGIN_CITY": "Hamilton",
            "YFSHIP_ORIGIN_REGION_CODE": "ON",
            "YFSHIP_ORIGIN_POSTAL_CODE": "L8P 1A1",
            "YFSHIP_ORIGIN_COUNTRY_CODE": "CA"
        ]
    }
}

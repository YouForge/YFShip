import ArgumentParser

enum ProviderID: String, Codable, Sendable, CaseIterable, Equatable, ExpressibleByArgument {
    case chitchats
    case stallion

    init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}

import Foundation

enum BenchmarkDestinationLoader {
    static func load() throws -> [BenchmarkDestination] {
        let data = Data(PackageResources.BenchmarkDestinations_json)
        return try JSONDecoder().decode([BenchmarkDestination].self, from: data)
    }
}

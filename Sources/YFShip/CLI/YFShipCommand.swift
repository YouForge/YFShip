import ArgumentParser

@main
struct YFShipCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "yfship",
        abstract: "Compare shipping rates and calculate benchmark shipping costs."
    )

    mutating func run() async throws {}
}

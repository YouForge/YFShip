import Foundation

struct ShipmentItem: Codable, Sendable, Equatable {
    let description: String
    let quantity: Int
    let valueCAD: Decimal
    let originCountryCode: String
    let hsCode: String?
    let sku: String?
}

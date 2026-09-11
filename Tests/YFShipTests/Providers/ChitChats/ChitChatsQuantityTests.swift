import Foundation
import Testing
@testable import YFShip

@Suite("Chit Chats quantity request fields")
struct ChitChatsQuantityTests {
    @Test("Line-item weight is per unit for U.S. and Canadian requests", arguments: ["US", "CA"], [1, 2, 3])
    func encodesPerUnitWeight(destinationCountry: String, quantity: Int) throws {
        let item = ShipmentItem(
            description: "Synthetic accessory",
            quantity: quantity,
            valueCAD: 20,
            originCountryCode: "CA",
            hsCode: "0000.00",
            sku: "SYNTHETIC-SKU"
        )
        let body = try encodedRequest(items: [item], destinationCountry: destinationCountry)
        let lineItems = try #require(body["line_items"] as? [[String: Any]])
        #expect(lineItems.count == 1)
        let lineItem = try #require(lineItems.first)
        let unitWeight = try #require(lineItem["weight"] as? Double)

        #expect(body["country_code"] as? String == destinationCountry)
        #expect(body["weight"] as? Double == 0.5)
        #expect(body["weight_unit"] as? String == "lb")
        #expect(body["size_x"] as? Double == 6)
        #expect(body["size_y"] as? Double == 4)
        #expect(body["size_z"] as? Double == 1)
        #expect(body["size_unit"] as? String == "in")
        #expect(unitWeight == 0.5 / Double(quantity))
        #expect(abs(unitWeight * Double(quantity) - 0.5) < 1e-12)
        #expect(lineItem["weight_unit"] as? String == "lb")
        #expect(lineItem["quantity"] as? Int == quantity)
        #expect(lineItem["sku_code"] as? String == "SYNTHETIC-SKU")
        #expect(lineItem["hs_tariff_code"] as? String == "0000.00")
        #expect(lineItem["value_amount"] as? String == "20.00")
        #expect(body["value"] as? String == "\(20 * quantity).00")
    }

    @Test("Shipment value sums quantity-scaled values while line values remain per unit", arguments: [
        (1, "35.00"), (2, "62.50"), (3, "90.00")
    ])
    func preservesDeclaredValueSemantics(quantity: Int, expectedTotal: String) throws {
        let items = [
            ShipmentItem(description: "Synthetic accessory", quantity: quantity,
                         valueCAD: 20, originCountryCode: "CA", hsCode: nil, sku: nil),
            ShipmentItem(description: "Synthetic component", quantity: quantity + 1,
                         valueCAD: Decimal(string: "7.50")!, originCountryCode: "CA",
                         hsCode: nil, sku: nil)
        ]
        let body = try encodedRequest(items: items)
        let lineItems = try #require(body["line_items"] as? [[String: Any]])
        #expect(body["value"] as? String == expectedTotal)
        #expect(body["value_currency"] as? String == "cad")
        #expect(lineItems.map { $0["quantity"] as? Int } == [quantity, quantity + 1])
        #expect(lineItems.map { $0["value_amount"] as? String } == ["20.00", "7.50"])
        #expect(lineItems.allSatisfy { $0["currency_code"] as? String == "cad" })
    }

    @Test("Nonpositive quantities cannot produce nonfinite line-item weights", arguments: [0, -1, Int.min])
    func guardsNonpositiveQuantity(quantity: Int) throws {
        let item = ShipmentItem(description: "Synthetic accessory", quantity: quantity,
                                valueCAD: 20, originCountryCode: "CA", hsCode: nil, sku: nil)
        let lineItem = ChitChatsLineItem(item: item, packageWeight: 0.5, origin: testShipment().origin)
        let data = try JSONEncoder().encode(lineItem)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let weight = try #require(body["weight"] as? Double)
        #expect(weight.isFinite)
        #expect(weight == 0.5)
        #expect(body["quantity"] as? Int == quantity)
    }

    private func encodedRequest(
        items: [ShipmentItem],
        destinationCountry: String = "US"
    ) throws -> [String: Any] {
        let base = testShipment()
        let shipment = Shipment(
            origin: base.origin,
            destination: destinationCountry == "US" ? base.destination : base.origin,
            package: base.package,
            items: items
        )
        let data = try JSONEncoder().encode(
            ChitChatsShipmentRequest(shipment: shipment, packageType: "parcel")
        )
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

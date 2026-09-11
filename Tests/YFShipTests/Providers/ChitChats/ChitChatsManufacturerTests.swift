import Foundation
import Testing
@testable import YFShip

@Suite("Chit Chats manufacturer request fields")
struct ChitChatsManufacturerTests {
    @Test("Every line item includes the manufacturer for U.S. and Canadian destinations", arguments: ["US", "CA"], [1, 2, 3])
    func encodesManufacturerFields(destinationCountry: String, quantity: Int) throws {
        let base = testShipment()
        let item = try #require(base.items.first)
        let differentOriginItem = ShipmentItem(
            description: item.description,
            quantity: quantity,
            valueCAD: item.valueCAD,
            originCountryCode: "US",
            hsCode: item.hsCode,
            sku: item.sku
        )
        let shipment = Shipment(
            origin: base.origin,
            destination: destinationCountry == "US" ? base.destination : base.origin,
            package: base.package,
            items: [item, differentOriginItem]
        )

        let body = try encodedRequest(for: shipment)
        #expect(body["country_code"] as? String == destinationCountry)
        #expect(body["address_1"] as? String == shipment.destination.address1)
        #expect(body["package_type"] as? String == "parcel")
        #expect(body["postage_type"] as? String == "unknown")
        let lineItems = try #require(body["line_items"] as? [[String: Any]])
        #expect(lineItems.count == shipment.items.count)
        for (lineItem, expectedItem) in zip(lineItems, shipment.items) {
            #expect(lineItem["manufacturer_contact"] as? String == "Synthetic Sender")
            #expect(lineItem["manufacturer_street"] as? String == "10 Origin St")
            #expect(lineItem["manufacturer_street_2"] == nil)
            #expect(lineItem["manufacturer_city"] as? String == "Hamilton")
            #expect(lineItem["manufacturer_postal_code"] as? String == "L8P 1A1")
            #expect(lineItem["manufacturer_province_code"] as? String == "ON")
            #expect(lineItem["manufacturer_country_code"] as? String == "CA")
            #expect(lineItem["origin_country"] as? String == expectedItem.originCountryCode)
            #expect(lineItem["hs_tariff_code"] as? String == expectedItem.hsCode)
            #expect(lineItem["sku_code"] as? String == expectedItem.sku)
            #expect(lineItem["quantity"] as? Int == expectedItem.quantity)
            #expect(lineItem["value_amount"] as? String == "20.00")
            #expect(lineItem["currency_code"] as? String == "cad")
            #expect(lineItem["weight_unit"] as? String == "lb")
        }
    }

    @Test("Manufacturer contact falls back to company then YouForge and includes street 2", arguments: [true, false])
    func encodesContactFallbackAndStreet2(hasCompany: Bool) throws {
        let base = testShipment()
        let origin = Address(
            name: nil,
            company: hasCompany ? base.origin.company : nil,
            address1: base.origin.address1,
            address2: base.destination.address2,
            city: base.origin.city,
            regionCode: base.origin.regionCode,
            postalCode: base.origin.postalCode,
            countryCode: base.origin.countryCode,
            isResidential: base.origin.isResidential,
            email: base.origin.email,
            phone: base.origin.phone
        )
        let shipment = Shipment(
            origin: origin,
            destination: base.destination,
            package: base.package,
            items: base.items
        )

        let body = try encodedRequest(for: shipment)
        let lineItems = try #require(body["line_items"] as? [[String: Any]])
        let lineItem = try #require(lineItems.first)
        #expect(
            lineItem["manufacturer_contact"] as? String
                == (hasCompany ? "Example Company" : "YouForge")
        )
        #expect(lineItem["manufacturer_street_2"] as? String == "Unit 2")
    }

    private func encodedRequest(for shipment: Shipment) throws -> [String: Any] {
        let data = try JSONEncoder().encode(
            ChitChatsShipmentRequest(shipment: shipment, packageType: "parcel")
        )
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

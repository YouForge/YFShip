import Foundation
import Testing
@testable import YFShip

enum ProviderTestError: Error {
    case missingFixture
    case unexpectedRequest
}

enum ProviderFixture {
    static func data(_ provider: String, _ name: String) throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/\(provider)"
        ) else {
            throw ProviderTestError.missingFixture
        }
        return try Data(contentsOf: url)
    }
}

actor RequestRecorder {
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }

    func snapshot() -> [URLRequest] {
        requests
    }
}

func testHTTPResponse(
    for request: URLRequest,
    statusCode: Int
) throws -> HTTPURLResponse {
    guard let url = request.url,
          let response = HTTPURLResponse(
              url: url,
              statusCode: statusCode,
              httpVersion: nil,
              headerFields: nil
          ) else {
        throw ProviderTestError.unexpectedRequest
    }
    return response
}

func testShipment() -> Shipment {
    Shipment(
        origin: Address(
            name: "Synthetic Sender",
            company: "Example Company",
            address1: "10 Origin St",
            address2: nil,
            city: "Hamilton",
            regionCode: "ON",
            postalCode: "L8P 1A1",
            countryCode: "CA",
            isResidential: false,
            email: "sender@example.invalid",
            phone: "555-0100"
        ),
        destination: Address(
            name: "Synthetic Recipient",
            company: nil,
            address1: "20 Destination Ave",
            address2: "Unit 2",
            city: "Buffalo",
            regionCode: "NY",
            postalCode: "14201",
            countryCode: "US",
            isResidential: true,
            email: nil,
            phone: nil
        ),
        package: ShippingPackage(
            weightLb: 0.5,
            lengthIn: 6,
            widthIn: 4,
            heightIn: 1
        ),
        items: [
            ShipmentItem(
                description: "Synthetic accessory",
                quantity: 1,
                valueCAD: Decimal(20),
                originCountryCode: "CA",
                hsCode: "0000.00",
                sku: "SYNTHETIC-1"
            )
        ]
    )
}

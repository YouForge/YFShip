import Foundation

struct StallionRatesRequest: Encodable, Sendable {
    let type: String
    let toAddress: StallionAddress
    let fromAddress: StallionAddress
    let packages: [StallionPackage]
    let items: [StallionItem]
    let timeout: Int

    init(shipment: Shipment) {
        type = "regular"
        toAddress = StallionAddress(shipment.destination)
        fromAddress = StallionAddress(shipment.origin)
        packages = [
            StallionPackage(
                shipment.package,
                contents: shipment.items.first?.description ?? "Merchandise"
            )
        ]
        items = shipment.items.map(StallionItem.init)
        timeout = 15
    }

    enum CodingKeys: String, CodingKey {
        case type
        case toAddress = "to_address"
        case fromAddress = "from_address"
        case packages
        case items
        case timeout
    }
}

struct StallionAddress: Encodable, Sendable {
    let name: String
    let company: String?
    let address1: String
    let address2: String?
    let city: String
    let provinceCode: String
    let postalCode: String
    let countryCode: String
    let email: String?
    let phone: String?
    let isResidential: Bool

    init(_ address: Address) {
        name = address.name ?? address.company ?? "YouForge Shipment"
        company = address.company
        address1 = address.address1
        address2 = address.address2
        city = address.city
        provinceCode = address.regionCode
        postalCode = address.postalCode
        countryCode = address.countryCode
        email = address.email
        phone = address.phone
        isResidential = address.isResidential
    }

    enum CodingKeys: String, CodingKey {
        case name
        case company
        case address1
        case address2
        case city
        case provinceCode = "province_code"
        case postalCode = "postal_code"
        case countryCode = "country_code"
        case email
        case phone
        case isResidential = "is_residential"
    }
}

struct StallionPackage: Encodable, Sendable {
    let weight: Double
    let weightUnit: String
    let length: Double
    let width: Double
    let height: Double
    let sizeUnit: String
    let packageContents: String

    init(_ package: ShippingPackage, contents: String) {
        weight = package.weightLb
        weightUnit = "lbs"
        length = package.lengthIn
        width = package.widthIn
        height = package.heightIn
        sizeUnit = "in"
        packageContents = contents
    }

    enum CodingKeys: String, CodingKey {
        case weight
        case weightUnit = "weight_unit"
        case length
        case width
        case height
        case sizeUnit = "size_unit"
        case packageContents = "package_contents"
    }
}

struct StallionItem: Encodable, Sendable {
    let title: String
    let description: String
    let customsDescription: String
    let quantity: Int
    let value: Decimal
    let currency: String
    let countryOfOrigin: String
    let hsCode: String?
    let sku: String?

    init(_ item: ShipmentItem) {
        title = item.description
        description = item.description
        customsDescription = item.description
        quantity = item.quantity
        value = item.valueCAD
        currency = "CAD"
        countryOfOrigin = item.originCountryCode
        hsCode = item.hsCode
        sku = item.sku
    }

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case customsDescription = "customs_description"
        case quantity
        case value
        case currency
        case countryOfOrigin = "country_of_origin"
        case hsCode = "hs_code"
        case sku
    }
}

struct StallionRatesResponse: Decodable, Sendable {
    let data: [StallionRate]
}

struct StallionRate: Decodable, Sendable {
    let postageTypeID: String?
    let service: String?
    let carrier: String?
    let serviceName: String?
    let trackable: Bool?
    let subtotal: StallionDecimal?
    let baseRate: StallionDecimal?
    let total: StallionDecimal?
    let currency: String?
    let estimatedDeliveryDays: Int?

    enum CodingKeys: String, CodingKey {
        case postageTypeID = "postage_type_id"
        case service
        case carrier
        case serviceName = "service_name"
        case trackable
        case subtotal
        case baseRate = "base_rate"
        case total
        case currency
        case estimatedDeliveryDays = "estimated_delivery_days"
    }
}

struct StallionDecimal: Decodable, Sendable {
    let value: Decimal

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self),
           let decimal = Decimal(
               string: string,
               locale: Locale(identifier: "en_US_POSIX")
           ) {
            value = decimal
            return
        }

        if let decimal = try? container.decode(Decimal.self) {
            value = decimal
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected a decimal string or number."
        )
    }
}

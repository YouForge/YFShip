import Foundation

struct ChitChatsShipmentRequest: Encodable, Sendable {
    let name: String
    let address1: String
    let address2: String?
    let city: String
    let provinceCode: String
    let postalCode: String
    let countryCode: String
    let packageContents: String
    let description: String
    let value: String
    let valueCurrency: String
    let packageType: String
    let weightUnit: String
    let weight: Double
    let sizeUnit: String
    let sizeX: Double
    let sizeY: Double
    let sizeZ: Double
    let insuranceRequested: Bool
    let signatureRequested: Bool
    let dutiesPaidRequested: Bool
    let postageType: String
    let shipDate: String
    let lineItems: [ChitChatsLineItem]

    init(shipment: Shipment, packageType: String) {
        let destination = shipment.destination
        let declaredValue = shipment.items.reduce(Decimal.zero) { partial, item in
            partial + (item.valueCAD * Decimal(item.quantity))
        }

        name = destination.name ?? "YouForge Shipment"
        address1 = destination.address1
        address2 = destination.address2
        city = destination.city
        provinceCode = destination.regionCode
        postalCode = destination.postalCode
        countryCode = destination.countryCode
        packageContents = "merchandise"
        description = shipment.items.first?.description ?? "Merchandise"
        value = Self.moneyString(declaredValue)
        valueCurrency = "cad"
        self.packageType = packageType
        weightUnit = "lb"
        weight = shipment.package.weightLb
        sizeUnit = "in"
        sizeX = shipment.package.lengthIn
        sizeY = shipment.package.widthIn
        sizeZ = shipment.package.heightIn
        insuranceRequested = false
        signatureRequested = false
        dutiesPaidRequested = false
        postageType = "unknown"
        shipDate = "today"
        lineItems = shipment.items.map {
            ChitChatsLineItem(
                item: $0,
                packageWeight: shipment.package.weightLb
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case name
        case address1 = "address_1"
        case address2 = "address_2"
        case city
        case provinceCode = "province_code"
        case postalCode = "postal_code"
        case countryCode = "country_code"
        case packageContents = "package_contents"
        case description
        case value
        case valueCurrency = "value_currency"
        case packageType = "package_type"
        case weightUnit = "weight_unit"
        case weight
        case sizeUnit = "size_unit"
        case sizeX = "size_x"
        case sizeY = "size_y"
        case sizeZ = "size_z"
        case insuranceRequested = "insurance_requested"
        case signatureRequested = "signature_requested"
        case dutiesPaidRequested = "duties_paid_requested"
        case postageType = "postage_type"
        case shipDate = "ship_date"
        case lineItems = "line_items"
    }

    static func moneyString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }
}

struct ChitChatsLineItem: Encodable, Sendable {
    let quantity: Int
    let description: String
    let valueAmount: String
    let currencyCode: String
    let originCountry: String
    let weight: Double
    let weightUnit: String
    let hsTariffCode: String?
    let skuCode: String?

    init(item: ShipmentItem, packageWeight: Double) {
        quantity = item.quantity
        description = item.description
        valueAmount = ChitChatsShipmentRequest.moneyString(item.valueCAD)
        currencyCode = "cad"
        originCountry = item.originCountryCode
        weight = packageWeight
        weightUnit = "lb"
        hsTariffCode = item.hsCode
        skuCode = item.sku
    }

    enum CodingKeys: String, CodingKey {
        case quantity
        case description
        case valueAmount = "value_amount"
        case currencyCode = "currency_code"
        case originCountry = "origin_country"
        case weight
        case weightUnit = "weight_unit"
        case hsTariffCode = "hs_tariff_code"
        case skuCode = "sku_code"
    }
}

struct ChitChatsShipmentResponse: Decodable, Sendable {
    let id: ChitChatsIdentifier
    let rates: [ChitChatsRate]
}

struct ChitChatsRate: Decodable, Sendable {
    let postageType: String?
    let postageDescription: String?
    let carrier: String?
    let paymentAmount: ChitChatsDecimal?
    let purchaseAmount: ChitChatsDecimal?
    let currency: String?
    let currencyCode: String?
    let tracking: Bool?
    let trackable: Bool?
    let estimatedDeliveryDays: Int?
    let deliveryDays: Int?
    let estimatedDeliveryDaysMax: Int?
    let deliveryTimeMax: Int?
    let deliveryMaxDays: Int?
    let deliveryTimeDescription: String?
    let estimatedDeliveryDescription: String?

    enum CodingKeys: String, CodingKey {
        case postageType = "postage_type"
        case postageDescription = "postage_description"
        case carrier
        case paymentAmount = "payment_amount"
        case purchaseAmount = "purchase_amount"
        case currency
        case currencyCode = "currency_code"
        case tracking
        case trackable
        case estimatedDeliveryDays = "estimated_delivery_days"
        case deliveryDays = "delivery_days"
        case estimatedDeliveryDaysMax = "estimated_delivery_days_max"
        case deliveryTimeMax = "delivery_time_max"
        case deliveryMaxDays = "delivery_max_days"
        case deliveryTimeDescription = "delivery_time_description"
        case estimatedDeliveryDescription = "estimated_delivery_description"
    }

    // Field-level tolerance preserves the shipment ID so cleanup still runs before mapping fails.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        postageType = try? container.decodeIfPresent(
            String.self,
            forKey: .postageType
        )
        postageDescription = try? container.decodeIfPresent(
            String.self,
            forKey: .postageDescription
        )
        carrier = try? container.decodeIfPresent(String.self, forKey: .carrier)
        paymentAmount = try? container.decodeIfPresent(
            ChitChatsDecimal.self,
            forKey: .paymentAmount
        )
        purchaseAmount = try? container.decodeIfPresent(
            ChitChatsDecimal.self,
            forKey: .purchaseAmount
        )
        currency = try? container.decodeIfPresent(String.self, forKey: .currency)
        currencyCode = try? container.decodeIfPresent(
            String.self,
            forKey: .currencyCode
        )
        tracking = try? container.decodeIfPresent(Bool.self, forKey: .tracking)
        trackable = try? container.decodeIfPresent(Bool.self, forKey: .trackable)
        estimatedDeliveryDays = try? container.decodeIfPresent(
            Int.self,
            forKey: .estimatedDeliveryDays
        )
        deliveryDays = try? container.decodeIfPresent(
            Int.self,
            forKey: .deliveryDays
        )
        estimatedDeliveryDaysMax = try? container.decodeIfPresent(
            Int.self,
            forKey: .estimatedDeliveryDaysMax
        )
        deliveryTimeMax = try? container.decodeIfPresent(
            Int.self,
            forKey: .deliveryTimeMax
        )
        deliveryMaxDays = try? container.decodeIfPresent(
            Int.self,
            forKey: .deliveryMaxDays
        )
        deliveryTimeDescription = try? container.decodeIfPresent(
            String.self,
            forKey: .deliveryTimeDescription
        )
        estimatedDeliveryDescription = try? container.decodeIfPresent(
            String.self,
            forKey: .estimatedDeliveryDescription
        )
    }

    var normalizedDeliveryBusinessDays: Int? {
        if let exact = estimatedDeliveryDays ?? deliveryDays {
            return exact
        }

        if let upperBound = estimatedDeliveryDaysMax
            ?? deliveryTimeMax
            ?? deliveryMaxDays {
            return upperBound
        }

        return Self.upperBound(
            from: deliveryTimeDescription ?? estimatedDeliveryDescription
        )
    }

    private static func upperBound(from description: String?) -> Int? {
        guard let description else {
            return nil
        }

        return description
            .split { !$0.isNumber }
            .compactMap { Int($0) }
            .max()
    }
}

struct ChitChatsIdentifier: Decodable, Sendable {
    let value: String

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value = string
            return
        }

        if let integer = try? container.decode(Int.self) {
            value = String(integer)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected a shipment identifier."
        )
    }
}

struct ChitChatsDecimal: Decodable, Sendable {
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

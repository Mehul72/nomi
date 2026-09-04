import Foundation

/// A JSON value, so tool arguments can be validated and stored without `Any`.
nonisolated indirect enum JSONValue: Sendable, Equatable, Hashable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Builds a value from the loosely typed dictionaries that JSONSerialization and MLX produce.
    init?(any value: Any) {
        switch value {
        case let string as String: self = .string(string)
        case let bool as Bool: self = .bool(bool)
        case let number as NSNumber:
            // NSNumber hides booleans; CFBoolean is the only reliable tell.
            if CFGetTypeID(number) == CFBooleanGetTypeID() { self = .bool(number.boolValue) } else { self = .number(number.doubleValue) }
        case let int as Int: self = .number(Double(int))
        case let double as Double: self = .number(double)
        case is NSNull: self = .null
        case let array as [Any]:
            var items: [JSONValue] = []
            for item in array {
                guard let converted = JSONValue(any: item) else { return nil }
                items.append(converted)
            }
            self = .array(items)
        case let object as [String: Any]:
            var items: [String: JSONValue] = [:]
            for (key, item) in object {
                guard let converted = JSONValue(any: item) else { return nil }
                items[key] = converted
            }
            self = .object(items)
        default:
            return nil
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        guard case .number(let value) = self, value == value.rounded(), abs(value) < Double(Int.max) else { return nil }
        return Int(value)
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// The Foundation representation, for JSONSerialization and for handing values to other libraries.
    var anyValue: Any {
        switch self {
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .null: NSNull()
        case .array(let value): value.map(\.anyValue)
        case .object(let value): value.mapValues(\.anyValue)
        }
    }
}

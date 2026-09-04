import Foundation

/// How much a tool can change or expose, which decides whether the user is asked first.
nonisolated enum RiskLevel: String, Codable, Sendable, Comparable {
    case low, medium, high

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        order(lhs) < order(rhs)
    }

    private static func order(_ level: RiskLevel) -> Int {
        switch level {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }
}

nonisolated indirect enum ToolParameterType: Sendable, Equatable {
    case string
    case integer
    case number
    case boolean
    case array(of: ToolParameterType)

    var jsonSchemaType: String {
        switch self {
        case .string: "string"
        case .integer: "integer"
        case .number: "number"
        case .boolean: "boolean"
        case .array: "array"
        }
    }
}

nonisolated struct ToolParameterSpec: Sendable, Equatable {
    var name: String
    var type: ToolParameterType
    var description: String
    var isRequired: Bool
    var allowedValues: [String]?

    static func required(_ name: String, _ type: ToolParameterType, _ description: String, allowedValues: [String]? = nil) -> Self {
        Self(name: name, type: type, description: description, isRequired: true, allowedValues: allowedValues)
    }

    static func optional(_ name: String, _ type: ToolParameterType, _ description: String, allowedValues: [String]? = nil) -> Self {
        Self(name: name, type: type, description: description, isRequired: false, allowedValues: allowedValues)
    }

    var schema: [String: any Sendable] {
        var result: [String: any Sendable] = ["type": type.jsonSchemaType, "description": description]
        if case .array(let element) = type {
            result["items"] = ["type": element.jsonSchemaType] as [String: any Sendable]
        }
        if let allowedValues {
            result["enum"] = allowedValues
        }
        return result
    }
}

nonisolated enum ToolError: LocalizedError, Equatable {
    case unknownTool(String)
    case missingArgument(String)
    case invalidArgument(name: String, reason: String)
    case notPermitted(String)
    case failed(String)
    case timedOut(seconds: Int)
    case offline

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name): "There is no tool called \(name)."
        case .missingArgument(let name): "The argument \(name) is required."
        case .invalidArgument(let name, let reason): "The argument \(name) is invalid: \(reason)."
        case .notPermitted(let reason): reason
        case .failed(let reason): reason
        case .timedOut(let seconds): "The action did not finish within \(seconds) seconds."
        case .offline: "Offline Mode is on, so this action cannot reach the network."
        }
    }
}

/// Validated arguments for one call. Accessors throw a `ToolError` the model can read and correct.
nonisolated struct ToolArguments: Sendable, Equatable {
    let values: [String: JSONValue]

    init(_ values: [String: JSONValue]) {
        self.values = values
    }

    func string(_ name: String) throws -> String {
        guard let value = values[name] else { throw ToolError.missingArgument(name) }
        guard let string = value.stringValue else { throw ToolError.invalidArgument(name: name, reason: "expected text") }
        return string
    }

    func optionalString(_ name: String) throws -> String? {
        guard let value = values[name], value != .null else { return nil }
        guard let string = value.stringValue else { throw ToolError.invalidArgument(name: name, reason: "expected text") }
        return string
    }

    func integer(_ name: String) throws -> Int {
        guard let value = values[name] else { throw ToolError.missingArgument(name) }
        return try Self.integer(from: value, name: name)
    }

    func optionalInteger(_ name: String) throws -> Int? {
        guard let value = values[name], value != .null else { return nil }
        return try Self.integer(from: value, name: name)
    }

    func number(_ name: String) throws -> Double {
        guard let value = values[name] else { throw ToolError.missingArgument(name) }
        return try Self.number(from: value, name: name)
    }

    func optionalNumber(_ name: String) throws -> Double? {
        guard let value = values[name], value != .null else { return nil }
        return try Self.number(from: value, name: name)
    }

    func bool(_ name: String, default fallback: Bool) throws -> Bool {
        guard let value = values[name], value != .null else { return fallback }
        if let bool = value.boolValue { return bool }
        if let string = value.stringValue?.lowercased(), ["true", "false"].contains(string) { return string == "true" }
        throw ToolError.invalidArgument(name: name, reason: "expected true or false")
    }

    func stringArray(_ name: String) throws -> [String] {
        guard let value = values[name] else { throw ToolError.missingArgument(name) }
        if let single = value.stringValue { return [single] }
        guard let array = value.arrayValue else { throw ToolError.invalidArgument(name: name, reason: "expected a list of text values") }
        return try array.map { item in
            guard let string = item.stringValue else { throw ToolError.invalidArgument(name: name, reason: "expected a list of text values") }
            return string
        }
    }

    private static func integer(from value: JSONValue, name: String) throws -> Int {
        if let int = value.intValue { return int }
        if let string = value.stringValue, let int = Int(string) { return int }
        throw ToolError.invalidArgument(name: name, reason: "expected a whole number")
    }

    private static func number(from value: JSONValue, name: String) throws -> Double {
        if let double = value.doubleValue { return double }
        if let string = value.stringValue, let double = Double(string) { return double }
        throw ToolError.invalidArgument(name: name, reason: "expected a number")
    }
}

/// What a tool hands back: text for the model and a short line for the activity timeline.
nonisolated struct ToolResult: Sendable, Equatable {
    var content: String
    var summary: String
    var isError = false

    static func failure(_ message: String) -> ToolResult {
        ToolResult(content: "Error: \(message)", summary: message, isError: true)
    }
}

/// Facts about the environment tools may need, gathered once per request.
nonisolated struct ToolContext: Sendable {
    var isOffline: Bool
    var homeLocation: String?
}

protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: [ToolParameterSpec] { get }
    var risk: RiskLevel { get }
    /// SF Symbol for the activity timeline.
    var symbol: String { get }
    /// Short present-tense verb phrase shown while the tool runs, such as `Checking the weather`.
    func activityLabel(for arguments: ToolArguments) -> String
    /// Plain sentence for the confirmation prompt, stating exactly what will happen.
    func confirmationText(for arguments: ToolArguments) -> String
    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult
}

extension Tool {
    /// The OpenAI-style function schema the model receives.
    var schema: ToolSchema {
        var properties: [String: any Sendable] = [:]
        for parameter in parameters {
            properties[parameter.name] = parameter.schema
        }
        let function: [String: any Sendable] = [
            "name": name,
            "description": description,
            "parameters": [
                "type": "object",
                "properties": properties,
                "required": parameters.filter(\.isRequired).map(\.name),
            ] as [String: any Sendable],
        ]
        return ["type": "function", "function": function]
    }

    /// Checks required parameters and value shapes before anything runs.
    func validate(_ arguments: [String: JSONValue]) throws -> ToolArguments {
        for parameter in parameters {
            guard let value = arguments[parameter.name], value != .null else {
                if parameter.isRequired { throw ToolError.missingArgument(parameter.name) }
                continue
            }
            try Self.check(value, against: parameter)
        }
        return ToolArguments(arguments)
    }

    private static func check(_ value: JSONValue, against parameter: ToolParameterSpec) throws {
        switch parameter.type {
        case .string:
            guard let string = value.stringValue else {
                throw ToolError.invalidArgument(name: parameter.name, reason: "expected text")
            }
            if let allowed = parameter.allowedValues, !allowed.contains(string) {
                throw ToolError.invalidArgument(name: parameter.name, reason: "expected one of \(allowed.joined(separator: ", "))")
            }
        case .integer:
            guard value.intValue != nil || value.stringValue.flatMap(Int.init) != nil else {
                throw ToolError.invalidArgument(name: parameter.name, reason: "expected a whole number")
            }
        case .number:
            guard value.doubleValue != nil || value.stringValue.flatMap(Double.init) != nil else {
                throw ToolError.invalidArgument(name: parameter.name, reason: "expected a number")
            }
        case .boolean:
            guard value.boolValue != nil || ["true", "false"].contains(value.stringValue?.lowercased() ?? "") else {
                throw ToolError.invalidArgument(name: parameter.name, reason: "expected true or false")
            }
        case .array:
            guard value.arrayValue != nil || value.stringValue != nil else {
                throw ToolError.invalidArgument(name: parameter.name, reason: "expected a list")
            }
        }
    }
}

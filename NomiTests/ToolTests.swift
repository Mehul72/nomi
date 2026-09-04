import Foundation
import Testing
@testable import Nomi

struct EchoTool: Tool {
    let name = "echo"
    let description = "Echoes"
    let parameters = [
        ToolParameterSpec.required("text", .string, "Text"),
        ToolParameterSpec.optional("count", .integer, "Repeat"),
        ToolParameterSpec.optional("mode", .string, "Mode", allowedValues: ["loud", "quiet"]),
        ToolParameterSpec.optional("tags", .array(of: .string), "Tags"),
        ToolParameterSpec.optional("flag", .boolean, "Flag"),
    ]
    let risk = RiskLevel.low
    let symbol = "speaker"
    func activityLabel(for arguments: ToolArguments) -> String { "Echoing" }
    func confirmationText(for arguments: ToolArguments) -> String { "Echo?" }
    func execute(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        ToolResult(content: try arguments.string("text"), summary: "Echoed")
    }
}

struct ToolValidationTests {
    let tool = EchoTool()

    @Test func acceptsWellFormedArguments() throws {
        let arguments = try tool.validate(["text": .string("hi"), "count": .number(2), "mode": .string("loud"), "tags": .array([.string("a")]), "flag": .bool(true)])
        #expect(try arguments.string("text") == "hi")
        #expect(try arguments.integer("count") == 2)
        #expect(try arguments.stringArray("tags") == ["a"])
        #expect(try arguments.bool("flag", default: false))
    }

    @Test func missingRequiredArgumentIsReported() {
        #expect(throws: ToolError.missingArgument("text")) {
            try tool.validate(["count": .number(1)])
        }
    }

    @Test func nullCountsAsMissing() {
        #expect(throws: ToolError.missingArgument("text")) {
            try tool.validate(["text": .null])
        }
    }

    @Test func wrongTypesAreRejected() {
        #expect(throws: ToolError.invalidArgument(name: "count", reason: "expected a whole number")) {
            try tool.validate(["text": .string("x"), "count": .string("many")])
        }
        #expect(throws: ToolError.invalidArgument(name: "flag", reason: "expected true or false")) {
            try tool.validate(["text": .string("x"), "flag": .number(1)])
        }
    }

    @Test func numericStringsAreAccepted() throws {
        let arguments = try tool.validate(["text": .string("x"), "count": .string("3")])
        #expect(try arguments.integer("count") == 3)
    }

    @Test func enumValuesAreEnforced() {
        #expect(throws: ToolError.invalidArgument(name: "mode", reason: "expected one of loud, quiet")) {
            try tool.validate(["text": .string("x"), "mode": .string("shout")])
        }
    }

    @Test func singleStringIsAcceptedForArray() throws {
        let arguments = try tool.validate(["text": .string("x"), "tags": .string("solo")])
        #expect(try arguments.stringArray("tags") == ["solo"])
    }

    @Test func schemaListsRequiredParameters() throws {
        let function = try #require(tool.schema["function"] as? [String: any Sendable])
        let parameters = try #require(function["parameters"] as? [String: any Sendable])
        #expect(parameters["required"] as? [String] == ["text"])
        let properties = try #require(parameters["properties"] as? [String: any Sendable])
        #expect((properties["mode"] as? [String: any Sendable])?["enum"] as? [String] == ["loud", "quiet"])
        #expect(((properties["tags"] as? [String: any Sendable])?["items"] as? [String: any Sendable])?["type"] as? String == "string")
    }
}

struct ConfirmationPolicyTests {
    @Test func defaultsAskForMediumAndHigh() {
        let policy = ConfirmationPolicy()
        #expect(!policy.requiresConfirmation(for: .low))
        #expect(policy.requiresConfirmation(for: .medium))
        #expect(policy.requiresConfirmation(for: .high))
    }

    @Test func mediumCanBeSwitchedOffButHighCannot() {
        let policy = ConfirmationPolicy(confirmsMediumRisk: false)
        #expect(!policy.requiresConfirmation(for: .medium))
        #expect(policy.requiresConfirmation(for: .high))
    }

    @Test func onlyMediumRiskGetsADefaultAllowButton() {
        #expect(ConfirmationRequest(id: UUID(), text: "x", risk: .medium).allowIsDefault)
        #expect(!ConfirmationRequest(id: UUID(), text: "x", risk: .high).allowIsDefault)
    }
}

struct FilePathPolicyTests {
    let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    @Test func expandsTildeAndRelativePaths() throws {
        #expect(try FilePathPolicy.resolve("~/Documents/a.txt", home: home).path(percentEncoded: false) == "/Users/tester/Documents/a.txt")
        #expect(try FilePathPolicy.resolve("Downloads/b.pdf", home: home).path(percentEncoded: false) == "/Users/tester/Downloads/b.pdf")
    }

    @Test func refusesSystemAndCredentialLocations() {
        #expect(throws: ToolError.self) { try FilePathPolicy.resolve("/System/Library/x", home: home) }
        #expect(throws: ToolError.self) { try FilePathPolicy.resolve("~/.ssh/id_ed25519", home: home) }
        #expect(throws: ToolError.self) { try FilePathPolicy.resolve("~/Library/Keychains/login.keychain-db", home: home) }
    }

    @Test func allowsOrdinaryLocations() throws {
        _ = try FilePathPolicy.resolve("~/Library/Application Support/Nomi/x", home: home)
        _ = try FilePathPolicy.resolve("/Volumes/External/photo.jpg", home: home)
    }
}

struct HiddenSpanFilterTests {
    @Test func hidesThinkBlocksSplitAcrossChunks() {
        var filter = HiddenSpanFilter()
        var visible = ""
        for chunk in ["Hel", "lo <thi", "nk>secret", " reasoning</th", "ink> world", "!"] {
            visible += filter.feed(chunk)
        }
        visible += filter.finish()
        #expect(visible == "Hello  world!")
    }

    @Test func passesPlainTextThroughIncludingAngleBrackets() {
        var filter = HiddenSpanFilter()
        var visible = filter.feed("a < b and <b>bold</b> ")
        visible += filter.feed("<t")
        visible += filter.finish()
        #expect(visible == "a < b and <b>bold</b> <t")
    }

    @Test func dropsUnfinishedHiddenBlocks() {
        var filter = HiddenSpanFilter()
        var visible = filter.feed("Answer <tool_call>{\"name\":")
        visible += filter.finish()
        #expect(visible == "Answer ")
    }
}

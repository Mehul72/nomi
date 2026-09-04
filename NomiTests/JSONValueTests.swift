import Foundation
import Testing
@testable import Nomi

struct JSONValueTests {
    @Test func decodesEveryShape() throws {
        let data = Data(#"{"s":"x","n":1.5,"i":2,"b":true,"z":null,"a":[1,"two"],"o":{"k":false}}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        let object = try #require(value.objectValue)
        #expect(object["s"] == .string("x"))
        #expect(object["n"] == .number(1.5))
        #expect(object["i"]?.intValue == 2)
        #expect(object["b"] == .bool(true))
        #expect(object["z"] == .null)
        #expect(object["a"] == .array([.number(1), .string("two")]))
        #expect(object["o"] == .object(["k": .bool(false)]))
    }

    @Test func bridgesFromFoundationWithoutConfusingBoolsAndNumbers() throws {
        let raw = try JSONSerialization.jsonObject(with: Data(#"{"flag":true,"count":3,"ratio":0.25}"#.utf8))
        let value = try #require(JSONValue(any: raw))
        #expect(value.objectValue?["flag"] == .bool(true))
        #expect(value.objectValue?["count"] == .number(3))
        #expect(value.objectValue?["ratio"] == .number(0.25))
    }

    @Test func nonIntegralNumbersAreNotInts() {
        #expect(JSONValue.number(2.5).intValue == nil)
        #expect(JSONValue.number(-4).intValue == -4)
        #expect(JSONValue.string("4").intValue == nil)
    }

    @Test func roundTripsThroughEncoding() throws {
        let original: JSONValue = .object(["list": .array([.number(1), .null, .bool(false)]), "name": .string("n")])
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == original)
    }
}

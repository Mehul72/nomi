import CoreGraphics
import Testing
@testable import Nomi

struct InputSynthesizerTests {
    @Test func parsesChordsWithModifiers() throws {
        let chord = try InputSynthesizer.parse("cmd+shift+s")
        #expect(chord.keyCode == 1)
        #expect(chord.flags.contains(.maskCommand))
        #expect(chord.flags.contains(.maskShift))
        #expect(!chord.flags.contains(.maskAlternate))
    }

    @Test func parsesNamedKeysAndAliases() throws {
        #expect(try InputSynthesizer.parse("return").keyCode == 36)
        #expect(try InputSynthesizer.parse("Enter").keyCode == 36)
        #expect(try InputSynthesizer.parse("ctrl+left").flags == [.maskControl])
    }

    @Test func rejectsUnknownKeysAndModifiers() {
        #expect(throws: AutomationError.unknownKey("hyper+x")) { try InputSynthesizer.parse("hyper+x") }
        #expect(throws: AutomationError.unknownKey("cmd+")) { try InputSynthesizer.parse("cmd+") }
        #expect(throws: AutomationError.unknownKey("launch")) { try InputSynthesizer.parse("launch") }
    }
}

struct UIElementSnapshotTests {
    @Test func lineIsCompactAndIndented() {
        let element = UIElementSnapshot(
            id: "e3", role: "AXButton", subrole: nil, title: "Save", description: nil, value: nil, placeholder: nil,
            isEnabled: false, isFocused: true, frame: nil, parentID: "e1", depth: 2, actions: ["AXPress"], childCount: 0
        )
        #expect(element.line == "    [e3] AXButton title=\"Save\" disabled focused actions=AXPress")
    }

    @Test func longValuesAreClipped() {
        let element = UIElementSnapshot(
            id: "e1", role: "AXTextArea", subrole: nil, title: nil, description: nil, value: String(repeating: "x", count: 200),
            placeholder: nil, isEnabled: true, isFocused: false, frame: nil, parentID: nil, depth: 0, actions: [], childCount: 3
        )
        #expect(element.line.contains("…"))
        #expect(element.line.count < 120)
        #expect(element.line.contains("children=3"))
    }

    @Test func snapshotTextListsAppWindowAndTruncation() {
        let snapshot = UISnapshot(appName: "TextEdit", bundleID: "com.apple.TextEdit", windowTitle: "Untitled", elements: [], wasTruncated: true)
        #expect(snapshot.text.hasPrefix("App: TextEdit (com.apple.TextEdit)\nWindow: Untitled"))
        #expect(snapshot.text.contains("more elements not shown"))
    }
}

struct TextRecognizerTests {
    private func line(_ text: String, x: CGFloat, y: CGFloat, height: CGFloat = 14) -> RecognizedLine {
        RecognizedLine(text: text, frame: CGRect(x: x, y: y, width: 100, height: height), confidence: 1)
    }

    @Test func paragraphsBreakOnLargeVerticalGaps() {
        let lines = [line("First", x: 0, y: 0), line("second", x: 0, y: 16), line("Third", x: 0, y: 60)]
        #expect(TextRecognizer.paragraphs(from: lines) == "First\nsecond\n\nThird")
    }

    @Test func emptyInputGivesEmptyText() {
        #expect(TextRecognizer.paragraphs(from: []) == "")
    }
}

struct ScreenDescriptionTests {
    @Test func textIncludesOnlyTheSourcesThatHaveContent() {
        let description = ScreenDescription(
            appName: "Safari", windowTitle: "Apple", source: .ocr, accessibilityText: "",
            recognizedLines: [RecognizedLine(text: "Hello", frame: CGRect(x: 10, y: 20, width: 30, height: 12), confidence: 1)], capture: nil
        )
        #expect(description.text == "App: Safari, window: Apple\n\nText recognised from the window image:\nHello")
        #expect(description.regionListing == "[10,20 30x12] Hello")
    }

    @Test func missingPermissionsAreNamedInTheError() {
        let error = ScreenReadingError.nothingReadable(appName: "Excel", accessibility: false, screenRecording: true)
        #expect(error.localizedDescription.contains("Accessibility permission"))
        #expect(!error.localizedDescription.contains("Screen Recording"))
        let both = ScreenReadingError.nothingReadable(appName: "Excel", accessibility: false, screenRecording: false)
        #expect(both.localizedDescription.contains("Accessibility or Screen Recording"))
    }
}

struct PermissionKindTests {
    @Test func everyKindOpensASystemSettingsPane() {
        for kind in PermissionKind.allCases {
            #expect(kind.settingsURL.scheme == "x-apple.systempreferences")
            #expect(kind.settingsURL.query()?.hasPrefix("Privacy_") == true)
            #expect(!kind.reason.isEmpty)
        }
    }
}

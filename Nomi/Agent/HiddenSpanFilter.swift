import Foundation

/// Drops text between tags the user must never see, such as `<think>` blocks, from a token stream.
nonisolated struct HiddenSpanFilter: Sendable {
    private let tags: [String]
    private var pending = ""
    private var hiddenTag: String?

    init(tags: [String] = ["think", "tool_call"]) {
        self.tags = tags
    }

    /// Feeds one chunk and returns the visible part. Text that might be the start of a tag is held back.
    mutating func feed(_ chunk: String) -> String {
        pending += chunk
        var visible = ""
        while !pending.isEmpty {
            if let tag = hiddenTag {
                let close = "</\(tag)>"
                if let range = pending.range(of: close) {
                    pending = String(pending[range.upperBound...])
                    hiddenTag = nil
                } else {
                    // Keep only the tail that could still be the start of the closing tag.
                    pending = String(pending.suffix(close.count - 1))
                    return visible
                }
                continue
            }

            var earliest: (tag: String, range: Range<String.Index>)?
            for tag in tags {
                if let range = pending.range(of: "<\(tag)>"), earliest == nil || range.lowerBound < earliest!.range.lowerBound {
                    earliest = (tag, range)
                }
            }
            if let earliest {
                visible += pending[..<earliest.range.lowerBound]
                pending = String(pending[earliest.range.upperBound...])
                hiddenTag = earliest.tag
                continue
            }

            // Hold back a possible partial opening tag at the end of the buffer.
            if let lastOpen = pending.lastIndex(of: "<"), Self.couldStartTag(pending[lastOpen...], tags: tags) {
                visible += pending[..<lastOpen]
                pending = String(pending[lastOpen...])
            } else {
                visible += pending
                pending = ""
            }
            return visible
        }
        return visible
    }

    /// Flushes what was held back at the end of a stream.
    mutating func finish() -> String {
        defer { pending = "" }
        return hiddenTag == nil ? pending : ""
    }

    private static func couldStartTag(_ fragment: Substring, tags: [String]) -> Bool {
        tags.contains { "<\($0)>".hasPrefix(fragment) }
    }
}

import SwiftUI

/// The full transcript in a standard window, for answers too long for the notch.
struct ConversationView: View {
    let assistant: Assistant

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(assistant.conversation.enumerated()), id: \.offset) { index, message in
                        ConversationRow(message: message)
                            .id(index)
                    }
                    if assistant.isBusy {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Working…").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            .onChange(of: assistant.conversation.count) { _, count in
                if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .toolbar {
            ToolbarItem {
                Button("New conversation", systemImage: "square.and.pencil") { assistant.startNewConversation() }
            }
        }
    }
}

private struct ConversationRow: View {
    let message: ConversationMessage

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .leading, spacing: 4) {
                Text("You").font(.caption).foregroundStyle(.secondary)
                Text(message.content).textSelection(.enabled)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 4) {
                Text("Nomi").font(.caption).foregroundStyle(.secondary)
                if !message.content.isEmpty {
                    Text(MarkdownText.rendered(message.content)).textSelection(.enabled)
                }
                ForEach(message.toolCalls, id: \.id) { call in
                    Label(call.name, systemImage: "wrench.and.screwdriver").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .tool:
            Text(message.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .textSelection(.enabled)
        case .system:
            EmptyView()
        }
    }
}

enum MarkdownText {
    static func rendered(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

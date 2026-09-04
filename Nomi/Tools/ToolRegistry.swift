import Foundation

/// The tools the agent may offer the model. Disabled tools stay registered but are neither advertised nor run.
final class ToolRegistry {
    private var tools: [String: any Tool] = [:]
    private var order: [String] = []
    private(set) var disabledNames: Set<String> = []

    init(tools: [any Tool] = []) {
        tools.forEach(register)
    }

    func register(_ tool: any Tool) {
        if tools[tool.name] == nil { order.append(tool.name) }
        tools[tool.name] = tool
    }

    func setEnabled(_ enabled: Bool, name: String) {
        if enabled { disabledNames.remove(name) } else { disabledNames.insert(name) }
    }

    var allTools: [any Tool] {
        order.compactMap { tools[$0] }
    }

    var enabledTools: [any Tool] {
        allTools.filter { !disabledNames.contains($0.name) }
    }

    func tool(named name: String) -> (any Tool)? {
        guard !disabledNames.contains(name) else { return nil }
        return tools[name]
    }

    var schemas: [ToolSchema] {
        enabledTools.map(\.schema)
    }
}

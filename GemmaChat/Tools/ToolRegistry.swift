import Foundation

final class ToolRegistry {
    private var tools: [String: any Tool] = [:]

    func register(_ tool: any Tool) {
        tools[tool.name] = tool
    }

    func get(_ name: String) -> (any Tool)? {
        tools[name]
    }

    var allTools: [any Tool] {
        Array(tools.values)
    }

    func systemPromptDescription() -> String {
        tools.values.map { tool in
            let params = tool.parameters.map { p in
                let req = p.required ? "(필수)" : "(선택)"
                return "    - \(p.name) \(req): \(p.description)"
            }.joined(separator: "\n")
            return "- \(tool.name): \(tool.description)\n\(params)"
        }.joined(separator: "\n")
    }

    static func createDefault() -> ToolRegistry {
        let registry = ToolRegistry()
        registry.register(AppLauncherTool())
        registry.register(WebSearchTool())
        registry.register(DateTimeTool())
        registry.register(DeviceInfoTool())
        registry.register(ClipboardTool())
        registry.register(MapsTool())
        registry.register(MessageTool())
        registry.register(PhoneCallTool())
        registry.register(SettingsTool())
        registry.register(ShortcutTool())
        registry.register(ReminderTool())
        registry.register(BrightnessTool())
        registry.register(SearchContactsTool())
        registry.register(AddContactTool())
        registry.register(FetchInfoTool())
        registry.register(ReadCalendarTool())
        registry.register(CreateCalendarEventTool())
        registry.register(SaveMemoTool())
        registry.register(ReadMemoTool())
        return registry
    }
}

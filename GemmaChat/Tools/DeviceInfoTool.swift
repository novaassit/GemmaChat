import UIKit

struct DeviceInfoTool: Tool {
    let name = "get_device_info"
    let description = "Returns device model, name, OS version, and battery information"
    let parameters: [ToolParameter] = []

    func execute(arguments: [String: String]) async -> ToolResult {
        let info = await MainActor.run {
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true

            let batteryLevel = device.batteryLevel >= 0
                ? "\(Int(device.batteryLevel * 100))%"
                : "Unknown"

            let batteryState: String
            switch device.batteryState {
            case .unknown:    batteryState = "Unknown"
            case .unplugged:  batteryState = "Unplugged"
            case .charging:   batteryState = "Charging"
            case .full:       batteryState = "Full"
            @unknown default: batteryState = "Unknown"
            }

            return """
            Model: \(device.model)
            Name: \(device.name)
            System: \(device.systemName) \(device.systemVersion)
            Battery: \(batteryLevel) (\(batteryState))
            """
        }

        return .ok(info)
    }
}

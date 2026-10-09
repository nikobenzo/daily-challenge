/// The few words that name the device and its system in status text. Each app passes
/// its own value, so the shared models never need to know which platform they run on.
public struct DeviceWording: Sendable, Equatable {
    /// "Mac", "iPhone": as in "Saved on this Mac".
    public let device: String
    /// "macOS", "iOS": as in "Delivery depends on macOS and Focus".
    public let system: String
    /// Where a person turns this app's notifications back on.
    public let notificationSettings: String
    /// Where a person checks the device clock.
    public let dateTimeSettings: String

    public init(device: String, system: String, notificationSettings: String, dateTimeSettings: String) {
        self.device = device
        self.system = system
        self.notificationSettings = notificationSettings
        self.dateTimeSettings = dateTimeSettings
    }

    public static let mac = DeviceWording(
        device: "Mac", system: "macOS",
        notificationSettings: "System Settings > Notifications > Daily Challenge",
        dateTimeSettings: "Date & Time")

    public static let iPhone = DeviceWording(
        device: "iPhone", system: "iOS",
        notificationSettings: "Settings > Notifications > Daily Challenge",
        dateTimeSettings: "Settings > General > Date & Time")
}

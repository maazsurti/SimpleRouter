import Foundation

/// Channels a navigation trace belongs to. Its raw value is the `category`
/// passed to the injected `Log`, so an app's logger can filter or tag by it.
public enum RouterLogCategory: String {
    /// Root switches and navigation stack mutations.
    case router = "ROUTER"

    /// Incoming URL receipt, handling, and clearing.
    case url = "URL"

    /// Sheet, cover, alert, and confirmation dialog state changes.
    case presentation = "PRESENTATION"
}

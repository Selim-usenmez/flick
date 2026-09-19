import AppKit
import ApplicationServices

/// Finds the Dock icon under a screen point, and the app it represents, using the
/// Accessibility API on the Dock process itself (`com.apple.dock`) rather than anything in
/// this app's own process.
struct DockItemLocator {
    struct Located {
        let axItem: AXUIElement
        /// Icon frame in Quartz global coordinates — same space as `WindowLocator`.
        let frame: CGRect
        let displayName: String
        let bundleURL: URL?
    }

    /// Extra margin around each icon's hit box — Dock icons are small and packed tightly.
    private static let hitTolerance: CGFloat = 4

    /// - Parameter point: a point in AppKit screen coordinates, e.g. from
    ///   `NSEvent.mouseLocation`.
    static func item(at point: NSPoint) -> Located? {
        guard let dockPID = dockProcessID(),
              let items = dockItemList(forPID: dockPID)
        else { return nil }

        let quartzPoint = ScreenGeometry.quartzPoint(fromAppKit: point)

        for item in items {
            guard isApplicationItem(item),
                  let frame = WindowLocator.frame(of: item),
                  frame.insetBy(dx: -hitTolerance, dy: -hitTolerance).contains(quartzPoint)
            else { continue }

            return Located(
                axItem: item,
                frame: frame,
                displayName: title(of: item) ?? "",
                bundleURL: url(of: item)
            )
        }
        return nil
    }

    private static func dockProcessID() -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.apple.dock" }
            .map { pid_t($0.processIdentifier) }
    }

    /// The Dock exposes its icons as: application → one `AXList` child → one `AXUIElement`
    /// per icon (apps, folders, minimized windows, the trash...).
    private static func dockItemList(forPID pid: pid_t) -> [AXUIElement]? {
        let dockApp = AXUIElementCreateApplication(pid)

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockApp, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement],
              let list = children.first
        else { return nil }

        var itemsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &itemsRef) == .success,
              let items = itemsRef as? [AXUIElement]
        else { return nil }
        return items
    }

    private static func isApplicationItem(_ item: AXUIElement) -> Bool {
        var subroleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXSubroleAttribute as CFString, &subroleRef) == .success,
              let subrole = subroleRef as? String
        else { return false }
        return subrole == "AXApplicationDockItem"
    }

    private static func title(of item: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef) == .success else { return nil }
        return titleRef as? String
    }

    /// Application Dock items expose the on-disk location of the app bundle via `AXURL`.
    private static func url(of item: AXUIElement) -> URL? {
        var urlRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &urlRef) == .success else { return nil }
        return urlRef as? URL
    }
}

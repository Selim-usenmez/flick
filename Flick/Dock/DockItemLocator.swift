import AppKit
import ApplicationServices

/// Finds the Dock icon under a screen point, and the app it represents, using the
/// Accessibility API on the Dock process itself (`com.apple.dock`) rather than anything in
/// this app's own process.
struct DockItemLocator {
    /// The Dock hosts two different kinds of gesture-able item: a running/launchable app's
    /// own icon, and — in the section right before the Trash — a thumbnail representing one
    /// specific minimized window. They need different handling: an app item can be resolved
    /// to an `NSRunningApplication` (`AXURL` gives its bundle); a minimized-window item
    /// can't be — it exposes no `AXURL`, and its `AXTopLevelUIElement` resolves to the Dock
    /// process itself, not to the window's owning app (confirmed empirically, since this
    /// isn't documented anywhere). Its only reliable action is `AXPress`, exactly what a
    /// real click does — restore that exact window.
    enum Kind {
        case application
        case minimizedWindow
    }

    struct Located {
        let axItem: AXUIElement
        /// Icon frame in Quartz global coordinates — same space as `WindowLocator`.
        let frame: CGRect
        let displayName: String
        let bundleURL: URL?
        let kind: Kind
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
            guard let kind = kind(of: item),
                  let frame = WindowLocator.frame(of: item),
                  frame.insetBy(dx: -hitTolerance, dy: -hitTolerance).contains(quartzPoint)
            else { continue }

            return Located(
                axItem: item,
                frame: frame,
                displayName: title(of: item) ?? "",
                bundleURL: url(of: item),
                kind: kind
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

    private static func kind(of item: AXUIElement) -> Kind? {
        var subroleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXSubroleAttribute as CFString, &subroleRef) == .success,
              let subrole = subroleRef as? String
        else { return nil }
        switch subrole {
        case "AXApplicationDockItem": return .application
        case "AXMinimizedWindowDockItem": return .minimizedWindow
        default: return nil
        }
    }

    private static func title(of item: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef) == .success else { return nil }
        return titleRef as? String
    }

    /// Application Dock items expose the on-disk location of the app bundle via `AXURL`.
    /// Minimized-window items don't (there's genuinely no value — `AXUIElementCopyAttributeValue`
    /// returns `.noValue` for it, not just an empty result), so this returns `nil` for those.
    private static func url(of item: AXUIElement) -> URL? {
        var urlRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &urlRef) == .success else { return nil }
        return urlRef as? URL
    }
}

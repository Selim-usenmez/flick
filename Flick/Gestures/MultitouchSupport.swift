import CoreFoundation
import Foundation

/// One trackpad finger's raw data for a single frame, laid out to match the private
/// `MultitouchSupport.framework`'s reverse-engineered `Finger` struct (widely documented in
/// open-source trackpad-visualizer projects; not from an Apple header, since none ships).
/// `normalizedX/Y` range roughly 0...1 across the trackpad surface.
struct MTFinger {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerID: Int32
    var handID: Int32
    var normalizedX: Float
    var normalizedY: Float
    var normalizedVelX: Float
    var normalizedVelY: Float
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var mmX: Float
    var mmY: Float
    var mmVelX: Float
    var mmVelY: Float
    var zero2a: Int32
    var zero2b: Int32
    var unknown2: Float
}

private typealias MTDeviceRef = UnsafeMutableRawPointer
// The fingers parameter is typed as a raw pointer, not `UnsafeMutablePointer<MTFinger>`:
// `@convention(c)` requires every type in the signature to be "representable in
// Objective-C", and a plain Swift struct (even one built entirely from C-compatible
// primitive fields) never qualifies, structs can't be `@objc`. Rebind to `MTFinger` inside
// the callback body instead, where that check doesn't apply.
private typealias MTContactCallback = @convention(c) (
    MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32
) -> Int32

private typealias MTDeviceCreateListFn = @convention(c) () -> CFMutableArray?
private typealias MTRegisterContactFrameCallbackFn = @convention(c) (MTDeviceRef?, MTContactCallback?) -> Void
private typealias MTUnregisterContactFrameCallbackFn = @convention(c) (MTDeviceRef?, MTContactCallback?) -> Void
private typealias MTDeviceStartFn = @convention(c) (MTDeviceRef?, Int32) -> Void
private typealias MTDeviceStopFn = @convention(c) (MTDeviceRef?) -> Void

/// Dynamically-loaded (`dlopen`/`dlsym`) binding to Apple's private
/// `MultitouchSupport.framework` — there's no public header to link against, so every
/// symbol is resolved by name at runtime instead of at build time.
///
/// This exists because `NSEvent`'s `.magnify`/`.rotate` gesture types — and even a raw,
/// session-wide `CGEventTap` — are only ever delivered to whichever app is frontmost; there
/// is no supported (or unsupported-but-reachable) way to observe a pinch gesture from a
/// background app while a *different* app has focus. Reading raw finger contacts directly
/// from the trackpad driver, bypassing AppKit's gesture recognition and focus routing
/// entirely, is the only way — and is what utilities like BetterTouchTool/Swish actually do
/// under the hood. Undocumented; could break on a future macOS release.
final class MultitouchSupport {
    static let shared = MultitouchSupport()

    private var deviceCreateList: MTDeviceCreateListFn?
    private var registerCallback: MTRegisterContactFrameCallbackFn?
    private var unregisterCallback: MTUnregisterContactFrameCallbackFn?
    private var deviceStart: MTDeviceStartFn?
    private var deviceStop: MTDeviceStopFn?
    private var devices: [MTDeviceRef] = []

    private(set) var isAvailable = false

    /// Called with every finger touching the trackpad in the current frame. Fires on a
    /// framework-owned background thread — hop to main before touching UI/AppKit state.
    var onFrame: (([MTFinger]) -> Void)?

    private init() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_NOW
        ) else { return }

        guard let createListSym = dlsym(handle, "MTDeviceCreateList"),
              let registerSym = dlsym(handle, "MTRegisterContactFrameCallback"),
              let unregisterSym = dlsym(handle, "MTUnregisterContactFrameCallback"),
              let startSym = dlsym(handle, "MTDeviceStart"),
              let stopSym = dlsym(handle, "MTDeviceStop")
        else { return }

        deviceCreateList = unsafeBitCast(createListSym, to: MTDeviceCreateListFn.self)
        registerCallback = unsafeBitCast(registerSym, to: MTRegisterContactFrameCallbackFn.self)
        unregisterCallback = unsafeBitCast(unregisterSym, to: MTUnregisterContactFrameCallbackFn.self)
        deviceStart = unsafeBitCast(startSym, to: MTDeviceStartFn.self)
        deviceStop = unsafeBitCast(stopSym, to: MTDeviceStopFn.self)
        isAvailable = true
    }

    func start() {
        guard isAvailable, devices.isEmpty,
              let deviceCreateList, let registerCallback, let deviceStart,
              let list = deviceCreateList()
        else { return }

        let count = CFArrayGetCount(list)
        for index in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            registerCallback(device, multitouchFrameCallback)
            deviceStart(device, 0)
            devices.append(device)
        }
    }

    /// Unregisters the frame callback before stopping each device — without this, the next
    /// `start()` would register `multitouchFrameCallback` a second time on top of the
    /// still-registered first one (the framework doesn't dedupe), so every real frame
    /// after one enable/disable cycle would be delivered twice, then three times, etc.,
    /// corrupting pinch-distance tracking.
    func stop() {
        guard let deviceStop else { return }
        for device in devices {
            unregisterCallback?(device, multitouchFrameCallback)
            deviceStop(device)
        }
        devices.removeAll()
    }
}

/// Non-capturing C callback — `MTRegisterContactFrameCallback` has no `userInfo` slot, so
/// state travels through the `MultitouchSupport.shared` singleton instead.
private func multitouchFrameCallback(
    device: UnsafeMutableRawPointer?,
    fingersRaw: UnsafeMutableRawPointer?,
    fingerCount: Int32,
    timestamp: Double,
    frame: Int32
) -> Int32 {
    guard let fingersRaw, fingerCount > 0 else { return 0 }
    let fingers = fingersRaw.assumingMemoryBound(to: MTFinger.self)
    let buffer = UnsafeBufferPointer(start: fingers, count: Int(fingerCount))
    MultitouchSupport.shared.onFrame?(Array(buffer))
    return 0
}

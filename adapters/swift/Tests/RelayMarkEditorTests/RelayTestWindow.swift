#if !os(macOS)
import UIKit

/// A window for UIKit tests. `UIWindow(frame:)` and `UIWindow()` are deprecated since
/// iOS 26 in favour of `init(windowScene:)`, but a SwiftPM test process (xctest) has no
/// window scene to give it. Constructing through `NSObject.Type` is the same `-init`
/// without the deprecation diagnostic, and keeps this one call site the only place to
/// change when the tests gain a scene host.
@MainActor
func relayTestWindow(width: CGFloat, height: CGFloat = 600) -> UIWindow {
    guard let window = (UIWindow.self as NSObject.Type).init() as? UIWindow else {
        preconditionFailure("UIWindow did not initialize")
    }
    window.frame = CGRect(x: 0, y: 0, width: width, height: height)
    return window
}
#endif

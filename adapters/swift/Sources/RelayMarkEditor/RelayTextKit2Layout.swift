import Foundation
import SwiftUI
import RelayMarkEditorCore
#if os(macOS)
import AppKit
typealias LayoutColor = NSColor
#else
import UIKit
typealias LayoutColor = UIColor
#endif

extension LayoutColor {
    static var labelColorCompat: LayoutColor {
        #if os(macOS)
        .labelColor
        #else
        .label
        #endif
    }
    static var secondaryLabelColorCompat: LayoutColor {
        #if os(macOS)
        .secondaryLabelColor
        #else
        .secondaryLabel
        #endif
    }
    static var separatorColorCompat: LayoutColor {
        #if os(macOS)
        .separatorColor
        #else
        .separator
        #endif
    }
}

/// Symmetric native text-container insets and line-fragment padding.
enum RelayPaperMargins {
    static let trailing: CGFloat = 5
    static let leading: CGFloat = 5
    static let linePadding: CGFloat = 5
}

public extension RelayMarkEditorView {
    /// Native text inset plus TextKit's line-fragment padding, for host alignment.
    static var textInsets: (leading: CGFloat, trailing: CGFloat) {
        (RelayPaperMargins.leading + RelayPaperMargins.linePadding, RelayPaperMargins.trailing + RelayPaperMargins.linePadding)
    }
}

#if os(macOS) && DEBUG
/// TextKit 1 compatibility mode is a one-way switch away from the paper's
/// TextKit 2 layout. Debug builds and tests stop at the first paper
/// view that takes it. UIKit posts no notification; its views assert in layout.
@MainActor enum RelayTextKit1Guard {
    private static var installed = false
    static func install() {
        guard !installed else { return }
        installed = true
        NotificationCenter.default.addObserver(forName: NSTextView.willSwitchToNSLayoutManagerNotification,
                                               object: nil, queue: nil) { note in
            guard note.object is CollaborationTextView else { return }
            assertionFailure("A paper text view switched to TextKit 1 compatibility mode")
        }
    }
}
#endif

/// A system-measured SwiftUI attachment surface shared by preserved tables and
/// inline content. Hosting controllers own all text and control layout.
/// See NSHostingController.sizeThatFits(in:) and UIHostingController.sizeThatFits(in:).
@MainActor
class RelayHostingAttachmentView<Content: View>: PlatformTableView {
    #if os(macOS)
    private let host: NSHostingController<Content>
    #else
    private let host: UIHostingController<Content>
    #endif

    var rootView: Content {
        get { host.rootView }
        set { host.rootView = newValue }
    }

    init(rootView: Content) {
        #if os(macOS)
        host = NSHostingController(rootView: rootView)
        #else
        host = UIHostingController(rootView: rootView)
        #endif
        super.init(frame: .zero)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        #if !os(macOS)
        backgroundColor = .clear
        host.view.backgroundColor = .clear
        #endif
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    #if os(macOS)
    override var isFlipped: Bool { true }
    #endif

    @discardableResult func layout(width: CGFloat) -> CGSize {
        let measured = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        frame.size = measured
        return measured
    }
}

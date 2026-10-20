import Foundation
@testable import RelayMarkEditor
import Testing
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
import RelayMarkSwift
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
struct RelayMarkEditorProseCodecTests {
    @Test func typingPreservesStoredMarksWhileExplicitFontChangeCanRemoveThem() {
        var marked = AttributedString("Bold 🌍")
        marked.inlinePresentationIntent = .stronglyEmphasized
        let native = NSMutableAttributedString(attributedString: NativeProseCodec.attributed(marked))
        #if os(macOS)
        let plain = NSFont.systemFont(ofSize: 15)
        #else
        let plain = UIFont.systemFont(ofSize: 15)
        #endif
        native.addAttribute(.font, value: plain, range: NSRange(location: 0, length: native.length))
        let typed = NativeProseCodec.value(native, inferFontChanges: false)
        #expect(typed.runs.allSatisfy { ($0.inlinePresentationIntent ?? []).contains(.stronglyEmphasized) })
        let formatted = NativeProseCodec.value(native, inferFontChanges: true)
        #expect(formatted.runs.allSatisfy { !($0.inlinePresentationIntent ?? []).contains(.stronglyEmphasized) })
        #expect(NativeProseCodec.value(native) == formatted) // Source-compatible default.
    }

    @Test func ruleIsOneNativeAttachmentWithAccessibleDescriptionAndAdaptiveWidth() throws {
        var rule = AttributedString("\u{FFFC}")
        rule.presentationIntent = PresentationIntent(.thematicBreak, identity: 1)
        let native = NativeProseCodec.attributed(rule)
        #expect(native.length == 1)
        #expect(native.string == "\u{FFFC}")
        let attachment = try #require(native.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        let container = NSTextContainer(size: CGSize(width: 300, height: 100))
        let location = NSTextContentStorage().documentRange.location
        func bounds(_ width: CGFloat) -> CGRect {
            attachment.attachmentBounds(for: [:], location: location, textContainer: container,
                proposedLineFragment: CGRect(x: 0, y: 0, width: width, height: 20), position: .zero)
        }
        let wide = bounds(300), narrow = bounds(100)
        #expect(wide.width > narrow.width)
        #expect(narrow.width > 0 && narrow.width <= 100)
        let image = try #require(attachment.image(for: wide, attributes: [:], location: location, textContainer: container))
        #if os(macOS)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let visibleRows = (0..<bitmap.pixelsHigh).filter {
            (bitmap.colorAt(x: bitmap.pixelsWide / 2, y: $0)?.alphaComponent ?? 0) > 0
        }
        #expect(!visibleRows.isEmpty && visibleRows.count < bitmap.pixelsHigh)
        #expect(image.accessibilityDescription == "Horizontal rule")
        #else
        #expect(attachment.accessibilityLabel == "Horizontal rule")
        #endif
        #expect(NativeProseCodec.value(native).presentationIntent == rule.presentationIntent)
        #expect(String(NativeProseCodec.value(native).characters) == "\u{FFFC}")
    }

    @Test func hardBreakRetainsUTF16PositionsWithoutBecomingAnAttachment() {
        let original = AttributedString("a\u{2028}😀b")
        let native = NativeProseCodec.attributed(original)
        #expect(native.length == 5)
        #expect(native.attribute(.attachment, at: 1, effectiveRange: nil) == nil)
        #expect(String(NativeProseCodec.value(native).characters) == String(original.characters))
    }

    #if os(macOS)
    @Test func nativeBackwardDeleteRemovesExactlyTheRuleAtom() {
        var rule = AttributedString("\u{FFFC}")
        rule.presentationIntent = PresentationIntent(.thematicBreak, identity: 2)
        let native = NSMutableAttributedString(attributedString: NativeProseCodec.attributed(AttributedString("before\n")))
        native.append(NativeProseCodec.attributed(rule))
        native.append(NSAttributedString(string: "\nafter"))
        let view = CollaborationTextView.textKit2(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        view.isEditable = true
        view.textStorage?.setAttributedString(native)
        view.setSelectedRange(NSRange(location: 8, length: 0))
        view.deleteBackward(nil)
        #expect(view.string == "before\n\nafter")
        #expect(view.selectedRange() == NSRange(location: 7, length: 0))
    }
    #endif

    @Test func formattingAcrossHardBreakTargetsBothTextLeavesAndSkipsRule() throws {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST:
            RelayMarkSourceCodec.parseDocument("left  \nright\n\n---\n\ntail", namespace: "native-hard-break"))
        let session = try RelayMarkEditorSession(document: document, persist: { _ in })
        #expect(session.isEditable)
        var bold = session.text
        bold.inlinePresentationIntent = .stronglyEmphasized
        session.editFormatting(bold, command: .init(baseline: session.text,
            range: NSRange(location: 0, length: String(session.text.characters).utf16.count), mark: .bold))
        #expect(session.failure == nil)
        // Check the canonical projection rather than assuming a flattened first XmlText child.
        let projection = try document.richProseProjection()
        let text = String(projection.text.characters)
        #expect(text.contains("left\u{2028}right"))
        #expect(text.contains("\u{FFFC}"))
        let ranges = projection.textRanges(in: NSRange(location: 0, length: text.utf16.count))
        #expect(ranges.count == 3)
        #expect(ranges.map(\.length) == [4, 5, 4])
        for run in projection.text.runs {
            let content = String(projection.text[run.range].characters)
            if content == "left" || content == "right" || content == "tail" {
                #expect(run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
            }
        }
    }
}

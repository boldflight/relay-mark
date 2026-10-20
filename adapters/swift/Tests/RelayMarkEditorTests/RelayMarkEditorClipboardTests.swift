import Foundation
@testable import RelayMarkEditor
import XCTest
import RelayMarkSwift
import RelayMarkCollaboration
import RelayMarkNativeCollaboration
#if os(macOS)
import AppKit
#endif

@MainActor
final class RelayMarkEditorClipboardTests: XCTestCase {
    func testSecondFragmentAdmissionRefusalKeepsBothOriginalsAndUnchangedTarget() async throws {
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("Before", namespace: "multi-target"))
        var writes = 0
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in writes += 1 })
        editor.setNativeSelection(NSRange(location: 3, length: 0))
        let before = try document.encodeUpdate(), capture = try editor.captureStructuredPaste()
        let edit = try editor.prepareStructuredClipboards(html: ["<p>First</p>", "<p>Second</p>"], capture: capture)
        var admissions = 0
        do {
            try await editor.insertStructuredPaste(edit, authorize: { _ in
                admissions += 1
                if admissions == 2 { throw CancellationError() }
            })
            XCTFail("Second original refusal must stop the whole operation")
        } catch is CancellationError {}
        XCTAssertEqual(admissions, 2); XCTAssertEqual(writes, 0)
        XCTAssertEqual(try document.encodeUpdate(), before)
    }
    #if os(macOS)
    func testActualImagePasteCapturesTheOriginalBeforePlatformConversion() throws {
        // This serial case owns/restores the actual OS pasteboard. No upload
        // receipt or media authorization is fabricated by this intake proof.
        let pasteboard = NSPasteboard.general
        let previous = (pasteboard.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
        var ownedCount: Int?
        defer {
            if let ownedCount {
                if pasteboard.changeCount == ownedCount {
                    pasteboard.clearContents()
                    let items = previous.map { fields in let item = NSPasteboardItem(); for (type, bytes) in fields { item.setData(bytes, forType: type) }; return item }
                    XCTAssertTrue(items.isEmpty || pasteboard.writeObjects(items))
                } else { XCTFail("Clipboard changed outside this operation; refusing to overwrite it") }
            }
        }
        let document = RelayMarkNativeDocument()
        _ = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("Before after", namespace: "image-os-target"))
        let before = try document.encodeUpdate()
        var writes = 0, reservations = 0, delivered: Data?
        let editor = try RelayMarkEditorSession(document: document, persist: { _ in writes += 1 })
        let coordinator = RelayMarkEditorView.TextCoordinator(session: editor)
        coordinator.services = RelayMarkEditorServices(images: ClosureImages { range, filename, contentType in
            XCTAssertEqual(range, NSRange(location: 7, length: 0))
            XCTAssertEqual(contentType, "image/png"); XCTAssertFalse(filename.isEmpty)
            reservations += 1
            return RelayMarkImageIntake(maximumBytes: 1 << 20, receive: { delivered = $0 }, failure: { XCTFail($0) })
        })
        let view = coordinator.makeTextView(accessibilityLabel: "Canonical image paste")
        defer { coordinator.retire(view) }
        view.setSelectedRange(NSRange(location: 7, length: 0))
        let bytes = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jGHoAAAAASUVORK5CYII="))
        let item = NSPasteboardItem(); XCTAssertTrue(item.setData(bytes, forType: .png))
        pasteboard.clearContents(); ownedCount = pasteboard.changeCount
        XCTAssertTrue(pasteboard.writeObjects([item])); ownedCount = pasteboard.changeCount
        view.paste(nil)
        XCTAssertEqual(reservations, 1, "Raw image paste must enter captured custody, not the platform attachment converter")
        XCTAssertEqual(delivered, bytes, "The exact OS bytes must reach the same image input owner")
        XCTAssertEqual(writes, 0); XCTAssertEqual(try document.encodeUpdate(), before)
        var failures = 0
        coordinator.onImageInputFailure = { _ in failures += 1 }
        let html = NSPasteboardItem(); XCTAssertTrue(html.setString("<p>Separate human item</p>", forType: .html))
        // AppKit keeps an item associated with its first pasteboard write even
        // after clearing. Model the new mixed paste with a fresh item, same bytes.
        let mixedImage = NSPasteboardItem(); XCTAssertTrue(mixedImage.setData(bytes, forType: .png))
        pasteboard.clearContents(); ownedCount = pasteboard.changeCount
        XCTAssertTrue(pasteboard.writeObjects([html, mixedImage])); ownedCount = pasteboard.changeCount
        view.paste(nil)
        XCTAssertEqual(failures, 1, "Mixed HTML/image input must refuse visibly without inserting a subset")
        XCTAssertEqual(reservations, 1); XCTAssertEqual(writes, 0)
        XCTAssertEqual(try document.encodeUpdate(), before)
    }

    #endif
}

/// PNG images up to 1 MB, reserved through `begin`.
private struct ClosureImages: RelayMarkImageService {
    let begin: (NSRange, String, String) -> RelayMarkImageIntake?
    var acceptedImageTypes: Set<String> { ["image/png"] }
    var maximumImageBytes: Int { 1 << 20 }
    func beginImageInput(at range: NSRange, filename: String, contentType: String) -> RelayMarkImageIntake? {
        begin(range, filename, contentType)
    }
    func beginImageInputs(at range: NSRange, files: [RelayMarkImageFile]) -> [RelayMarkImageIntake]? { nil }
}

import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkModel
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkClipboardFitTraceTests: XCTestCase {
    private func node(_ name: String, _ content: [PMNode], _ schema: PMSchema) throws -> PMNode {
        try XCTUnwrap(schema.nodes[name]).create(nil, PMFragment.fromArray(content))
    }
    func testEqualRetainedTextDoesNotDetermineCopiedPlacement() throws {
        let schema = try PMYXmlBridge.canonical().schema
        let target = try node("doc", [node("paragraph", [schema.text(Array("same same".utf16))], schema)], schema)
        let source = PMSlice(PMFragment.from(schema.text(Array("same".utf16))), openStart: 0, openEnd: 0)
        let trace = try PMClipboardFitTrace(source)
        var tr = PMTransform(target); try tr.replaceRange(6, 6, source, sourceTrace: trace)
        XCTAssertEqual(tr.doc.child(0).childCount, 1)
        XCTAssertEqual(tr.doc.child(0).child(0).textString, "same samesame")
        XCTAssertEqual(trace.placements, [.init(sourceFrom: 0, sourceTo: 4, targetFrom: 6, targetTo: 10)])
        XCTAssertEqual(trace.nodes.first?.path, [0])
        XCTAssertEqual(trace.omitted, [])
    }
    func testOpenParagraphTracksItsTextAfterWrapperJoinsRetainedParagraph() throws {
        let schema = try PMYXmlBridge.canonical().schema
        let target = try node("doc", [node("paragraph", [schema.text(Array("same same".utf16))], schema)], schema)
        let paragraph = try node("paragraph", [schema.text(Array("same".utf16))], schema)
        let source = PMSlice(PMFragment.from(paragraph), openStart: 1, openEnd: 1)
        let trace = try PMClipboardFitTrace(source)
        var tr = PMTransform(target); try tr.replaceRange(6, 6, source, sourceTrace: trace)
        XCTAssertEqual(tr.doc.child(0).childCount, 1)
        XCTAssertEqual(tr.doc.child(0).child(0).textString, "same samesame")
        XCTAssertEqual(trace.placements, [.init(sourceFrom: 1, sourceTo: 5, targetFrom: 6, targetTo: 10)])
        XCTAssertEqual(trace.omitted, [0, 5])
        XCTAssertTrue(trace.events.contains { $0["kind"] as? String == "open_wrapper" && $0["source_path"] as? [Int] == [0] })
    }
    func testBothCopiedTextPathsSurviveCoalescingWithDifferentRetainedNeighbors() throws {
        let schema = try PMYXmlBridge.canonical().schema
        let bold = try XCTUnwrap(schema.marks["bold"]).create(nil)
        let texts = [schema.text(Array("A".utf16), marks: [bold]), schema.text(Array("B".utf16))]
        let target = try node("doc", [node("paragraph", texts, schema)], schema)
        let source = PMSlice(PMFragment.from(try node("paragraph", texts, schema)), openStart: 1, openEnd: 1)
        let trace = try PMClipboardFitTrace(source)
        var tr = PMTransform(target); try tr.replaceRange(2, 2, source, sourceTrace: trace)
        XCTAssertEqual(tr.doc.child(0).childCount, 2)
        XCTAssertEqual(tr.doc.child(0).child(0).textString, "AA")
        XCTAssertEqual(tr.doc.child(0).child(1).textString, "BB")
        XCTAssertEqual(trace.nodes.map(\.path), [[0], [0, 0], [0, 1]])
        XCTAssertEqual(trace.placements, [.init(sourceFrom: 1, sourceTo: 3, targetFrom: 2, targetTo: 4)])
        XCTAssertEqual(trace.omitted, [0, 3])
    }
    func testReplaceAroundGapRemainsTargetOnlyBetweenCopiedSourceIntervals() throws {
        let schema = try PMYXmlBridge.canonical().schema
        let target = try node("doc", [node("paragraph", [schema.text(Array("abcd".utf16))], schema)], schema)
        let incoming = try node("bulletList", [node("listItem", [node("paragraph", [schema.text(Array("X".utf16))], schema)], schema)], schema)
        let source = PMSlice(PMFragment.from(incoming), openStart: 0, openEnd: 3)
        let trace = try PMClipboardFitTrace(source)
        let step = try XCTUnwrap(pmReplaceStep(target, 2, 2, source, sourceTrace: trace))
        guard case let .replaceAround(_, _, gapFrom, gapTo, _, insert, _) = step else { return XCTFail("Actual inline suffix must move through replaceAround") }
        XCTAssertEqual(gapFrom, 2); XCTAssertEqual(gapTo, 5); XCTAssertEqual(insert, 5)
        let after = try step.apply(target)
        XCTAssertEqual(after.child(0).child(0).textString, "a")
        XCTAssertEqual(after.child(1).child(0).child(0).child(0).textString, "Xbcd")
        XCTAssertEqual(trace.placements, [
            .init(sourceFrom: 0, sourceTo: 4, targetFrom: 3, targetTo: 7),
            .init(sourceFrom: 4, sourceTo: 7, targetFrom: 10, targetTo: 13)
        ])
        XCTAssertEqual(trace.omitted, [])
    }
    func testFitterReportsActualMarkFilteringAlongsideExactOriginalPath() throws {
        let schema = try PMYXmlBridge.canonical().schema
        let bold = try XCTUnwrap(schema.marks["bold"]).create(nil)
        let target = try node("doc", [node("codeBlock", [schema.text(Array("ab".utf16))], schema)], schema)
        let incoming = try node("paragraph", [schema.text(Array("X".utf16), marks: [bold])], schema)
        let source = PMSlice(PMFragment.from(incoming), openStart: 1, openEnd: 1)
        let trace = try PMClipboardFitTrace(source)
        let step = try XCTUnwrap(pmReplaceStep(target, 2, 2, source, sourceTrace: trace))
        let after = try step.apply(target)
        XCTAssertEqual(after.child(0).child(0).textString, "aXb")
        XCTAssertEqual(after.child(0).child(0).marks.count, 0)
        XCTAssertEqual(trace.placements, [.init(sourceFrom: 1, sourceTo: 2, targetFrom: 2, targetTo: 3)])
        let filtered = try XCTUnwrap(trace.events.first { $0["kind"] as? String == "filtered_marks" })
        XCTAssertEqual(filtered["source_tokens"] as? [Int], [1])
        XCTAssertEqual((filtered["marks"] as? [[String: Any]])?.first?["type"] as? String, "bold")
    }
    func testLaterItemMapsEarlierOriginalTraceAndRefusesActualLoss() throws {
        let schema = try PMYXmlBridge.canonical().schema
        let target = try node("doc", [node("paragraph", [schema.text(Array("ab".utf16))], schema)], schema)
        let first = PMSlice(PMFragment.from(schema.text(Array("First".utf16))), openStart: 0, openEnd: 0)
        let second = PMSlice(PMFragment.from(schema.text(Array("Second".utf16))), openStart: 0, openEnd: 0)
        var transform = PMTransform(target)
        let firstTrace = try PMClipboardFitTrace(first)
        try transform.replaceRange(2, 2, first, sourceTrace: firstTrace)
        let secondIndex = transform.steps.count, secondTrace = try PMClipboardFitTrace(second)
        try transform.replaceRange(7, 7, second, sourceTrace: secondTrace)
        let items: [[String: Any]] = [
            ["clipboard_slice": first.json(), "source_trace": try firstTrace.json(), "step_index": 0],
            ["clipboard_slice": second.json(), "source_trace": try secondTrace.json(), "step_index": secondIndex]
        ]
        func input(_ steps: [PMStep]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["clipboard_items": items,
                "before_document": target.json(), "steps": steps.map { $0.json() }])
        }
        let output = try RelayMarkContentEditCodec.planClipboardAnchorAllocation(input(transform.steps))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        XCTAssertTrue(pmCompareDeep(result["document"]!, transform.doc.json()))
        XCTAssertEqual(transform.doc.child(0).child(0).textString, "aFirstSecondb")
        // An actual subsequent Step deletes the first supplied character. The
        // source token mapping must reject before the native document commit.
        try transform.step(.replace(from: 2, to: 3, slice: .empty))
        XCTAssertThrowsError(try RelayMarkContentEditCodec.planClipboardAnchorAllocation(input(transform.steps)))
    }

}

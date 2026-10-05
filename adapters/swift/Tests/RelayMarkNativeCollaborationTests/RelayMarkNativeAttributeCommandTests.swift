import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration

@MainActor
final class RelayMarkNativeAttributeCommandTests: XCTestCase {
    func testAuthoredHeadingListCalloutAndTaskSettingsRetainTextAndEmitActualSteps() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let source = "# Heading\n\n7. Entry\n\n@Callout(tone: \"info\", emphasis: \"soft\") {\nNested **rich** text\n}\n\n- [ ] Task"
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument(source, namespace: "attribute-command"))
        try peer.applyUpdate(seed)
        let beforeText = String(try document.richProseProjection().text.characters)
        let root = try JSONSerialization.jsonObject(with: document.snapshot()) as! [String: Any]
        let nodes = root["children"] as! [[String: Any]]
        let heading = nodes[0]["attributes"] as! [String: Any], callout = nodes[2]["attributes"] as! [String: Any]
        let task = ((nodes[3]["children"] as! [[String: Any]])[0]["attributes"] as! [String: Any])
        for kind in ["heading", "ordered", "callout", "task"] {
            let observation = try document.captureContentEditObservation()
            let change: RelayMarkNativeRichEditing.Change
            switch kind {
            case "heading": change = try document.setRichHeadingLevel(anchor: document.anchor(path: [0], index: 0), expectedHeadingID: heading["headingId"] as? String, level: 3)
            case "ordered": change = try document.setRichOrderedListStart(anchor: document.anchor(path: [1], index: 0), expectedStart: 7, start: 10)
            case "callout": change = try document.setCalloutAppearance(anchor: document.anchor(path: [2], index: 0), expectedID: callout["relaymarkId"] as! String, expectedTone: "info", expectedEmphasis: "soft", tone: "warning", emphasis: "strong")
            default: change = try document.setRichTaskItemChecked(path: [3, 0], expectedID: task["relaymarkId"] as! String, expectedEntityID: nil, expectedChecked: false, checked: true)
            }
            let steps = try JSONSerialization.jsonObject(with: change.steps) as! [[String: Any]]
            XCTAssertFalse(steps.isEmpty)
            XCTAssertTrue(steps.allSatisfy { $0["stepType"] as? String == "attr" })
            let witness = try JSONSerialization.jsonObject(with: document.buildContentEditWitness(observation, steps: change.steps, update: change.update)) as! [String: Any]
            XCTAssertEqual((witness["text_items"] as! [String: Any])["runs"] as? [[String: Int]], [])
            XCTAssertEqual((witness["proven_copies"] as! [Any]).count, 0)
            try peer.applyUpdate(change.update)
            XCTAssertEqual(try peer.authoredDocument(), try document.authoredDocument())
            XCTAssertEqual(String(try document.richProseProjection().text.characters), beforeText)
        }
        let final = try JSONSerialization.jsonObject(with: document.snapshot()) as! [String: Any]
        let finalNodes = final["children"] as! [[String: Any]]
        XCTAssertEqual((finalNodes[0]["attributes"] as! [String: Any])["level"] as? Int, 3)
        XCTAssertEqual((finalNodes[1]["attributes"] as! [String: Any])["start"] as? Int, 10)
        XCTAssertEqual((finalNodes[2]["attributes"] as! [String: Any])["tone"] as? String, "warning")
        XCTAssertEqual(((finalNodes[3]["children"] as! [[String: Any]])[0]["attributes"] as! [String: Any])["checked"] as? Bool, true)
    }
    func testBlockStyleUsesRetainedGapAndDoesNotClassifyExistingRichTextAsHuman() throws {
        for style in [RelayMarkNativeBlockStyle.heading(2), .quote, .bulletList, .orderedList, .taskList] {
            let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
            let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("**Kept🌍**", namespace: "block-style"))
            try peer.applyUpdate(seed)
            let before = try document.authoredDocument()
            let observation = try document.captureContentEditObservation()
            let change: RelayMarkNativeRichEditing.Change = try document.setRichBlockStyle(at: 0, style: style, expectedSnapshot: document.snapshot())
            let steps = try JSONSerialization.jsonObject(with: change.steps) as! [[String: Any]]
            XCTAssertTrue(steps.allSatisfy { $0["stepType"] as? String == "replaceAround" })
            let witness = try JSONSerialization.jsonObject(with: document.buildContentEditWitness(observation, steps: change.steps, update: change.update)) as! [String: Any]
            XCTAssertEqual(((witness["text_items"] as! [String: Any])["runs"] as! [Any]).count, 0)
            XCTAssertEqual(String(try document.richProseProjection().text.characters), "Kept🌍")
            try peer.applyUpdate(change.update)
            XCTAssertEqual(try document.authoredDocument(), try peer.authoredDocument())
            _ = try XCTUnwrap(document.undo())
            XCTAssertEqual(try document.authoredDocument(), before)
        }
    }

    func testCalloutTitleAndTaskInsertionEmitActualStepsWithoutReallocatingNeighbors() throws {
        let document = RelayMarkNativeDocument(), peer = RelayMarkNativeDocument()
        let seed = try document.initializeDocument(authoredAST: RelayMarkSourceCodec.parseDocument("Before\n\n@Callout(tone: \"info\", emphasis: \"soft\") {\n- Nested **body**\n}", namespace: "title-insertion"))
        try peer.applyUpdate(seed)
        let before = try JSONSerialization.jsonObject(with: document.authoredDocument()) as! [String: Any]
        let nodes = (try JSONSerialization.jsonObject(with: document.snapshot()) as! [String: Any])["children"] as! [[String: Any]]
        let calloutID = (nodes[1]["attributes"] as! [String: Any])["relaymarkId"] as! String
        let observation = try document.captureContentEditObservation()
        let title = try document.addCalloutTitle(anchor: document.anchor(path: [1], index: 0), expectedID: calloutID, expectedSnapshot: document.snapshot())
        let witness = try JSONSerialization.jsonObject(with: document.buildContentEditWitness(observation, steps: title.change.steps, update: title.change.update)) as! [String: Any]
        let runs = (witness["text_items"] as! [String: Any])["runs"] as! [[String: Any]]
        XCTAssertEqual(runs.reduce(0) { $0 + ($1["count"] as! Int) }, 5)
        XCTAssertEqual((witness["proven_copies"] as! [Any]).count, 0)
        try peer.applyUpdate(title.change.update)
        let taskObservation = try document.captureContentEditObservation()
        let task = try document.insertEmptyRichTaskList(after: document.anchor(path: [0], index: 0), expectedSnapshot: document.snapshot())
        let taskWitness = try JSONSerialization.jsonObject(with: document.buildContentEditWitness(taskObservation, steps: task.change.steps, update: task.change.update)) as! [String: Any]
        XCTAssertEqual(((taskWitness["text_items"] as! [String: Any])["runs"] as! [Any]).count, 0)
        try peer.applyUpdate(task.change.update)
        XCTAssertEqual(try peer.authoredDocument(), try document.authoredDocument())
        let after = try JSONSerialization.jsonObject(with: document.authoredDocument()) as! [String: Any]
        XCTAssertEqual(NSDictionary(dictionary: (after["blocks"] as! [[String: Any]])[0]), NSDictionary(dictionary: (before["blocks"] as! [[String: Any]])[0]))
    }

}

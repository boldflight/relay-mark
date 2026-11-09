import Foundation
import RelayMarkProseProjection
import RelayMarkSwift

/// A checklist item a person started on purpose and has finished, ready for
/// the host to make into a Task.
public struct RelayTaskDraft: Equatable, Sendable {
    public let blockID: String
    /// The item's operation id: its block identity as a UUID, the server's idempotency key.
    public let operationID: String
    /// The first paragraph's text, trimmed; never empty for a finished draft.
    public let title: String
    /// The first paragraph's exact text, which the server's anchor checks.
    public let text: String
    public let done: Bool
    /// The nearest enclosing linked task item's entity, when there is one.
    public let parentEntityID: String?
    /// The task item's path in the paper, for its anchor.
    public let path: [Int]
}

/// relaymark-core decides which checklist items are draft Tasks and when one
/// is finished (spec/relaymark/editor/task-drafts-v1.json); the session keeps
/// the armed set and describes its task items to the engine. The engine sees
/// an outline of the task items only, never the paper, and nothing runs while
/// no draft is armed except the three ways to start one.
extension RelayMarkEditorSession {
    /// Arms existing unlinked items, as "Create linked tasks…" does for the ones
    /// a person picks; their Tasks are created as they are finished.
    public func armTaskDrafts(_ blockIDs: [String]) {
        armTaskDrafts(event: ["kind": "arm", "ids": blockIDs], before: nil)
    }

    /// Keeps items as plain checklist items: they create no Task until armed again.
    public func keepTaskDraftsLocal(_ blockIDs: [String]) {
        armTaskDrafts(event: ["kind": "disarm", "ids": blockIDs], before: nil)
    }

    /// Finishes the given armed drafts now, as the host's "Create task" action does.
    public func finishTaskDrafts(_ blockIDs: [String]) {
        finishTaskDrafts(blockIDs, outline: RelayTaskDraftOutline(nativeTaskItems))
    }

    /// Every unlinked checklist item, armed or not, for the host's review.
    public func taskDrafts() -> [RelayTaskDraft] {
        let outline = RelayTaskDraftOutline(nativeTaskItems)
        return (try? drafts(outline, armed: armedTaskDrafts, only: nil)) ?? []
    }

    /// After a typed checklist, the Checklist command or Return in an armed
    /// item, from the task items before the edit.
    func armTaskDrafts(event: [String: Any], before: [RelayMarkCollaborativeProse.TaskItem]?) {
        guard createsTaskDrafts || ["arm", "disarm"].contains(event["kind"] as? String) else { return }
        let after = RelayTaskDraftOutline(nativeTaskItems)
        do {
            armedTaskDrafts = try RelayMarkTaskDraftCodec.arm(before: before.map { RelayTaskDraftOutline($0).document },
                after: after.document, armed: armedTaskDrafts, event: event)
        } catch { failure = error.localizedDescription }
        caretTaskDraft = nil
        if let caret = nativeSelection?.location { noteTaskDraftCaret(caret) }
    }

    /// The caret is at `offset`. Leaving the armed item that held it finishes
    /// that draft. The item, not the offset, is remembered, so a peer's edit
    /// that shifts the text never reads as the person moving away. A peer's
    /// update, a paste or Undo never arms; they only drop drafts that are gone
    /// or linked, from ids the projection already holds.
    func noteTaskDraftCaret(_ offset: Int) {
        guard !armedTaskDrafts.isEmpty else { caretTaskDraft = nil; return }
        let items = nativeTaskItems
        let unlinked = Set(items.filter { $0.entityID == nil }.map(\.id))
        armedTaskDrafts.removeAll { !unlinked.contains($0) }
        let holding = items.last { offset >= $0.firstParagraphRange.location && offset <= NSMaxRange($0.firstParagraphRange) }?.id
        if let left = caretTaskDraft, left != holding, armedTaskDrafts.contains(left), activeComposition == nil {
            let outline = RelayTaskDraftOutline(items)
            if let before = outline.firstParagraphStart(left) {
                finish(outline, boundary: ["key": "move", "before": before, "after": outline.position(atUTF16: offset)])
            }
        }
        caretTaskDraft = holding.flatMap { armedTaskDrafts.contains($0) ? $0 : nil }
    }

    /// The person ticked an unlinked item's checkbox.
    func finishTaskDraftOnCheckbox(_ blockID: String) {
        guard armedTaskDrafts.contains(blockID) else { return }
        finish(RelayTaskDraftOutline(nativeTaskItems), boundary: ["key": "checkbox", "block": blockID])
    }

    private func finish(_ outline: RelayTaskDraftOutline, boundary: [String: Any]) {
        do {
            let finished = try RelayMarkTaskDraftCodec.finished(document: outline.document, armed: armedTaskDrafts, boundary: boundary)
            finishTaskDrafts(finished, outline: outline)
        } catch { failure = error.localizedDescription }
    }

    private func finishTaskDrafts(_ blockIDs: [String], outline: RelayTaskDraftOutline) {
        guard !blockIDs.isEmpty else { return }
        do {
            let finished = try drafts(outline, armed: armedTaskDrafts, only: Set(blockIDs)).filter { !$0.title.isEmpty }
            guard !finished.isEmpty else { return }
            // A finished draft is the host's now; it arms it again after a refusal.
            armedTaskDrafts.removeAll { id in finished.contains { $0.blockID == id } }
            onTaskDraftsFinished?(finished)
        } catch { failure = error.localizedDescription }
    }

    private func drafts(_ outline: RelayTaskDraftOutline, armed: [String], only: Set<String>?) throws -> [RelayTaskDraft] {
        try RelayMarkTaskDraftCodec.drafts(document: outline.document, armed: armed).compactMap { draft in
            guard let block = draft["block_id"] as? String, only?.contains(block) ?? true,
                  let operation = draft["operation_id"] as? String, let title = draft["title"] as? String,
                  let text = draft["text"] as? String, let done = draft["done"] as? Bool,
                  let path = outline.paths[block] else { return nil }
            return RelayTaskDraft(blockID: block, operationID: operation, title: title, text: text, done: done,
                                  parentEntityID: draft["parent_entity_id"] as? String, path: path)
        }
    }
}

/// The paper's task items as the engine reads them: nested task lists holding
/// each item's identity, check, link and first-paragraph text, and nothing else.
/// A caret maps into an item's first paragraph or outside every item.
struct RelayTaskDraftOutline {
    let document: Data
    let paths: [String: [Int]]
    private let starts: [(id: String, range: NSRange, position: Int, length: Int)]

    init(_ items: [RelayMarkCollaborativeProse.TaskItem]) {
        var paths: [String: [Int]] = [:], starts: [(String, NSRange, Int, Int)] = []
        // Each item nests under the nearest earlier item whose path encloses it.
        var children: [Int: [Int]] = [:], roots: [Int] = []
        for (index, item) in items.enumerated() {
            paths[item.id] = item.path
            let parent = items[..<index].lastIndex { $0.path.count < item.path.count && Array(item.path.prefix($0.path.count)) == $0.path }
            if let parent { children[parent, default: []].append(index) } else { roots.append(index) }
        }
        // ProseMirror positions: an item opens at `position`, its paragraph's text starts two later.
        func node(_ index: Int, at position: Int) -> (json: [String: Any], size: Int) {
            let item = items[index], length = item.firstParagraphText.utf16.count
            var paragraph: [String: Any] = ["type": "paragraph"]
            if length > 0 { paragraph["content"] = [["type": "text", "text": item.firstParagraphText]] }
            starts.append((item.id, item.firstParagraphRange, position, length))
            var content: [[String: Any]] = [paragraph], size = 2 + length + 2
            if let nested = children[index] {
                let list = Self.list(nested, at: position + size - 1, node: node)
                content.append(list.json); size += list.size
            }
            let attributes: [String: Any] = ["relaymarkId": item.id, "checked": item.checked, "entityId": item.entityID ?? NSNull()]
            return (["type": "taskItem", "attrs": attributes, "content": content], size)
        }
        let top = roots.isEmpty ? nil : Self.list(roots, at: 0, node: node)
        let content: [[String: Any]] = top.map { [$0.json] } ?? [["type": "paragraph"]]
        let doc: [String: Any] = ["type": "doc", "content": content]
        document = (try? JSONSerialization.data(withJSONObject: doc)) ?? Data()
        self.paths = paths
        self.starts = starts
    }

    private static func list(_ indexes: [Int], at position: Int, node: (Int, Int) -> (json: [String: Any], size: Int)) -> (json: [String: Any], size: Int) {
        var content: [[String: Any]] = [], size = 2
        for index in indexes {
            let child = node(index, position + size - 1)
            content.append(child.json); size += child.size
        }
        return (["type": "taskList", "content": content], size)
    }

    /// The outline position at the start of an item's first paragraph text.
    func firstParagraphStart(_ id: String) -> Int? {
        starts.first { $0.id == id }.map { $0.position + 2 }
    }

    /// The outline position for a paper caret: inside the first paragraph of
    /// the item holding it, or 0, which no item holds.
    func position(atUTF16 offset: Int) -> Int {
        guard let start = starts.last(where: { offset >= $0.range.location && offset <= NSMaxRange($0.range) }) else { return 0 }
        return start.position + 2 + min(offset - start.range.location, start.length)
    }
}

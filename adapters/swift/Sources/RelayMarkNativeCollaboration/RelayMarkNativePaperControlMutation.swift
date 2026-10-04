import Foundation
import RelayMarkProseProjection

/// Authored canonical Paper-control XML commands over the existing YSwift replica.
/// Host authorization, navigation, and connection hydration stay outside this layer.
@MainActor
public enum RelayMarkNativePaperControlMutation {
    public struct Block: Sendable {
        public let id: String
        public let control: RelayMarkPaperControlContract.Control
        public let authored: [String: String]

        public init(id: String, control: RelayMarkPaperControlContract.Control,
                    authored: [String: String]) {
            self.id = id
            self.control = control
            self.authored = authored
        }
    }

    /// Insert at a root XML sibling boundary. Neighbor IDs bind the command to
    /// the block order the caller displayed, including nil at either edge.
    public static func insert(document: RelayMarkNativeDocument, atRootIndex index: Int,
                              expectedPreviousID: String?, expectedNextID: String?,
                              block: Block) throws -> Data {
        let (root, blocks, _) = try current(document)
        guard index >= 0, index <= blocks.count, blocks.count < 4_096,
              (index == 0 ? expectedPreviousID == nil : blockID(blocks[index - 1]) == expectedPreviousID),
              (index == blocks.count ? expectedNextID == nil : blockID(blocks[index]) == expectedNextID) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let (tag, attributes) = try validated(block)
        var candidate = root
        var children = blocks
        children.insert(["kind": "element", "name": tag, "attributes": attributes, "children": []], at: index)
        candidate["children"] = children
        let change = RelayMarkNativeDocument.PaperControlChange.insert(tag: tag, attributes: attributes)
        try validate(document: document, candidate: candidate, at: index, change: change)
        return try document.mutatePaperControl(at: index, change: change)
    }

    /// Update authored fields on the same XML element. Its stable ID, control
    /// kind, and Yrs element identity stay in place.
    public static func update(document: RelayMarkNativeDocument, atRootIndex index: Int,
                              expectedID: String, expectedSource: String,
                              authored: [String: String]) throws -> Data {
        let (root, blocks, prose) = try current(document)
        let old = try existing(blocks: blocks, prose: prose, index: index,
                               expectedID: expectedID, expectedSource: expectedSource)
        let block = Block(id: old.id, control: old.control, authored: authored)
        let (tag, attributes) = try validated(block)
        let newSource = try RelayMarkPaperControlContract.validate(nodeName: tag,
                                                                    attributes: attributes).source
        guard old.source != newSource else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        var candidate = root
        var children = blocks
        children[index]["attributes"] = attributes
        candidate["children"] = children
        let change = RelayMarkNativeDocument.PaperControlChange.update(
            tag: tag, expectedID: old.id, attributes: attributes)
        try validate(document: document, candidate: candidate, at: index, change: change)
        return try document.mutatePaperControl(at: index, change: change)
    }

    /// Remove one identified control. A stale index, ID, or canonical authored
    /// source cannot retarget another block.
    public static func remove(document: RelayMarkNativeDocument, atRootIndex index: Int,
                              expectedID: String, expectedSource: String) throws -> Data {
        let (root, blocks, prose) = try current(document)
        let old = try existing(blocks: blocks, prose: prose, index: index,
                               expectedID: expectedID, expectedSource: expectedSource)
        var candidate = root
        var children = blocks
        children.remove(at: index)
        candidate["children"] = children
        let change = RelayMarkNativeDocument.PaperControlChange.remove(
            tag: nodeName(old.control), expectedID: old.id)
        try validate(document: document, candidate: candidate, at: index, change: change)
        return try document.mutatePaperControl(at: index, change: change)
    }

    private static func current(_ document: RelayMarkNativeDocument)
        throws -> (root: [String: Any], blocks: [[String: Any]], prose: RelayMarkCollaborativeProse) {
        let prose = try document.richProseProjection()
        guard prose.isEditable,
              let root = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any],
              let blocks = root["children"] as? [[String: Any]] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return (root, blocks, prose)
    }

    private static func existing(blocks: [[String: Any]], prose: RelayMarkCollaborativeProse,
                                 index: Int, expectedID: String, expectedSource: String)
        throws -> RelayMarkCollaborativeProse.BlockAtom {
        guard blocks.indices.contains(index), blockID(blocks[index]) == expectedID,
              let old = prose.blockAtoms.first(where: {
                  $0.path == [index] && $0.id == expectedID && $0.source == expectedSource
              }), blocks[index]["name"] as? String == nodeName(old.control) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return old
    }

    private static func validated(_ block: Block) throws -> (tag: String, attributes: [String: String]) {
        let tag = nodeName(block.control)
        var attributes = block.authored
        guard attributes["relaymarkId"] == nil else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        attributes["relaymarkId"] = block.id
        _ = try RelayMarkPaperControlContract.validate(nodeName: tag, attributes: attributes)
        return (tag, attributes)
    }

    private static func nodeName(_ control: RelayMarkPaperControlContract.Control) -> String {
        switch control {
        case .button: "relayButton"
        case .anchor: "relayAnchor"
        case .connection: "relayConnection"
        }
    }

    private static func blockID(_ block: [String: Any]) -> String? {
        (block["attributes"] as? [String: Any])?["relaymarkId"] as? String
    }

    private static func validate(document: RelayMarkNativeDocument, candidate: [String: Any],
                                 at index: Int, change: RelayMarkNativeDocument.PaperControlChange) throws {
        let candidateData = try JSONSerialization.data(withJSONObject: candidate)
        let expectedAST = try RelayMarkNativeDocumentProjection.project(snapshot: candidateData)
        guard try RelayMarkCollaborativeProse(snapshot: candidateData, dialect: .rich).isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let scratch = RelayMarkNativeDocument()
        try scratch.applyUpdate(document.encodeUpdate())
        _ = try scratch.mutatePaperControl(at: index, change: change)
        guard try RelayMarkNativeDocumentProjection.project(document: scratch) == expectedAST,
              try scratch.richProseProjection().isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
    }
}

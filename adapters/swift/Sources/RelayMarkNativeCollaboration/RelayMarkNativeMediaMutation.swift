import Foundation
import RelayMarkProseProjection
import RelayMarkSwift

/// Authored media-block commands using the existing YSwift/Yrs root XML path.
/// The host supplies authorized media identity and owns upload, fetch and playback.
@MainActor
public enum RelayMarkNativeMediaMutation {
    public struct Block: Sendable {
        public let id: String
        public let kind: RelayMarkCollaborativeProse.MediaAtom.Kind
        /// Durable absolute local path or HTTPS image source, or a video UUID.
        public let source: String
        public let alt: String?
        public let title: String?
        public let width: Int?
        public let height: Int?

        public init(id: String, kind: RelayMarkCollaborativeProse.MediaAtom.Kind,
                    source: String, alt: String? = nil, title: String? = nil,width: Int? = nil,height: Int? = nil) {
            self.id = id
            self.kind = kind
            self.source = source
            self.alt = alt
            self.title = title
            self.width = width;self.height = height
        }
    }

    /// Insert at the exact root sibling boundary the host displayed. Full AST
    /// validation rejects unresolved uploads, unsafe sources and duplicate IDs.
    public static func insert(document: RelayMarkNativeDocument, atRootIndex index: Int,
                              expectedPreviousID: String?, expectedNextID: String?,
                              block: Block) throws -> RelayMarkNativeRichEditing.Change {
        guard document.integrationStatus().isComplete,
              try document.richProseProjection().isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let (root, blocks) = try snapshot(document)
        guard index >= 0, index <= blocks.count, blocks.count < RelayMarkNativeDocument.maximumBlocks,
              (index == 0 ? expectedPreviousID == nil : blockID(blocks[index - 1]) == expectedPreviousID),
              (index == blocks.count ? expectedNextID == nil : blockID(blocks[index]) == expectedNextID) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let attributes = try attributes(for: block)
        var candidate = root, children = blocks
        children.insert(["kind": "element", "name": block.kind.rawValue,
                         "attributes": attributes, "children": []], at: index)
        candidate["children"] = children
        _ = try project(candidate)
        return try RelayMarkNativeRichEditing.insertWidget(document: document, tree: root,
            candidate: candidate, parentID: nil, index: index)
    }

    /// Remove one exact media atom. The remaining paper must pass the native
    /// editable projection; unrelated media and neighbors stay untouched.
    public static func remove(document: RelayMarkNativeDocument, atRootIndex index: Int,
                              expectedID: String, expectedSource: String) throws -> RelayMarkNativeRichEditing.Change {
        guard document.integrationStatus().isComplete else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let prose = try document.richProseProjection()
        let (root, blocks) = try snapshot(document)
        guard blocks.indices.contains(index), blockID(blocks[index]) == expectedID,
              let media = prose.mediaAtoms.first(where: {
                  $0.path == [index] && $0.id == expectedID && $0.source == expectedSource
              }),
              blocks[index]["name"] as? String == media.kind.rawValue else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        var candidate = root, children = blocks
        children.remove(at: index)
        candidate["children"] = children
        let candidateData = try JSONSerialization.data(withJSONObject: candidate)
        _ = try RelayMarkNativeDocumentProjection.project(snapshot: candidateData)
        guard try RelayMarkCollaborativeProse(snapshot: candidateData, dialect: .rich).isEditable else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return try RelayMarkNativeRichEditing.removeWidget(document: document, tree: root, id: expectedID)
    }

    private static func attributes(for block: Block) throws -> [String: Any] {
        var attributes: [String:Any] = ["relaymarkId": block.id]
        switch block.kind {
        case .image:
            attributes["src"] = block.source
            if let alt = block.alt { attributes["alt"] = alt }
            if let title = block.title { attributes["title"] = title }
            if let width = block.width { attributes["width"] = width };if let height = block.height { attributes["height"] = height }
        case .videoEmbed:
            guard block.alt == nil, block.title == nil, block.width == nil, block.height == nil else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            attributes["videoId"] = block.source
        }
        return attributes
    }

    private static func snapshot(_ document: RelayMarkNativeDocument)
        throws -> (root: [String: Any], blocks: [[String: Any]]) {
        guard let root = try JSONSerialization.jsonObject(with: document.snapshot()) as? [String: Any],
              let blocks = root["children"] as? [[String: Any]] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return (root, blocks)
    }

    private static func blockID(_ block: [String: Any]) -> String? {
        (block["attributes"] as? [String: Any])?["relaymarkId"] as? String
    }

    private static func project(_ snapshot: [String: Any]) throws -> RelayMarkDocument {
        try RelayMarkNativeDocumentProjection.project(
            snapshot: JSONSerialization.data(withJSONObject: snapshot))
    }

}

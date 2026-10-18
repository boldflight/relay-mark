import Foundation
import RelayMarkProseProjection

/// Structural Return uses the packaged maintained command/keymap and the same
/// canonical native PM/Yrs writer as ordinary rich selection replacement.
@MainActor
public enum RelayMarkNativeRichReturn {
    public enum Kind: Sendable { case split, exit }
    public struct Result: Sendable {
        public let change: RelayMarkNativeRichEditing.Change
        public let kind: Kind
        public let blockID: String
    }

    public static func apply(document: RelayMarkNativeDocument, blockPath: [Int],
                             utf16Offset: Int, selectionEnd: RelayMarkNativeRichEditing.Caret? = nil,
                             expectedSnapshot: Data) throws -> Result {
        try apply(document: document, blockPath: blockPath, utf16Offset: utf16Offset, selectionEnd: selectionEnd,
                  scope: RelayMarkNativeRichEditing.scope(document: document, expectedSnapshot: expectedSnapshot), windowed: false)
    }

    /// The same command reading and writing only the top-level nodes around
    /// the selection. `paper` is the caller's projection of the document as it is now.
    public static func apply(document: RelayMarkNativeDocument, blockPath: [Int],
                             utf16Offset: Int, selectionEnd: RelayMarkNativeRichEditing.Caret? = nil,
                             paper: RelayMarkCollaborativeProse) throws -> Result {
        try RelayMarkNativeRichEditing.windowed(document: document, paper: paper,
                                                paths: [blockPath] + (selectionEnd.map { [$0.blockPath] } ?? [])) { scope in
            try apply(document: document, blockPath: scope.local(blockPath), utf16Offset: utf16Offset,
                      selectionEnd: selectionEnd.map { .init(blockPath: scope.local($0.blockPath), offset: $0.offset) },
                      scope: scope, windowed: true)
        }
    }

    private static func apply(document: RelayMarkNativeDocument, blockPath: [Int],
                              utf16Offset: Int, selectionEnd: RelayMarkNativeRichEditing.Caret?,
                              scope: RelayMarkNativeRichEditing.Scope, windowed: Bool) throws -> Result {
        let tree = scope.tree, projection = scope.projection
        guard projection.isEditable else {throw RelayMarkNativeDocument.Failure.unsupportedProseEdit}
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: tree)
        func position(path: [Int], offset: Int) throws -> Int {
            guard let row=projection.blockPaths.firstIndex(of:path) else {throw RelayMarkNativeDocument.Failure.invalidTextPath}
            let text=(String(projection.text.characters) as NSString).substring(with:projection.blockRanges[row])
            guard RelayMarkNativeRichXML.isCharacterBoundary(offset,in:text) else {throw RelayMarkNativeDocument.Failure.unsupportedProseEdit}
            let block=try RelayMarkNativeRichEditing.positionForPath(path,in:source)
            guard source.nodeAt(block)?.isTextblock==true else {throw RelayMarkNativeDocument.Failure.unsupportedProseEdit}
            return block+1+offset
        }
        let anchor=try position(path:blockPath,offset:utf16Offset)
        let head=try selectionEnd.map {try position(path:$0.blockPath,offset:$0.offset)} ?? anchor
        let result = try RelayMarkNativeRichEditing.command(document: document, tree: tree, name: "return",
            selection: ["type": "text", "anchor": anchor, "head": head], scope: windowed ? scope : nil)
        guard let id = result.blockID else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return Result(change: result.change, kind: result.kind == "exit" ? .exit : .split, blockID: id)
    }
}

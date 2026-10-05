import Foundation

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
        guard document.integrationStatus().isComplete, try document.snapshot() == expectedSnapshot,
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let projection = try document.richProseProjection()
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
            selection: ["type": "text", "anchor": anchor, "head": head])
        guard let id = result.blockID else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return Result(change: result.change, kind: result.kind == "exit" ? .exit : .split, blockID: id)
    }
}

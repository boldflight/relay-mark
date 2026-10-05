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
                             utf16Offset: Int, expectedSnapshot: Data) throws -> Result {
        guard document.integrationStatus().isComplete, try document.snapshot() == expectedSnapshot,
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let projection = try document.richProseProjection()
        guard projection.isEditable, let row = projection.blockPaths.firstIndex(of: blockPath) else {
            throw RelayMarkNativeDocument.Failure.invalidTextPath
        }
        let range = projection.blockRanges[row]
        let sourceText = (String(projection.text.characters) as NSString).substring(with: range)
        guard RelayMarkNativeRichXML.isCharacterBoundary(utf16Offset, in: sourceText) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        let bridge = try PMYXmlBridge.canonical(), source = try bridge.document(fromSnapshot: tree)
        let blockPosition = try RelayMarkNativeRichEditing.positionForPath(blockPath, in: source)
        guard source.nodeAt(blockPosition)?.isTextblock == true else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let position = blockPosition + 1 + utf16Offset
        let result = try RelayMarkNativeRichEditing.command(document: document, tree: tree, name: "return",
            selection: ["type": "text", "anchor": position, "head": position])
        guard let id = result.blockID else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return Result(change: result.change, kind: result.kind == "exit" ? .exit : .split, blockID: id)
    }
}

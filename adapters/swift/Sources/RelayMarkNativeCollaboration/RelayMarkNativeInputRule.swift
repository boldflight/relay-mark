import Foundation
import RelayMarkProseProjection
import RelayMarkSwift

/// Typed Markdown shortcuts: `- ` starts a bullet list, `[ ] ` a checklist,
/// `**bold**` makes bold text. relaymark-core owns the rules (the web editor's
/// TipTap rules, ported, and checked against the same shared cases) and
/// returns them as a maintained command; this writes its Steps through the
/// native PM/Yrs owner, as Return does.
@MainActor
public enum RelayMarkNativeInputRule {
    /// Whether typing `text` after `before`, the block's text up to the caret,
    /// could complete a shortcut. Cheap enough for every keystroke: anything
    /// but a rule's last character is answered without calling the engine.
    public static func mayComplete(before: String, typing text: String) -> Bool {
        guard let last = text.last, RelayMarkContentEditCodec.inputRuleTriggers.contains(last) else { return false }
        return RelayMarkContentEditCodec.inputRuleMatches(before: before, text: text)
    }

    /// The shortcut typing `text` at the caret completes, reading and writing
    /// only the top-level nodes around it; nil when none does and the text is
    /// typed as usual. `paper` is the caller's projection of the document as it is now.
    public static func apply(document: RelayMarkNativeDocument, blockPath: [Int], utf16Offset: Int, text: String,
                             paper: RelayMarkCollaborativeProse) throws -> (change: RelayMarkNativeRichEditing.Change, rule: String)? {
        try RelayMarkNativeRichEditing.windowed(document: document, paper: paper, paths: [blockPath]) { scope in
            let projection = scope.projection, path = scope.local(blockPath)
            guard projection.isEditable, let row = projection.blockPaths.firstIndex(of: path) else {
                throw RelayMarkNativeDocument.Failure.invalidTextPath
            }
            let block = (String(projection.text.characters) as NSString).substring(with: projection.blockRanges[row])
            guard RelayMarkNativeRichXML.isCharacterBoundary(utf16Offset, in: block) else {
                throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
            }
            let source = try PMYXmlBridge.canonical().document(fromSnapshot: scope.tree)
            let start = try RelayMarkNativeRichEditing.positionForPath(path, in: source)
            guard source.nodeAt(start)?.isTextblock == true else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            let caret = start + 1 + utf16Offset
            return try RelayMarkNativeRichEditing.inputRule(document: document, tree: scope.tree, text: text,
                selection: ["type": "text", "anchor": caret, "head": caret], scope: scope)
        }
    }
}

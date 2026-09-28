import Foundation

/// Selection replacement over authored XML. Delegates to ProseMirror's own
/// deleteRange / replaceRange through RelayMarkNativeMarkdownV3Editing, so
/// joins across paragraphs, lists, quotes, callouts and tables match a
/// browser peer. Yrs supplies the transaction and undo.
@MainActor
public enum RelayMarkNativeMarkdownV3Replacement {
    public static func replace(document: RelayMarkNativeDocument, range: NSRange,
                               runs: [(text: String, attributes: [String: Any])],
                               expectedSnapshot: Data) throws -> Data {
        try RelayMarkNativeMarkdownV3Editing.replace(document: document, range: range, runs: runs,
                                                     expectedSnapshot: expectedSnapshot).update
    }
}

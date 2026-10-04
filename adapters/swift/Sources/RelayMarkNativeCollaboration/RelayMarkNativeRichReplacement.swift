import Foundation

/// Selection replacement over authored XML. Delegates to ProseMirror's own
/// deleteRange / replaceRange through RelayMarkNativeRichEditing, so
/// joins across paragraphs, lists, quotes, callouts and tables match a
/// browser peer. Yrs supplies the transaction and undo.
@MainActor
public enum RelayMarkNativeRichReplacement {
    public static func replace(document: RelayMarkNativeDocument, range: NSRange,
                               runs: [(text: String, attributes: [String: Any])],
                               expectedSnapshot: Data) throws -> Data {
        try RelayMarkNativeRichEditing.replace(document: document, range: range, runs: runs,
                                                     expectedSnapshot: expectedSnapshot).update
    }
}

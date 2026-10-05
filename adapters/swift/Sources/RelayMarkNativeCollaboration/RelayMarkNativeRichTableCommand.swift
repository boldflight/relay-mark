import Foundation
import RelayMarkSwift

/// Resolve the displayed cell identities, then execute the maintained table
/// command through the shared canonical PM schema and existing native writer.
@MainActor
public enum RelayMarkNativeRichTableCommand {
    public enum Operation: String, Sendable, CaseIterable {
        case addRowBefore, addRowAfter, addColumnBefore, addColumnAfter
        case deleteRow, deleteColumn, deleteTable
        case toggleHeaderCell, toggleHeaderRow, toggleHeaderColumn
        case mergeCells, splitCell
    }
    private typealias Failure = RelayMarkNativeDocument.Failure

    public static func canApply(_ operation: Operation, document: RelayMarkNativeDocument,
                                cellAnchor: Data, expectedCellID: String,
                                headAnchor: Data? = nil, expectedHeadCellID: String? = nil) -> Bool {
        guard let request = try? context(document: document, anchor: (cellAnchor, expectedCellID),
            head: headAnchor.map { ($0, expectedHeadCellID ?? "") }, expectedSnapshot: document.snapshot()) else { return false }
        return (try? prepare(operation, request: request)) != nil
    }

    public static func availableOperations(document: RelayMarkNativeDocument, cellAnchor: Data,
                                           expectedCellID: String, headAnchor: Data? = nil,
                                           expectedHeadCellID: String? = nil) -> Set<Operation> {
        guard let request = try? context(document: document, anchor: (cellAnchor, expectedCellID),
            head: headAnchor.map { ($0, expectedHeadCellID ?? "") }, expectedSnapshot: document.snapshot()) else { return [] }
        return Set(Operation.allCases.filter { (try? prepare($0, request: request)) != nil })
    }

    public static func apply(_ operation: Operation, document: RelayMarkNativeDocument,
                             cellAnchor: Data, expectedCellID: String,
                             headAnchor: Data? = nil, expectedHeadCellID: String? = nil,
                             expectedSnapshot: Data) throws -> RelayMarkNativeRichEditing.Change {
        let request = try context(document: document, anchor: (cellAnchor, expectedCellID),
            head: headAnchor.map { ($0, expectedHeadCellID ?? "") }, expectedSnapshot: expectedSnapshot)
        return try RelayMarkNativeRichEditing.command(document: document, tree: request.tree,
            name: operation.rawValue, selection: request.selection).change
    }

    private struct Context { let tree: [String: Any], source: PMNode, selection: [String: Any] }
    private static func prepare(_ operation: Operation, request: Context) throws -> Data {
        try RelayMarkContentEditCodec.command(document: JSONSerialization.data(withJSONObject: request.source.json()),
            request: JSONSerialization.data(withJSONObject: ["command": operation.rawValue, "selection": request.selection]))
    }

    private static func context(document: RelayMarkNativeDocument, anchor: (Data, String), head: (Data, String)?,
                                expectedSnapshot: Data) throws -> Context {
        guard document.integrationStatus().isComplete, try document.snapshot() == expectedSnapshot,
              try document.richProseProjection().isEditable,
              let tree = try JSONSerialization.jsonObject(with: expectedSnapshot) as? [String: Any] else { throw Failure.invalidAnchor }
        func cellPath(_ reference: (Data, String)) throws -> [Int] {
            guard let position = try document.resolve(anchor: reference.0), position.index == 0, position.path.count >= 3 else { throw Failure.invalidAnchor }
            let cell = try RelayMarkNativeRichXML.node(at: position.path, in: tree)
            let table = try RelayMarkNativeRichXML.node(at: Array(position.path.dropLast(2)), in: tree)
            guard ["tableCell", "tableHeader"].contains(cell["name"] as? String ?? ""),
                  (cell["attributes"] as? [String: Any])?["relaymarkId"] as? String == reference.1,
                  table["name"] as? String == "table" else { throw Failure.invalidAnchor }
            return position.path
        }
        let anchorPath = try cellPath(anchor), headPath = try head.map(cellPath) ?? anchorPath
        guard Array(anchorPath.dropLast(2)) == Array(headPath.dropLast(2)) else { throw Failure.invalidAnchor }
        let source = try PMYXmlBridge.canonical().document(fromSnapshot: tree)
        let start = try RelayMarkNativeRichEditing.positionForPath(anchorPath, in: source), end = try RelayMarkNativeRichEditing.positionForPath(headPath, in: source)
        return Context(tree: tree, source: source, selection: ["type": "cell", "anchor": start, "head": end])
    }
}

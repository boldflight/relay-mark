import CoreFoundation
import Foundation
import RelayMarkSwift

/// Read-only projection for the unregistered v3 plain-prose/table subset.
/// The Yrs replica remains the document owner; this never rewrites its XML.
public enum RelayMarkNativeMixedTableProjection {
    public enum Failure: Error, Equatable {
        case unsupported(String)
    }

    public static func project(snapshot: Data) throws -> RelayMarkDocument {
        let raw = try JSONSerialization.jsonObject(with: snapshot)
        let root = try object(raw, keys: ["kind", "children"])
        try require(root["kind"] as? String == "fragment", "root fragment")
        try RelayMarkNativeMarkdownBlocksV3Projection.validateDepth(root, depth: 0)
        let nodes = try children(root, minimum: 1)
        var ids = Set<String>()
        let blocks = try nodes.map { node -> [String: Any] in
            let (name, _, _) = try element(node)
            switch name {
            case "paragraph": return try paragraph(node, ids: &ids)
            case "table": return try table(node, ids: &ids)
            default: throw Failure.unsupported("top-level node \(name)")
            }
        }
        let ast: [String: Any] = ["type": "relaymark.document", "version": 1, "blocks": blocks]
        return try RelayMarkDocument.decodeJSON(JSONSerialization.data(withJSONObject: ast))
    }

    static func table(_ raw: Any, ids: inout Set<String>) throws -> [String: Any] {
        let (name, attrs, rawRows) = try element(raw)
        try require(name == "table", "table node")
        let id = try blockID(attrs, allowed: ["relaymarkId"], ids: &ids)
        try require(!rawRows.isEmpty && rawRows.count <= 256, "table row limit")
        var cellCount = 0
        var grid = Array(repeating: Set<Int>(), count: rawRows.count)
        var expectedWidth: Int?
        var rows = [[String: Any]]()
        for (rowIndex, rawRow) in rawRows.enumerated() {
            let (rowName, rowAttrs, rawCells) = try element(rawRow)
            try require(rowName == "tableRow" && !rawCells.isEmpty, "table row")
            let rowID = try blockID(rowAttrs, allowed: ["relaymarkId"], ids: &ids)
            cellCount += rawCells.count
            try require(cellCount <= 4_096, "table cell limit")
            var cells = [[String: Any]]()
            var column = 0
            for rawCell in rawCells {
                while grid[rowIndex].contains(column) { column += 1 }
                let (cell, colspan, rowspan) = try mapCell(rawCell, ids: &ids)
                try require(colspan <= 256 && rowspan <= rawRows.count &&
                            column <= 256 - colspan && rowIndex <= rawRows.count - rowspan,
                            "table span limit")
                for row in rowIndex..<(rowIndex + rowspan) {
                    for slot in column..<(column + colspan) {
                        try require(!grid[row].contains(slot), "overlapping cells")
                        grid[row].insert(slot)
                    }
                }
                cells.append(cell)
                column += colspan
            }
            let width = (grid[rowIndex].max() ?? -1) + 1
            try require(width > 0 && (expectedWidth == nil || expectedWidth == width) &&
                        (0..<width).allSatisfy(grid[rowIndex].contains), "nonrectangular table")
            expectedWidth = width
            rows.append(["id": rowID, "type": "table_row", "content": cells])
        }
        return ["id": id, "type": "table", "content": rows]
    }

    private static func mapCell(_ raw: Any, ids: inout Set<String>) throws
        -> ([String: Any], Int, Int) {
        let (name, attrs, rawParagraphs) = try element(raw)
        try require(name == "tableHeader" || name == "tableCell", "table cell")
        let id = try blockID(attrs,
                             allowed: ["relaymarkId", "colspan", "rowspan", "colwidth", "align"],
                             ids: &ids)
        let colspan = try positiveInteger(attrs["colspan"], "colspan")
        let rowspan = try positiveInteger(attrs["rowspan"], "rowspan")
        let colwidth: Any
        if let widths = attrs["colwidth"], !(widths is NSNull) {
            guard let list = widths as? [Any], list.count == colspan else {
                throw Failure.unsupported("colwidth")
            }
            colwidth = try list.map { try positiveInteger($0, "colwidth", minimum: 0) }
        } else {
            colwidth = NSNull()
        }
        let align: Any
        if let value = attrs["align"], !(value is NSNull) {
            guard let value = value as? String, ["left", "center", "right"].contains(value) else {
                throw Failure.unsupported("cell align")
            }
            align = value
        } else {
            align = NSNull()
        }
        try require(!rawParagraphs.isEmpty, "cell paragraphs")
        let paragraphs = try rawParagraphs.map {
            try RelayMarkNativeMarkdownBlocksV3Projection.block($0, depth: 0, ids: &ids)
        }
        let props: [String: Any] = ["header": name == "tableHeader", "colspan": colspan,
                                    "rowspan": rowspan, "colwidth": colwidth, "align": align]
        return (["id": id, "type": "table_cell", "props": props, "content": paragraphs],
                colspan, rowspan)
    }

    private static func paragraph(_ raw: Any, ids: inout Set<String>) throws -> [String: Any] {
        let (name, attrs, rawLeaves) = try element(raw)
        try require(name == "paragraph", "paragraph")
        let id = try blockID(attrs, allowed: ["relaymarkId"], ids: &ids)
        // A table cell uses the same TipTap inline grammar as an ordinary v3
        // paragraph. Keep one validator so marks and links cannot diverge.
        return ["id": id, "type": "paragraph",
                "content": try RelayMarkNativeMarkdownBlocksV3Projection.inline(rawLeaves, breaks: true)]
    }

    private static func blockID(_ attrs: [String: Any], allowed: Set<String>,
                                ids: inout Set<String>) throws -> String {
        try require(Set(attrs.keys).isSubset(of: allowed), "unknown attributes")
        guard let id = attrs["relaymarkId"] as? String else {
            throw Failure.unsupported("relaymarkId")
        }
        let characters = Array(id)
        let hex = Set("0123456789abcdef")
        try require(characters.count == 33 && characters[0] == "b" && characters[13] == "4" &&
                    Set("89ab").contains(characters[17]) &&
                    characters.dropFirst().allSatisfy(hex.contains), "relaymarkId")
        try require(ids.insert(id).inserted, "duplicate relaymarkId")
        return id
    }

    /// `minimum: 0` admits prosemirror-tables' unspecified column width.
    private static func positiveInteger(_ raw: Any?, _ label: String, minimum: Double = 1) throws -> Int {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, value.doubleValue.rounded() == value.doubleValue,
              value.doubleValue >= minimum, value.doubleValue <= 9_007_199_254_740_991 else {
            throw Failure.unsupported(label)
        }
        return value.intValue
    }

    private static func element(_ raw: Any) throws -> (String, [String: Any], [Any]) {
        let node = try object(raw, keys: ["kind", "name", "attributes", "children"])
        try require(node["kind"] as? String == "element", "XML element")
        guard let name = node["name"] as? String,
              let attrs = node["attributes"] as? [String: Any] else {
            throw Failure.unsupported("XML element metadata")
        }
        return (name, attrs, try children(node, minimum: 0))
    }

    private static func children(_ node: [String: Any], minimum: Int) throws -> [Any] {
        guard let children = node["children"] as? [Any], children.count >= minimum else {
            throw Failure.unsupported("XML children")
        }
        return children
    }

    private static func object(_ raw: Any, keys: Set<String>) throws -> [String: Any] {
        guard let value = raw as? [String: Any], Set(value.keys).isSubset(of: keys) else {
            throw Failure.unsupported("unknown XML fields")
        }
        return value
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ reason: String) throws {
        if !condition() { throw Failure.unsupported(reason) }
    }
}

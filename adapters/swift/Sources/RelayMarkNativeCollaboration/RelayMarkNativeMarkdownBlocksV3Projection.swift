import CoreFoundation
import Foundation
import RelayMarkSwift

/// Read-only, bounded projection of the draft v3 Markdown blocks carried by YSwift XML.
/// This does not admit v3 collaboration or editing in the native host.
public enum RelayMarkNativeMarkdownBlocksV3Projection {
    public enum Failure: Error, Equatable {
        case unsupported(String)
    }

    @MainActor
    public static func project(document: RelayMarkNativeDocument) throws -> RelayMarkDocument {
        guard document.integrationStatus().isComplete else { throw Failure.unsupported("incomplete update") }
        return try project(snapshot: document.snapshot())
    }

    public static func project(snapshot: Data) throws -> RelayMarkDocument {
        guard snapshot.count <= 4_194_304 else { throw Failure.unsupported("snapshot limit") }
        let raw = try JSONSerialization.jsonObject(with: snapshot)
        let root = try object(raw, keys: ["kind", "children"])
        try require(root["kind"] as? String == "fragment", "root fragment")
        let nodes = try children(root, minimum: 1, maximum: 4_096)
        var ids = Set<String>()
        let blocks = try nodes.map { try block($0, depth: 0, ids: &ids) }
        let ast: [String: Any] = ["type": "relaymark.document", "version": 1, "blocks": blocks]
        return try RelayMarkDocument.decodeJSON(JSONSerialization.data(withJSONObject: ast))
    }

    private static func block(_ raw: Any, depth: Int, ids: inout Set<String>) throws -> [String: Any] {
        let (name, attrs, children) = try element(raw)
        switch name {
        case "paragraph": return try paragraph(raw, ids: &ids)
        case "heading":
            let id = try blockID(attrs, allowed: ["relaymarkId", "level", "headingId"], ids: &ids)
            let level = try integer(attrs["level"], label: "heading level", maximum: 6)
            let anchor: Any
            if let value = attrs["headingId"], !(value is NSNull) {
                guard let text = value as? String, text.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$", options: .regularExpression) != nil else {
                    throw Failure.unsupported("heading ID")
                }
                anchor = text
            } else { anchor = NSNull() }
            return ["id": id, "type": "heading", "props": ["level": level, "headingId": anchor],
                    "content": try inline(children, breaks: true)]
        case "blockquote":
            let id = try blockID(attrs, allowed: ["relaymarkId"], ids: &ids)
            try require(!children.isEmpty && children.count <= 4_096, "quote children")
            return ["id": id, "type": "quote", "content": try children.map { try paragraph($0, ids: &ids) }]
        case "bulletList", "orderedList":
            try require(depth <= 1, "nested list depth")
            let ordered = name == "orderedList"
            let id = try blockID(attrs, allowed: ordered ? ["relaymarkId", "start", "type"] : ["relaymarkId"], ids: &ids)
            var props: [String: Any] = ["kind": ordered ? "ordered" : "bullet"]
            if ordered {
                try require(attrs["type"] == nil || attrs["type"] is NSNull, "ordered list type")
                props["start"] = try integer(attrs["start"], label: "list start", maximum: 9_007_199_254_740_991)
            }
            try require(!children.isEmpty && children.count <= 4_096, "list children")
            return ["id": id, "type": "list", "props": props,
                    "content": try children.map { try listItem($0, depth: depth, ids: &ids) }]
        case "codeBlock":
            let id = try blockID(attrs, allowed: ["relaymarkId", "language"], ids: &ids)
            let language: Any
            if let value = attrs["language"], !(value is NSNull) {
                guard let text = value as? String, !text.contains("\r"), !text.contains("\n") else {
                    throw Failure.unsupported("code language")
                }
                language = text
            } else { language = NSNull() }
            return ["id": id, "type": "code", "props": ["language": language],
                    "content": try inline(children, breaks: false)]
        case "horizontalRule":
            let id = try blockID(attrs, allowed: ["relaymarkId"], ids: &ids)
            try require(children.isEmpty, "horizontal rule children")
            return ["id": id, "type": "horizontal_rule", "content": [[String: Any]]()]
        case "table":
            // Reuse the existing strict grid and cell validator. It returns the same
            // portable AST shape and keeps the table boundary unchanged.
            let fragment: [String: Any] = ["kind": "fragment", "children": [raw]]
            let table = try RelayMarkNativeMixedTableProjection.project(
                snapshot: JSONSerialization.data(withJSONObject: fragment)).blocks[0]
            func register(_ block: RelayMarkBlock) throws {
                try require(ids.insert(block.id).inserted, "duplicate relaymarkId")
                for child in block.childBlocks { try register(child) }
            }
            try register(table)
            return try object(JSONSerialization.jsonObject(with: JSONEncoder().encode(table)),
                              keys: ["id", "type", "props", "content", "evidence_refs"])
        default: throw Failure.unsupported("block \(name)")
        }
    }

    private static func listItem(_ raw: Any, depth: Int, ids: inout Set<String>) throws -> [String: Any] {
        let (name, attrs, children) = try element(raw)
        try require(name == "listItem" && (1...2).contains(children.count), "list item")
        let id = try blockID(attrs, allowed: ["relaymarkId"], ids: &ids)
        var content = [try paragraph(children[0], ids: &ids)]
        if children.count == 2 {
            let (nestedName, _, _) = try element(children[1])
            try require(nestedName == "bulletList" || nestedName == "orderedList", "list item children")
            content.append(try block(children[1], depth: depth + 1, ids: &ids))
        }
        return ["id": id, "type": "list_item", "content": content]
    }

    private static func paragraph(_ raw: Any, ids: inout Set<String>) throws -> [String: Any] {
        let (name, attrs, children) = try element(raw)
        try require(name == "paragraph", "paragraph")
        let id = try blockID(attrs, allowed: ["relaymarkId"], ids: &ids)
        return ["id": id, "type": "paragraph", "content": try inline(children, breaks: true)]
    }

    private static func inline(_ children: [Any], breaks: Bool) throws -> [[String: Any]] {
        try require(children.count <= 4_096, "inline child limit")
        var result = [[String: Any]]()
        for child in children {
            let node = try object(child, keys: ["kind", "name", "attributes", "children", "delta"])
            if node["kind"] as? String == "text" {
                try require(Set(node.keys).isSubset(of: ["kind", "delta"]), "text fields")
                guard let runs = node["delta"] as? [Any], runs.count <= 4_096 else {
                    throw Failure.unsupported("text delta")
                }
                for run in runs {
                    let item = try object(run, keys: ["insert", "attributes"])
                    if let marks = item["attributes"] { try require(try object(marks, keys: []).isEmpty, "text marks") }
                    guard let value = item["insert"] as? String, !value.isEmpty, value.utf16.count <= 131_072 else {
                        throw Failure.unsupported("text run")
                    }
                    result.append(["type": "text", "text": value])
                }
            } else {
                let (name, attrs, grandchildren) = try element(child)
                try require(breaks && name == "hardBreak" && attrs.isEmpty && grandchildren.isEmpty,
                            "inline element")
                result.append(["type": "hard_break"])
            }
        }
        return result
    }

    private static func blockID(_ attrs: [String: Any], allowed: Set<String>, ids: inout Set<String>) throws -> String {
        try require(Set(attrs.keys).isSubset(of: allowed), "unknown attributes")
        guard let id = attrs["relaymarkId"] as? String else { throw Failure.unsupported("relaymarkId") }
        let chars = Array(id)
        let hex = Set("0123456789abcdef")
        try require(chars.count == 33 && chars[0] == "b" && chars[13] == "4" &&
                    Set("89ab").contains(chars[17]) && chars.dropFirst().allSatisfy(hex.contains), "relaymarkId")
        try require(ids.insert(id).inserted, "duplicate relaymarkId")
        return id
    }

    private static func integer(_ raw: Any?, label: String, maximum: Double) throws -> Int {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, value.doubleValue.rounded() == value.doubleValue,
              value.doubleValue >= 1, value.doubleValue <= maximum else { throw Failure.unsupported(label) }
        return value.intValue
    }

    private static func element(_ raw: Any) throws -> (String, [String: Any], [Any]) {
        let node = try object(raw, keys: ["kind", "name", "attributes", "children"])
        try require(node["kind"] as? String == "element", "XML element")
        guard let name = node["name"] as? String, let attrs = node["attributes"] as? [String: Any] else {
            throw Failure.unsupported("XML metadata")
        }
        return (name, attrs, try children(node, minimum: 0, maximum: 4_096))
    }

    private static func children(_ node: [String: Any], minimum: Int, maximum: Int) throws -> [Any] {
        guard let children = node["children"] as? [Any], (minimum...maximum).contains(children.count) else {
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

    private static func require(_ condition: @autoclosure () throws -> Bool, _ reason: String) throws {
        if try !condition() { throw Failure.unsupported(reason) }
    }
}

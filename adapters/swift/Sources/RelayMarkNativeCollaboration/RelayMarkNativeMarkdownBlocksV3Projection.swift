import CoreFoundation
import Foundation
import RelayMarkProseProjection
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
        try validateDepth(root, depth: 0)
        let nodes = try children(root, minimum: 1, maximum: 4_096)
        var ids = Set<String>()
        let blocks = try nodes.map { try block($0, depth: 0, ids: &ids) }
        let ast: [String: Any] = ["type": "relaymark.document", "version": 1, "blocks": blocks]
        return try RelayMarkDocument.decodeJSON(JSONSerialization.data(withJSONObject: ast))
    }

    static func block(_ raw: Any, depth: Int, calloutDepth: Int = 0, taskDepth: Int = 0,
                              ids: inout Set<String>) throws -> [String: Any] {
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
            return ["id": id, "type": "quote", "content": try children.map { try block($0, depth: 0, calloutDepth: calloutDepth, ids: &ids) }]
        case "bulletList", "orderedList":
            try require(depth < 16, "nested list depth")
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
        case "taskList":
            try require(taskDepth < 16, "task list depth")
            let id = try blockID(attrs, allowed: ["relaymarkId"], ids: &ids)
            try require(!children.isEmpty && children.count <= 4_096, "task list children")
            return ["id": id, "type": "task_list",
                    "content": try children.map { try taskItem($0, depth: taskDepth, ids: &ids) }]
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
        case "image":
            let id = try blockID(attrs, allowed: ["relaymarkId", "src", "alt", "title", "width", "height"], ids: &ids)
            let media = try RelayMarkMediaV3Contract.validate(name: name, attributes: attrs, children: [])
            try require(children.isEmpty, "image children")
            return ["id": id, "type": "image",
                    "props": ["src": media.source, "alt": media.alt.map { $0 as Any } ?? NSNull(),
                              "title": media.title.map { $0 as Any } ?? NSNull()],
                    "content": [[String: Any]]()]
        case "videoEmbed":
            let id = try blockID(attrs, allowed: ["relaymarkId", "videoId", "playbackId", "title",
                                                   "source", "thumbnailUrl", "status", "youtubeId",
                                                   "uploadPercent"], ids: &ids)
            try require(children.isEmpty, "video children")
            let media = try RelayMarkMediaV3Contract.validate(name: name, attributes: attrs, children: [])
            return ["id": id, "type": "relay.video_embed", "props": ["videoId": media.source],
                    "content": [[String: Any]]()]
        case "relayEntityReference":
            let id = try blockID(attrs, allowed: ["relaymarkId", "entityRef", "entityId", "entityType",
                                                   "label", "projection", "source"], ids: &ids)
            try require(children.isEmpty, "entity reference children")
            guard let entityRef = attrs["entityRef"] as? String,
                  let entityId = attrs["entityId"] as? String,
                  let label = attrs["label"] as? String,
                  let projection = attrs["projection"] as? String,
                  let source = attrs["source"] as? String,
                  attrs["entityType"] as? String == "Entity",
                  entityReferenceSource(source, entityRef: entityRef, entityId: entityId,
                                        label: label, projection: projection) else {
                throw Failure.unsupported("entity reference source/identity")
            }
            return ["id": id, "type": "relay.entity_reference",
                    "props": ["id": entityRef, "label": label, "projection": projection, "source": source],
                    "content": [[String: Any]]()]
        case "relayButton", "relayAnchor", "relayConnection":
            let validated = try RelayMarkPaperControlContract.validate(nodeName: name, attributes: attrs)
            let id = try blockID(attrs, allowed: Set(attrs.keys), ids: &ids)
            try require(children.isEmpty, "paper control children")
            var props: [String: Any] = ["control": validated.control.rawValue, "source": validated.source]
            for (key, value) in validated.authored { props[key] = value }
            return ["id": id, "type": "relay.paper_control", "props": props,
                    "content": [[String: Any]]()]
        case "agentSuggestion":
            let authored = try RelayMarkAgentSuggestionV3Contract.validate(attributes: attrs)
            let id = try blockID(attrs, allowed: Set(attrs.keys), ids: &ids)
            try require(children.isEmpty, "AgentSuggestion children")
            var props: [String: Any] = ["review": authored.review, "kind": authored.kind,
                                        "evidence": authored.evidence]
            if let confidence = authored.confidence { props["confidence"] = confidence }
            return ["id": id, "type": "relay.agent_suggestion", "props": props,
                    "content": [["type": "text", "text": authored.content]]]
        case "callout":
            try require(calloutDepth < 8, "callout depth")
            let id = try blockID(attrs, allowed: ["relaymarkId", "tone", "emphasis"], ids: &ids)
            guard let tone = attrs["tone"] as? String,
                  ["neutral", "primary", "secondary", "accent", "info", "success", "warning", "error"].contains(tone),
                  let emphasis = attrs["emphasis"] as? String,
                  ["soft", "strong"].contains(emphasis) else {
                throw Failure.unsupported("callout appearance")
            }
            try require(!children.isEmpty && children.count <= 4_096, "callout children")
            var content = [[String: Any]]()
            var body = children[...]
            if try element(children[0]).0 == "calloutTitle" {
                content.append(try calloutTitle(children[0], ids: &ids))
                body = children.dropFirst()
                try require(!body.isEmpty, "callout body")
            }
            for child in body {
                content.append(try block(child, depth: 0, calloutDepth: calloutDepth + 1, ids: &ids))
            }
            return ["id": id, "type": "relay.callout",
                    "props": ["tone": tone, "emphasis": emphasis], "content": content]
        case "table":
            return try RelayMarkNativeMixedTableProjection.table(raw, ids: &ids)
        default: throw Failure.unsupported("block \(name)")
        }
    }

    private static func calloutTitle(_ raw: Any, ids: inout Set<String>) throws -> [String: Any] {
        let (name, attrs, children) = try element(raw)
        try require(name == "calloutTitle", "callout title")
        let id = try blockID(attrs, allowed: ["relaymarkId"], ids: &ids)
        return ["id": id, "type": "relay.callout_title", "content": try inline(children, breaks: false)]
    }

    private static func listItem(_ raw: Any, depth: Int, ids: inout Set<String>) throws -> [String: Any] {
        let (name, attrs, children) = try element(raw)
        try require(name == "listItem" && !children.isEmpty && children.count <= 4_096, "list item")
        let id = try blockID(attrs, allowed: ["relaymarkId"], ids: &ids)
        var content = [try paragraph(children[0], ids: &ids)]
        for child in children.dropFirst() {
            let (childName, _, _) = try element(child)
            content.append(try block(child,
                depth: ["bulletList", "orderedList"].contains(childName) ? depth + 1 : 0, ids: &ids))
        }
        return ["id": id, "type": "list_item", "content": content]
    }

    static func validateDepth(_ node: [String: Any], depth: Int) throws {
        try require(depth <= 64, "document nesting limit")
        for child in node["children"] as? [[String: Any]] ?? [] {
            try validateDepth(child, depth: depth + 1)
        }
    }

    private static func taskItem(_ raw: Any, depth: Int, ids: inout Set<String>) throws -> [String: Any] {
        let (name, attrs, children) = try element(raw)
        try require(name == "taskItem" && !children.isEmpty && children.count <= 4_096, "task item")
        let id = try blockID(attrs, allowed: ["relaymarkId", "checked", "entityId"], ids: &ids)
        let checked: Bool
        if let value = attrs["checked"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw Failure.unsupported("task checked")
            }
            checked = number.boolValue
        } else { checked = false }
        let entity: Any
        if let linked = attrs["entityId"], !(linked is NSNull) {
            guard let value = linked as? String, UUID(uuidString: value)?.uuidString.lowercased() == value else {
                throw Failure.unsupported("task entityId")
            }
            entity = value
        } else {
            entity = NSNull()
        }
        var content = [try paragraph(children[0], ids: &ids)]
        for child in children.dropFirst() {
            let (childName, _, _) = try element(child)
            content.append(try block(child, depth: 0, taskDepth: childName == "taskList" ? depth + 1 : depth,
                                     ids: &ids))
        }
        return ["id": id, "type": "task_item", "props": ["checked": checked, "entityId": entity],
                "content": content]
    }

    private static func paragraph(_ raw: Any, ids: inout Set<String>) throws -> [String: Any] {
        let (name, attrs, children) = try element(raw)
        try require(name == "paragraph", "paragraph")
        let id = try blockID(attrs, allowed: ["relaymarkId"], ids: &ids)
        return ["id": id, "type": "paragraph", "content": try inline(children, breaks: true)]
    }

    static func inline(_ children: [Any], breaks: Bool) throws -> [[String: Any]] {
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
                    guard let value = item["insert"] as? String, !value.isEmpty, value.utf16.count <= 131_072 else {
                        throw Failure.unsupported("text run")
                    }
                    result.append(try markedText(value, attributes: item["attributes"]))
                }
            } else {
                let (name, attrs, grandchildren) = try element(child)
                if breaks && (name == "relayReference" || name == "relayTag") {
                    try require(grandchildren.isEmpty, "inline atom children")
                    result.append(try atom(name, attrs: attrs))
                    continue
                }
                try require(breaks && name == "hardBreak" && attrs.isEmpty && grandchildren.isEmpty,
                            "inline element")
                result.append(["type": "hard_break"])
            }
        }
        return result
    }

    private static func atom(_ name: String, attrs: [String: Any]) throws -> [String: Any] {
        let uuidPattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
        func validUUID(_ value: String) -> Bool {
            value.range(of: uuidPattern, options: .regularExpression) != nil
        }
        if name == "relayReference" {
            try require(Set(attrs.keys).isSubset(of: Set(["entityType", "entityId", "label", "source", "status", "subtitle"])),
                        "reference attributes")
            guard let type = attrs["entityType"] as? String,
                  type.range(of: "^[A-Z][A-Za-z0-9]*(?: [A-Z][A-Za-z0-9]*)*$", options: .regularExpression) != nil,
                  type != "Tag", let id = attrs["entityId"] as? String, validUUID(id),
                  let label = attrs["label"] as? String, !label.isEmpty,
                  label == label.trimmingCharacters(in: .whitespacesAndNewlines),
                  label.rangeOfCharacter(from: CharacterSet.newlines) == nil, !label.contains("]"),
                  let source = attrs["source"] as? String,
                  source == "[[\(type): \(id) | \(label)]]",
                  (attrs["status"] == nil || attrs["status"] is NSNull),
                  (attrs["subtitle"] == nil || attrs["subtitle"] is NSNull) else {
                throw Failure.unsupported("reference identity or source")
            }
            return ["type": "relay.entity_ref", "id": id, "label": label,
                    "props": ["entityType": type, "source": source]]
        }
        try require(Set(attrs.keys).isSubset(of: Set(["id", "name", "color", "source"])), "tag attributes")
        guard let id = attrs["id"] as? String, validUUID(id),
              let tagName = attrs["name"] as? String,
              tagName.range(of: "^[a-z0-9][a-z0-9_-]*$", options: .regularExpression) != nil,
              let source = attrs["source"] as? String,
              source == "[[Tag: \(id) | #\(tagName)]]",
              (attrs["color"] == nil || attrs["color"] is NSNull) else {
            throw Failure.unsupported("tag identity or source")
        }
        return ["type": "relay.tag_ref", "id": id, "label": "#\(tagName)",
                "props": ["name": tagName, "source": source]]
    }

    /// TipTap's mark rank is link, bold, code, italic, strike, underline,
    /// highlight, superscript, subscript. Code excludes all other marks.
    /// Portable wrappers follow that outer-to-inner rank so the
    /// inverse can restore one exact normalized ProseMirror text run.
    private static func markedText(_ text: String, attributes raw: Any?) throws -> [String: Any] {
        let attrs = try object(raw ?? [String: Any](),
                               keys: ["link", "bold", "code", "italic", "strike", "underline",
                                      "highlight", "superscript", "subscript"])
        try require(attrs["code"] == nil || attrs.count == 1, "code mark combination")
        for key in ["bold", "code", "italic", "strike", "underline", "highlight", "superscript", "subscript"]
            where attrs[key] != nil {
            try require(try object(attrs[key]!, keys: []).isEmpty, "mark attributes")
        }
        var result: [String: Any] = ["type": "text", "text": text]
        for key in ["subscript", "superscript", "highlight", "underline", "strike", "italic", "code", "bold", "link"]
            where attrs[key] != nil {
            let type: String
            switch key {
            case "strike": type = "strikethrough"
            case "italic": type = "emphasis"
            case "code": type = "code_span"
            case "bold": type = "strong"
            case "underline", "highlight", "superscript", "subscript": type = key
            default: type = "link"
            }
            var wrapper: [String: Any] = ["type": type, "content": [result]]
            if key == "link" {
                let link = try object(attrs[key]!, keys: ["href", "target", "rel", "class", "title"])
                try require(Set(link.keys) == Set(["href", "target", "rel", "class", "title"]),
                            "link attributes")
                guard let href = link["href"] as? String, !href.isEmpty,
                      href.rangeOfCharacter(from: .controlCharacters) == nil,
                      !href.contains("<"), !href.contains(">") else {
                    throw Failure.unsupported("link href")
                }
                try require(link["target"] as? String == "_blank" &&
                            link["rel"] as? String == "noopener noreferrer nofollow" &&
                            (link["class"] == nil || link["class"] is NSNull) &&
                            (link["title"] == nil || link["title"] is NSNull), "link attributes")
                wrapper["href"] = href
            }
            result = wrapper
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

    private static func entityReferenceSource(_ source: String, entityRef: String, entityId: String,
                                              label: String, projection: String) -> Bool {
        guard source.utf16.count <= 16_384,
              let directive = try? NSRegularExpression(
                pattern: #"^@EntityRef\s*\(([\s\S]*?)\)\s*\{(?:\r\n|\n|\r)  ([^\r\n{}]+)(?:\r\n|\n|\r)\}$"#),
              let match = directive.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              match.range == NSRange(source.startIndex..., in: source),
              let headerRange = Range(match.range(at: 1), in: source),
              let bodyRange = Range(match.range(at: 2), in: source) else { return false }
        let body = String(source[bodyRange])
        guard body == body.trimmingCharacters(in: .whitespacesAndNewlines),
              !body.contains("[["), !body.contains("]]"), !body.contains("](relay:"),
              !body.hasPrefix("@"), !body.hasPrefix("#") else { return false }
        guard let attribute = try? NSRegularExpression(
            pattern: #"^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*("(?:\\.|[^"\\])*")"#) else { return false }
        var remaining = String(source[headerRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        var values = [String: String]()
        while !remaining.isEmpty {
            guard let token = attribute.firstMatch(in: remaining,
                                                   range: NSRange(remaining.startIndex..., in: remaining)),
                  token.range.location == 0,
                  let keyRange = Range(token.range(at: 1), in: remaining),
                  let valueRange = Range(token.range(at: 2), in: remaining) else { return false }
            let key = String(remaining[keyRange])
            guard ["id", "label", "projection"].contains(key), values[key] == nil,
                  let value = try? JSONDecoder().decode(String.self,
                                                         from: Data(remaining[valueRange].utf8)) else { return false }
            values[key] = value
            guard let consumed = Range(token.range, in: remaining) else { return false }
            remaining = String(remaining[consumed.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                guard remaining.hasPrefix(",") else { return false }
                remaining.removeFirst()
                remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !remaining.isEmpty else { return false }
            }
        }
        guard entityRef == values["id"], entityRef == "entity:\(entityId)",
              UUID(uuidString: entityId)?.uuidString.lowercased() == entityId,
              label == (values["label"] ?? body), !label.isEmpty,
              label == label.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.contains("\r"), !label.contains("\n"),
              projection == (values["projection"] ?? "link"),
              ["link", "chip", "card"].contains(projection) else { return false }
        return true
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

import Foundation
import Yniffi
import YSwift
import RelayMarkSwift

/// The y-prosemirror binding between a canonical Y.XmlFragment and a ProseMirror
/// document: createNodeFromYElement for reading, and updateYFragment /
/// updateYText for writing a transformed document back, so retained
/// subtrees keep their Yrs identity exactly as a browser peer's edit would.
/// Unknown node types, attributes or marks are refused rather than dropped.
final class PMYXmlBridge {
    enum Child {
        case node(PMNode)
        case text([PMNode])
    }

    nonisolated(unsafe) private static let cachedSchema: PMSchema? = {
        guard let data = RelayMarkNativeProseMirrorSchema.json.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return try? PMSchema(json: json, nodeAttributeOrder: RelayMarkNativeProseMirrorSchema.nodeAttributeOrder,
                            markAttributeOrder: RelayMarkNativeProseMirrorSchema.markAttributeOrder)
    }()

    let schema: PMSchema
    /// Children of each converted PM element in Y order; identity mapping for updateYFragment.
    private var sources: [ObjectIdentifier: [Child]] = [:]
    private var retained: [PMNode] = []

    private var causalWrite: Data?
    private var causalTargets = Set<String>()
    private var causalNodes: [ObjectIdentifier:Bool] = [:]
    func prepareWrite(_ prepared: Data) throws {
        guard let value=try JSONSerialization.jsonObject(with:prepared) as? [String:Any],
              let targets=value["causal_targets"] as? [String] else {throw RelayMarkNativeDocument.Failure.unsupportedProseEdit}
        causalWrite=prepared;causalTargets=Set(targets);causalNodes.removeAll()
    }
    private func requiresWrite(_ node:PMNode) -> Bool {
        let key=ObjectIdentifier(node)
        if let value=causalNodes[key] {return value}
        let result=(node.attrs["relaymarkId"] as? String).map{causalTargets.contains($0)} == true || node.content.children.contains{requiresWrite($0)}
        causalNodes[key]=result;return result
    }
    private func requiresWrite(_ child: Child, y: YXmlNode, sourceParent: PMNode?, sourceGroup: Int,
                               targetParent: PMNode, targetGroup: Int, in tx: YrsTransaction) throws -> Bool {
        switch child {
        case .node(let node): return requiresWrite(node)
        case .text:
            guard y.kind(in: tx) == "text" else { return true }
            return try textPlan(y, sourceParent: sourceParent, sourceGroup: sourceGroup,
                targetParent: targetParent, targetGroup: targetGroup, in: tx).contains { $0["retain"] == nil }
        }
    }

    init(schema: PMSchema) { self.schema = schema }

    static func canonical() throws -> PMYXmlBridge {
        guard let schema = cachedSchema else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        return PMYXmlBridge(schema: schema)
    }

    /// Shared-schema attribute order is observable CRDT allocation order. Swift
    /// Dictionary order must never decide item clocks in construction or writes.
    static func orderedAttributes(nodeName: String, values: [String: Any]) throws -> [(String, Any)] {
        let bridge = try canonical()
        guard let type = bridge.schema.nodes[nodeName], !type.isText,
              Set(values.keys).isSubset(of: Set(type.attrs.map(\.name))) else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return type.attrs.compactMap { attribute in values[attribute.name].map { (attribute.name, $0) } }
    }

    /// Replacement snapshots already contain physical fields. Validate them
    /// through the sole codec, then retain schema order for plain attributes
    /// and a deterministic order for the codec-owned additional fields.
    static func orderedPhysicalAttributes(nodeName: String, values: [String: Any]) throws -> [(String, Any)] {
        let logical = try logicalAttributes(nodeName: nodeName, physical: values)
        _ = try orderedAttributes(nodeName: nodeName, values: logical)
        let schema = try canonical().schema
        guard let type = schema.nodes[nodeName] else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let names = type.attrs.map(\.name)
        return names.compactMap { name in values[name].map { (name, $0) } }
            + values.keys.filter { !names.contains($0) }.sorted().map { ($0, values[$0]!) }
    }

    private static func logicalAttributes(nodeName: String, physical: [String: Any]) throws -> [String: Any] {
        try RelayMarkContentEditCodec.decodeDocumentAttributes(nodeName: nodeName, attributes: physical)
    }
    private static func physicalAttributes(nodeName: String, logical: [String: Any]) throws -> [String: Any] {
        _ = try orderedAttributes(nodeName: nodeName, values: logical)
        return try RelayMarkContentEditCodec.encodeDocumentAttributes(nodeName: nodeName, attributes: logical)
    }

    // MARK: Y XML snapshot → ProseMirror

    func document(fromSnapshot tree: [String: Any]) throws -> PMNode {
        let (nodes, groups) = try children(tree["children"] as? [[String: Any]] ?? [])
        let doc = try schema.topNodeType.create(["relaymark":tree["metadata"] as? [String:Any] ?? [:]], PMFragment.fromArray(nodes))
        record(doc, groups)
        return doc
    }

    private func record(_ node: PMNode, _ groups: [Child]) {
        sources[ObjectIdentifier(node)] = groups
        retained.append(node)
    }

    private func children(_ raw: [[String: Any]]) throws -> ([PMNode], [Child]) {
        var nodes: [PMNode] = [], groups: [Child] = []
        for child in raw {
            if child["kind"] as? String == "text" {
                let texts = try (child["delta"] as? [[String: Any]] ?? []).compactMap { run -> PMNode? in
                    guard let insert = run["insert"] as? String else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
                    if insert.isEmpty { return nil }
                    return schema.text(Array(insert.utf16), marks: try marks(run["attributes"] as? [String: Any] ?? [:]))
                }
                nodes.append(contentsOf: texts)
                groups.append(.text(texts))
            } else {
                let node = try element(child)
                nodes.append(node)
                groups.append(.node(node))
            }
        }
        return (nodes, groups)
    }

    private func marks(_ attributes: [String: Any]) throws -> [PMMark] {
        try PMMark.setFrom(attributes.map { key, value in
            guard let type = schema.marks[key] else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            return type.create(value as? [String: Any] ?? [:])
        })
    }

    private func element(_ raw: [String: Any]) throws -> PMNode {
        guard raw["kind"] as? String == "element", let name = raw["name"] as? String,
              let type = schema.nodes[name], !type.isText else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let attributes = try Self.logicalAttributes(nodeName: name, physical: raw["attributes"] as? [String: Any] ?? [:])
        let known = Set(type.attrs.map(\.name))
        guard attributes.keys.allSatisfy(known.contains) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let rawChildren = raw["children"] as? [[String: Any]] ?? []
        guard !type.isLeaf || rawChildren.isEmpty else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
        let (nodes, groups) = try children(rawChildren)
        let node = try type.create(attributes, PMFragment.fromArray(nodes))
        record(node, groups)
        return node
    }

    // MARK: ProseMirror → Y XML snapshot (prospective validation)

    func snapshot(_ doc: PMNode) throws -> [String: Any] {
        ["kind": "fragment", "children": try Self.normalize(doc).map(snapshot),"metadata":doc.attrs["relaymark"] ?? [:]]
    }

    private func snapshot(_ child: Child) throws -> [String: Any] {
        switch child {
        case .text(let texts):
            return ["kind": "text", "delta": texts.map { text -> [String: Any] in
                let attributes = Self.attributes(text.marks)
                return attributes.isEmpty ? ["insert": text.textString]
                    : ["insert": text.textString, "attributes": attributes]
            }]
        case .node(let node):
            return ["kind": "element", "name": node.type.name,
                    "attributes": try Self.physicalAttributes(nodeName: node.type.name, logical: node.attrs),
                    "children": try Self.normalize(node).map(snapshot)]
        }
    }

    static func normalize(_ node: PMNode) -> [Child] {
        var result: [Child] = []
        for child in node.content.children {
            if child.isText, case .text(let texts)? = result.last {
                result[result.count - 1] = .text(texts + [child])
            } else {
                result.append(child.isText ? .text([child]) : .node(child))
            }
        }
        return result
    }

    static func attributes(_ marks: [PMMark]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: marks.map { ($0.type.name, $0.attrs as Any) })
    }

    // MARK: updateYFragment

    private func mapped(_ source: PMNode?, count: Int) -> [Child]? {
        guard let source, let children = sources[ObjectIdentifier(source)], children.count == count else { return nil }
        return children
    }

    private static func mappedIdentity(_ mapped: Child?, _ child: Child) -> Bool {
        switch (mapped, child) {
        case let (.node(a)?, .node(b)): return a === b
        case let (.text(a)?, .text(b)): return a.count == b.count && zip(a, b).allSatisfy { $0 === $1 }
        default: return false
        }
    }

    private static func sourceNode(_ child: Child?) -> PMNode? {
        if case .node(let node)? = child { return node }
        return nil
    }

    /// `window` limits the write to those children of `y`; the PM node then
    /// holds only them, and every index written is offset by the window's start.
    func update(_ y: YXmlNode, _ p: PMNode, source: PMNode?, in tx: YrsTransaction, window: Range<Int>? = nil) throws {
        let base = window?.lowerBound ?? 0
        let isElement = y.kind(in: tx) == "element"
        if isElement {
            guard y.tag(in: tx) == p.type.name else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            let yAttrs = try y.attributes(in: tx)
            let physical = try Self.physicalAttributes(nodeName: p.type.name, logical: p.attrs)
            for (key, value) in try Self.orderedPhysicalAttributes(nodeName: p.type.name, values: physical) {
                // Maintained y-tiptap's codec path uses equalityDeep. Literal
                // null and unchanged nested settings retain their original Items.
                if !pmCompareDeep(yAttrs[key], value) { try y.setAttribute(key, value: value, in: tx) }
            }
            for key in yAttrs.keys.sorted() where physical[key] == nil { try y.removeAttribute(key, in: tx) }
        }
        let pChildren = Self.normalize(p)
        let yChildren = try window.map { range in try range.map { index -> YXmlNode in
            guard let child = y.child(at: UInt32(index), in: tx) else { throw RelayMarkNativeDocument.Failure.unsupportedProseEdit }
            return child
        } } ?? y.children(in: tx)
        let pCount = pChildren.count, yCount = yChildren.count, minCount = min(pCount, yCount)
        let mapping = mapped(source, count: yCount)
        if try reconcileMappedChildren(y, p, source: source, yChildren: yChildren,
                                       pChildren: pChildren, mapping: mapping, base: base, in: tx) { return }
        var left = 0, right = 0
        while left < minCount {
            if try requiresWrite(pChildren[left], y: yChildren[left], sourceParent: source, sourceGroup: left, targetParent: p, targetGroup: left, in: tx) {break}
            if !Self.mappedIdentity(mapping?[left], pChildren[left]),
               !(try equal(yChildren[left], pChildren[left], in: tx)) { break }
            left += 1
        }
        while right + left < minCount {
            let yIndex = yCount - right - 1, pIndex = pCount - right - 1
            if try requiresWrite(pChildren[pIndex], y: yChildren[yIndex], sourceParent: source, sourceGroup: yIndex, targetParent: p, targetGroup: pIndex, in: tx) {break}
            if !Self.mappedIdentity(mapping?[yIndex], pChildren[pIndex]),
               !(try equal(yChildren[yIndex], pChildren[pIndex], in: tx)) { break }
            right += 1
        }
        while yCount - left - right > 0 && pCount - left - right > 0 {
            let leftY = yChildren[left], leftP = pChildren[left]
            let rightIndex = yCount - right - 1
            let rightY = yChildren[rightIndex], rightP = pChildren[pCount - right - 1]
            if leftY.kind(in: tx) == "text", case .text(let texts) = leftP {
                let matches=try equalText(leftY,texts,in:tx)
                if try requiresWrite(leftP, y: leftY, sourceParent: source, sourceGroup: left, targetParent: p, targetGroup: left, in: tx) || !matches { try updateText(leftY, texts, sourceParent:source,sourceGroup:left,targetParent:p,targetGroup:left,in:tx) }
                left += 1
                continue
            }
            var updateLeft = matchNodeName(leftY, leftP, in: tx)
            var updateRight = matchNodeName(rightY, rightP, in: tx)
            if updateLeft && updateRight {
                let equalityLeft = try equalityFactor(leftY, leftP, source: Self.sourceNode(mapping?[left]), in: tx)
                let equalityRight = try equalityFactor(rightY, rightP, source: Self.sourceNode(mapping?[rightIndex]), in: tx)
                if equalityLeft.found && !equalityRight.found { updateRight = false }
                else if !equalityLeft.found && equalityRight.found { updateLeft = false }
                else if equalityLeft.factor < equalityRight.factor { updateLeft = false }
                else { updateRight = false }
            }
            if updateLeft, case .node(let node) = leftP {
                try update(leftY, node, source: Self.sourceNode(mapping?[left]), in: tx)
                left += 1
            } else if updateRight, case .node(let node) = rightP {
                try update(rightY, node, source: Self.sourceNode(mapping?[rightIndex]), in: tx)
                right += 1
            } else {
                try y.removeChildren(start: UInt32(base + left), length: 1, in: tx)
                try create(leftP, in: y, at: base + left, tx)
                left += 1
            }
        }
        let deleteCount = yCount - left - right
        if yCount == 1 && pCount == 0 && yChildren[0].kind(in: tx) == "text" {
            let length = yChildren[0].length(in: tx)
            if length > 0 { try yChildren[0].removeText(start: 0, length: length, in: tx) }
        } else if deleteCount > 0 {
            try y.removeChildren(start: UInt32(base + left), length: UInt32(deleteCount), in: tx)
        }
        if left + right < pCount {
            for (offset, child) in pChildren[left..<(pCount - right)].enumerated() {
                try create(child, in: y, at: base + left + offset, tx)
            }
        }
    }

    // Maintained y-tiptap reconciles reordered mapped PM children before its
    // positional fallback. Anchors are PM object identities, never rich IDs,
    // equal labels, or semantically equal attributes.
    private func mappedChildAnchors(_ mapping: [Child]?, _ targets: [Child]) -> [(y: Int, p: Int)] {
        guard let mapping else { return [] }
        var targetIndices: [ObjectIdentifier: Int] = [:]
        for (index, child) in targets.enumerated() {
            if case .node(let node) = child, targetIndices[ObjectIdentifier(node)] == nil {
                targetIndices[ObjectIdentifier(node)] = index
            }
        }
        var candidates: [(y: Int, p: Int)] = []
        for (index, child) in mapping.enumerated() {
            if case .node(let node) = child, let target = targetIndices[ObjectIdentifier(node)] {
                candidates.append((index, target))
            }
        }
        var predecessors = Array(repeating: -1, count: candidates.count), tails: [Int] = []
        for index in candidates.indices {
            var low = 0, high = tails.count
            while low < high {
                let middle = (low + high) / 2
                if candidates[tails[middle]].p < candidates[index].p { low = middle + 1 }
                else { high = middle }
            }
            predecessors[index] = low > 0 ? tails[low - 1] : -1
            if low == tails.count { tails.append(index) } else { tails[low] = index }
        }
        guard var index = tails.last else { return [] }
        var anchors: [(y: Int, p: Int)] = []
        while index != -1 { anchors.append(candidates[index]); index = predecessors[index] }
        return anchors.reversed()
    }

    private func reconcileMappedChildren(_ y: YXmlNode, _ p: PMNode, source: PMNode?,
                                        yChildren: [YXmlNode], pChildren: [Child], mapping: [Child]?,
                                        base: Int = 0, in tx: YrsTransaction) throws -> Bool {
        let anchors = mappedChildAnchors(mapping, pChildren)
        guard anchors.count >= 2, anchors.contains(where: { $0.y != $0.p }),
              anchors.allSatisfy({ matchNodeName(yChildren[$0.y], pChildren[$0.p], in: tx) }) else { return false }

        func updateMatching(_ oldIndex: Int, _ targetIndex: Int) throws -> Bool {
            let old = yChildren[oldIndex], target = pChildren[targetIndex]
            if old.kind(in: tx) == "text", case .text(let texts) = target {
                if try requiresWrite(target, y: old, sourceParent: source, sourceGroup: oldIndex,
                                     targetParent: p, targetGroup: targetIndex, in: tx) || !equalText(old, texts, in: tx) {
                    try updateText(old, texts, sourceParent: source, sourceGroup: oldIndex,
                                   targetParent: p, targetGroup: targetIndex, in: tx)
                }
                return true
            }
            if matchNodeName(old, target, in: tx), case .node(let node) = target {
                if try requiresWrite(node) || !equal(old, target, in: tx) {
                    try update(old, node, source: Self.sourceNode(mapping?[oldIndex]), in: tx)
                }
                return true
            }
            return false
        }
        func reconcileGap(_ oldStart: Int, _ oldEnd: Int, _ targetStart: Int, _ targetEnd: Int) throws {
            let count = min(oldEnd - oldStart, targetEnd - targetStart)
            for offset in 0..<count {
                if try !updateMatching(oldStart + offset, targetStart + offset) {
                    try y.removeChildren(start: UInt32(base + targetStart + offset), length: 1, in: tx)
                    try create(pChildren[targetStart + offset], in: y, at: base + targetStart + offset, tx)
                }
            }
            let deleted = oldEnd - oldStart - count
            if deleted > 0 { try y.removeChildren(start: UInt32(base + targetStart + count), length: UInt32(deleted), in: tx) }
            for index in (targetStart + count)..<targetEnd { try create(pChildren[index], in: y, at: base + index, tx) }
        }
        var oldIndex = 0, targetIndex = 0
        for anchor in anchors {
            try reconcileGap(oldIndex, anchor.y, targetIndex, anchor.p)
            _ = try updateMatching(anchor.y, anchor.p)
            oldIndex = anchor.y + 1; targetIndex = anchor.p + 1
        }
        try reconcileGap(oldIndex, yChildren.count, targetIndex, pChildren.count)
        return true
    }

    private func matchNodeName(_ y: YXmlNode, _ p: Child, in tx: YrsTransaction) -> Bool {
        guard case .node(let node) = p, y.kind(in: tx) == "element" else { return false }
        return y.tag(in: tx) == node.type.name
    }

    private func equalityFactor(_ y: YXmlNode, _ p: Child, source: PMNode?, in tx: YrsTransaction) throws
        -> (factor: Int, found: Bool) {
        guard case .node(let node) = p else { return (0, false) }
        let yChildren = y.children(in: tx), pChildren = Self.normalize(node)
        let yCount = yChildren.count, pCount = pChildren.count, minCount = min(yCount, pCount)
        let mapping = mapped(source, count: yCount)
        var left = 0, right = 0, found = false
        while left < minCount {
            if Self.mappedIdentity(mapping?[left], pChildren[left]) { found = true }
            else if !(try equal(yChildren[left], pChildren[left], in: tx)) { break }
            left += 1
        }
        while left + right < minCount {
            let yIndex = yCount - right - 1
            if Self.mappedIdentity(mapping?[yIndex], pChildren[pCount - right - 1]) { found = true }
            else if !(try equal(yChildren[yIndex], pChildren[pCount - right - 1], in: tx)) { break }
            right += 1
        }
        return (left + right, found)
    }

    private func equal(_ y: YXmlNode, _ p: Child, in tx: YrsTransaction) throws -> Bool {
        switch p {
        case .node(let node):
            guard y.kind(in: tx) == "element", y.tag(in: tx) == node.type.name else { return false }
            let normalized = Self.normalize(node), children = y.children(in: tx)
            guard children.count == normalized.count,
                  pmCompareDeep(try Self.physicalAttributes(nodeName: node.type.name, logical: node.attrs),
                                try y.attributes(in: tx)) else { return false }
            for (child, expected) in zip(children, normalized) where !(try equal(child, expected, in: tx)) { return false }
            return true
        case .text(let texts):
            guard y.kind(in: tx) == "text" else { return false }
            return try equalText(y, texts, in: tx)
        }
    }

    private func equalText(_ y: YXmlNode, _ texts: [PMNode], in tx: YrsTransaction) throws -> Bool {
        let delta = try y.delta(in: tx)
        guard delta.count == texts.count else { return false }
        for (run, text) in zip(delta, texts) {
            guard Array(run.text.utf16) == text.text!, run.attributes.count == text.marks.count else { return false }
            for (name, value) in run.attributes {
                guard let mark = text.marks.first(where: { $0.type.name == name }),
                      Self.equalAttrs(value, mark.attrs) else { return false }
            }
        }
        return true
    }

    private func textPlan(_ y: YXmlNode, sourceParent: PMNode?, sourceGroup: Int,
                          targetParent: PMNode, targetGroup: Int, in tx: YrsTransaction) throws -> [[String: Any]] {
        let delta = try y.delta(in: tx)
        guard let prepared=causalWrite,let sourceID=sourceParent?.attrs["relaymarkId"] as? String,
              let targetID=targetParent.attrs["relaymarkId"] as? String else {throw RelayMarkNativeDocument.Failure.unsupportedProseEdit}
        guard let sourceParent,let rawGroups=sources[ObjectIdentifier(sourceParent)],sourceGroup<rawGroups.count else {throw RelayMarkNativeDocument.Failure.unsupportedProseEdit}
        var group=0, sourceOffset=0, inText=false
        for raw in rawGroups.prefix(sourceGroup) {
            switch raw {
            case .text(let texts):inText=true;sourceOffset+=texts.reduce(0){$0+$1.textString.utf16.count}
            case .node:if inText {group+=1;inText=false};group+=1;sourceOffset=0
            }
        }
        let planned=try RelayMarkContentEditCodec.planTextWrite(prepared:prepared,sourceParent:sourceID,sourceGroup:group,targetParent:targetID,targetGroup:targetGroup,sourceOffset:sourceOffset,sourceLength:delta.reduce(0){$0+$1.text.utf16.count})
        guard let changes = try JSONSerialization.jsonObject(with: planned) as? [[String: Any]] else {
            throw RelayMarkNativeDocument.Failure.unsupportedProseEdit
        }
        return changes
    }

    private func updateText(_ y: YXmlNode, _ texts: [PMNode], sourceParent:PMNode?,sourceGroup:Int,targetParent:PMNode,targetGroup:Int,in tx: YrsTransaction) throws {
        let delta = try y.delta(in: tx)
        var cleared: [String: Any] = [:]
        for run in delta { for key in run.attributes.keys { cleared[key] = NSNull() } }
        let content = texts.map { text -> ([UInt16], [String: Any]) in
            (text.text!, cleared.merging(Self.attributes(text.marks)) { $1 })
        }
        let changes = try textPlan(y, sourceParent: sourceParent, sourceGroup: sourceGroup,
            targetParent: targetParent, targetGroup: targetGroup, in: tx)
        var cursor=0
        for change in changes {
            if let count=change["retain"] as? Int {cursor+=count}
            else if let count=change["delete"] as? Int {try y.removeText(start:UInt32(cursor),length:UInt32(count),in:tx)}
            else if let text=change["insert"] as? String {try y.insert(text,attributes:[:],at:UInt32(cursor),in:tx);cursor+=text.utf16.count}
            else {throw RelayMarkNativeDocument.Failure.unsupportedProseEdit}
        }
        var offset = 0
        for (text, attributes) in content {
            if !attributes.isEmpty {
                try y.format(at: UInt32(offset), length: UInt32(text.count), attributes: attributes, in: tx)
            }
            offset += text.count
        }
    }

    private func create(_ child: Child, in parent: YXmlNode, at index: Int, _ tx: YrsTransaction) throws {
        switch child {
        case .node(let node):
            let element = try parent.insertElement(named: node.type.name, at: UInt32(index), in: tx)
            // The maintained binding integrates child types/text first, then
            // authored attrs. This order determines the exact CRDT item clocks.
            for (offset, grandchild) in Self.normalize(node).enumerated() {
                try create(grandchild, in: element, at: offset, tx)
            }
            let physical = try Self.physicalAttributes(nodeName: node.type.name, logical: node.attrs)
            for (key, value) in try Self.orderedPhysicalAttributes(nodeName: node.type.name, values: physical) {
                try element.setAttribute(key, value: value, in: tx)
            }
        case .text(let texts):
            let leaf = try parent.insertText(at: UInt32(index), in: tx)
            var offset: UInt32 = 0
            for text in texts {
                try leaf.insert(text.textString, attributes: Self.attributes(text.marks), at: offset, in: tx)
                offset += UInt32(text.text!.count)
            }
        }
    }

    // MARK: JavaScript equality

    /// `a === b` for JSON values: objects and arrays compare by reference, so never equal here.
    private static func strictEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case let (a as String, b as String): return a == b
        case let (a as NSNumber, b as NSNumber):
            let aBool = CFGetTypeID(a) == CFBooleanGetTypeID(), bBool = CFGetTypeID(b) == CFBooleanGetTypeID()
            return aBool == bBool && a.isEqual(to: b)
        default: return false
        }
    }

    private static func object(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] { return dictionary }
        if let array = value as? [Any] {
            return Dictionary(uniqueKeysWithValues: array.enumerated().map { (String($0.offset), $0.element) })
        }
        return nil
    }

    /// y-prosemirror equalAttrs: null-valued keys are ignored, objects compare recursively.
    private static func equalAttrs(_ p: Any?, _ y: Any?) -> Bool {
        let pattrs = object(p) ?? [:], yattrs = object(y) ?? [:]
        let keys = pattrs.keys.filter { !(pattrs[$0] is NSNull) }
        guard keys.count == yattrs.keys.filter({ !(yattrs[$0] is NSNull) }).count else { return false }
        return keys.allSatisfy { key in
            let l = pattrs[key], r = yattrs[key]
            return key == "ychange" || strictEqual(l, r) || (object(l) != nil && object(r) != nil && equalAttrs(l, r))
        }
    }
}

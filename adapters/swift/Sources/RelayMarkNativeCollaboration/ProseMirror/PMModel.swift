import Foundation

// A port of the prosemirror-model 1.x pieces that prosemirror-transform's
// replace algorithm depends on: schema compilation, content expressions,
// nodes, fragments, marks, slices, resolved positions and Node.replace.
// Names and control flow follow the JavaScript source so behavior can be
// checked against it line by line. Text is stored as UTF-16 code units, as
// in JavaScript, so positions match ProseMirror's exactly.

struct PMReplaceError: Error { let message: String }

/// Deep JSON value equality, as prosemirror-model's compareDeep.
func pmCompareDeep(_ a: Any?, _ b: Any?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case (is NSNull, is NSNull): return true
    case let (a as [String: Any], b as [String: Any]):
        guard a.count == b.count else { return false }
        return a.allSatisfy { key, value in b.keys.contains(key) && pmCompareDeep(value, b[key]) }
    case let (a as [Any], b as [Any]):
        return a.count == b.count && zip(a, b).allSatisfy { pmCompareDeep($0, $1) }
    case let (a as String, b as String): return a == b
    case let (a as NSNumber, b as NSNumber):
        let aBool = CFGetTypeID(a) == CFBooleanGetTypeID(), bBool = CFGetTypeID(b) == CFBooleanGetTypeID()
        return aBool == bBool && a.isEqual(to: b)
    default: return false
    }
}

final class PMSchema {
    let nodeOrder: [PMNodeType]
    let nodes: [String: PMNodeType]
    let markOrder: [PMMarkType]
    let marks: [String: PMMarkType]
    let topNodeType: PMNodeType
    let text: PMNodeType

    /// Builds a schema from the exported TipTap schema: node and mark specs in
    /// schema order, with mark sets and exclusions already resolved.
    init(json: [String: Any]) throws {
        guard let rawNodes = json["nodes"] as? [[String: Any]], let rawMarks = json["marks"] as? [[String: Any]],
              let top = json["top"] as? String else { throw PMReplaceError(message: "invalid schema") }
        let markOrder = try rawMarks.enumerated().map { rank, raw -> PMMarkType in
            guard let name = raw["name"] as? String else { throw PMReplaceError(message: "invalid mark") }
            return PMMarkType(name: name, rank: rank, inclusive: raw["inclusive"] as? Bool,
                              attrs: PMAttribute.list(raw["attrs"]))
        }
        let marks = Dictionary(uniqueKeysWithValues: markOrder.map { ($0.name, $0) })
        for (type, raw) in zip(markOrder, rawMarks) {
            type.excluded = (raw["excludes"] as? [String] ?? [type.name]).compactMap { marks[$0] }
        }
        let nodeOrder = try rawNodes.map { raw -> PMNodeType in
            guard let name = raw["name"] as? String else { throw PMReplaceError(message: "invalid node") }
            return PMNodeType(name: name, spec: raw)
        }
        let nodes = Dictionary(uniqueKeysWithValues: nodeOrder.map { ($0.name, $0) })
        var cache: [String: PMContentMatch] = [:]
        for type in nodeOrder {
            let expression = type.spec["content"] as? String ?? ""
            let match = try cache[expression] ?? PMContentMatch.parse(expression, nodeTypes: nodeOrder)
            cache[expression] = match
            type.contentMatch = match
            type.inlineContent = match.inlineContent
        }
        for (type, raw) in zip(nodeOrder, rawNodes) {
            type.markSet = (raw["markSet"] as? [String]).map { $0.compactMap { marks[$0] } }
        }
        guard let topNodeType = nodes[top], let text = nodes["text"] else {
            throw PMReplaceError(message: "schema lacks doc or text")
        }
        self.nodeOrder = nodeOrder
        self.nodes = nodes
        self.markOrder = markOrder
        self.marks = marks
        self.topNodeType = topNodeType
        self.text = text
    }

    func text(_ units: [UInt16], marks: [PMMark] = []) -> PMNode {
        PMNode(type: text, attrs: [:], content: .empty, marks: PMMark.setFrom(marks), text: units)
    }
}

struct PMAttribute {
    let name: String
    let hasDefault: Bool
    let defaultValue: Any

    static func list(_ raw: Any?) -> [PMAttribute] {
        guard let raw = raw as? [String: Any] else { return [] }
        return raw.keys.sorted().map { name in
            let spec = raw[name] as? [String: Any] ?? [:]
            return PMAttribute(name: name, hasDefault: spec.keys.contains("default"),
                               defaultValue: spec["default"] ?? NSNull())
        }
    }
}

final class PMNodeType {
    let name: String
    let spec: [String: Any]
    let groups: [String]
    let attrs: [PMAttribute]
    let isBlock: Bool
    let isText: Bool
    var contentMatch: PMContentMatch!
    var inlineContent = false
    var markSet: [PMMarkType]?

    init(name: String, spec: [String: Any]) {
        self.name = name
        self.spec = spec
        groups = (spec["group"] as? String)?.split(separator: " ").map(String.init) ?? []
        attrs = PMAttribute.list(spec["attrs"])
        isBlock = !((spec["inline"] as? Bool ?? false) || name == "text")
        isText = name == "text"
    }

    func flag(_ key: String) -> Bool { spec[key] as? Bool ?? false }
    var isInline: Bool { !isBlock }
    var isTextblock: Bool { isBlock && inlineContent }
    var isLeaf: Bool { contentMatch === PMContentMatch.empty }
    var isAtom: Bool { isLeaf || flag("atom") }
    func isInGroup(_ group: String) -> Bool { groups.contains(group) }
    func hasRequiredAttrs() -> Bool { attrs.contains { !$0.hasDefault } }

    func compatibleContent(_ other: PMNodeType) -> Bool {
        self === other || contentMatch.compatible(other.contentMatch)
    }

    func computeAttrs(_ given: [String: Any]?) throws -> [String: Any] {
        var built: [String: Any] = [:]
        for attr in attrs {
            if let value = given?[attr.name] { built[attr.name] = value }
            else if attr.hasDefault { built[attr.name] = attr.defaultValue }
            else { throw PMReplaceError(message: "No value supplied for attribute \(attr.name)") }
        }
        return built
    }

    func create(_ attrs: [String: Any]? = nil, _ content: PMFragment = .empty, marks: [PMMark] = []) throws -> PMNode {
        PMNode(type: self, attrs: try computeAttrs(attrs), content: content, marks: PMMark.setFrom(marks))
    }

    func createAndFill(_ attrs: [String: Any]? = nil, _ content: PMFragment = .empty, marks: [PMMark] = []) -> PMNode? {
        guard let attrs = try? computeAttrs(attrs) else { return nil }
        var content = content
        if content.size > 0 {
            guard let before = contentMatch.fillBefore(content) else { return nil }
            content = before.append(content)
        }
        guard let matched = contentMatch.matchFragment(content),
              let after = matched.fillBefore(.empty, toEnd: true) else { return nil }
        return PMNode(type: self, attrs: attrs, content: content.append(after), marks: PMMark.setFrom(marks))
    }

    func validContent(_ content: PMFragment) -> Bool {
        guard let result = contentMatch.matchFragment(content), result.validEnd else { return false }
        return content.children.allSatisfy { allowsMarks($0.marks) }
    }

    func allowsMarkType(_ type: PMMarkType) -> Bool { markSet == nil || markSet!.contains { $0 === type } }
    func allowsMarks(_ marks: [PMMark]) -> Bool { markSet == nil || marks.allSatisfy { allowsMarkType($0.type) } }
    func allowedMarks(_ marks: [PMMark]) -> [PMMark] {
        guard markSet != nil, !allowsMarks(marks) else { return marks }
        return marks.filter { allowsMarkType($0.type) }
    }
}

final class PMMarkType {
    let name: String
    let rank: Int
    let inclusive: Bool?
    let attrs: [PMAttribute]
    var excluded: [PMMarkType] = []

    init(name: String, rank: Int, inclusive: Bool?, attrs: [PMAttribute]) {
        self.name = name
        self.rank = rank
        self.inclusive = inclusive
        self.attrs = attrs
    }

    func excludes(_ other: PMMarkType) -> Bool { excluded.contains { $0 === other } }

    func create(_ given: [String: Any]?) -> PMMark {
        var built: [String: Any] = [:]
        for attr in attrs { built[attr.name] = given?[attr.name] ?? (attr.hasDefault ? attr.defaultValue : NSNull()) }
        return PMMark(type: self, attrs: built)
    }
}

struct PMMark {
    let type: PMMarkType
    let attrs: [String: Any]

    func eq(_ other: PMMark) -> Bool { type === other.type && pmCompareDeep(attrs, other.attrs) }
    func isInSet(_ set: [PMMark]) -> Bool { set.contains { eq($0) } }

    func addToSet(_ set: [PMMark]) -> [PMMark] {
        var copy: [PMMark]?, placed = false
        for (index, other) in set.enumerated() {
            if eq(other) { return set }
            if type.excludes(other.type) {
                if copy == nil { copy = Array(set[..<index]) }
            } else if other.type.excludes(type) {
                return set
            } else {
                if !placed, other.type.rank > type.rank {
                    if copy == nil { copy = Array(set[..<index]) }
                    copy!.append(self)
                    placed = true
                }
                copy?.append(other)
            }
        }
        var result = copy ?? set
        if !placed { result.append(self) }
        return result
    }

    func removeFromSet(_ set: [PMMark]) -> [PMMark] {
        guard let index = set.firstIndex(where: { eq($0) }) else { return set }
        return Array(set[..<index] + set[(index + 1)...])
    }

    static func sameSet(_ a: [PMMark], _ b: [PMMark]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.eq($1) }
    }

    static func setFrom(_ marks: [PMMark]) -> [PMMark] { marks.sorted { $0.type.rank < $1.type.rank } }
}

final class PMFragment {
    let children: [PMNode]
    let size: Int

    nonisolated(unsafe) static let empty = PMFragment([], size: 0)

    init(_ children: [PMNode], size: Int? = nil) {
        self.children = children
        self.size = size ?? children.reduce(0) { $0 + $1.nodeSize }
    }

    var childCount: Int { children.count }
    var firstChild: PMNode? { children.first }
    var lastChild: PMNode? { children.last }
    func child(_ index: Int) -> PMNode { children[index] }
    func maybeChild(_ index: Int) -> PMNode? { children.indices.contains(index) ? children[index] : nil }

    static func from(_ node: PMNode?) -> PMFragment { node.map { PMFragment([$0]) } ?? .empty }

    /// Joins adjacent text nodes with the same marks, as Fragment.fromArray.
    static func fromArray(_ nodes: [PMNode]) -> PMFragment {
        guard !nodes.isEmpty else { return .empty }
        var joined: [PMNode] = []
        for node in nodes {
            if let last = joined.last, node.isText, last.sameMarkup(node) {
                joined[joined.count - 1] = last.withText(last.text! + node.text!)
            } else {
                joined.append(node)
            }
        }
        return PMFragment(joined)
    }

    func append(_ other: PMFragment) -> PMFragment {
        if other.size == 0 { return self }
        if size == 0 { return other }
        var content = children, index = 0
        if let last = lastChild, let first = other.firstChild, last.isText, last.sameMarkup(first) {
            content[content.count - 1] = last.withText(last.text! + first.text!)
            index = 1
        }
        content.append(contentsOf: other.children[index...])
        return PMFragment(content, size: size + other.size)
    }

    func cut(_ from: Int, _ to: Int? = nil) -> PMFragment {
        let to = to ?? size
        if from == 0 && to == size { return self }
        var result: [PMNode] = [], resultSize = 0
        if to > from {
            var pos = 0, index = 0
            while pos < to {
                var child = children[index]
                let end = pos + child.nodeSize
                if end > from {
                    if pos < from || end > to {
                        if child.isText {
                            child = child.cut(max(0, from - pos), min(child.text!.count, to - pos))
                        } else {
                            child = child.cut(max(0, from - pos - 1), min(child.content.size, to - pos - 1))
                        }
                    }
                    result.append(child)
                    resultSize += child.nodeSize
                }
                pos = end
                index += 1
            }
        }
        return PMFragment(result, size: resultSize)
    }

    func cutByIndex(_ from: Int, _ to: Int) -> PMFragment {
        if from == to { return .empty }
        if from == 0 && to == children.count { return self }
        return PMFragment(Array(children[from..<to]))
    }

    func replaceChild(_ index: Int, _ node: PMNode) -> PMFragment {
        let current = children[index]
        if current === node { return self }
        var copy = children
        copy[index] = node
        return PMFragment(copy, size: size + node.nodeSize - current.nodeSize)
    }

    func addToStart(_ node: PMNode) -> PMFragment { PMFragment([node] + children, size: size + node.nodeSize) }
    func addToEnd(_ node: PMNode) -> PMFragment { PMFragment(children + [node], size: size + node.nodeSize) }

    func eq(_ other: PMFragment) -> Bool {
        children.count == other.children.count && zip(children, other.children).allSatisfy { $0.eq($1) }
    }

    func findIndex(_ pos: Int) throws -> (index: Int, offset: Int) {
        if pos == 0 { return (0, pos) }
        if pos == size { return (children.count, pos) }
        guard pos > 0, pos < size else { throw PMReplaceError(message: "Position \(pos) outside of fragment") }
        var current = 0
        for (index, child) in children.enumerated() {
            let end = current + child.nodeSize
            if end >= pos { return end == pos ? (index + 1, end) : (index, current) }
            current = end
        }
        throw PMReplaceError(message: "Position \(pos) outside of fragment")
    }

    func nodesBetween(_ from: Int, _ to: Int, _ body: (PMNode, Int, PMNode?, Int) -> Bool,
                      nodeStart: Int = 0, parent: PMNode? = nil) {
        var pos = 0, index = 0
        while pos < to, index < children.count {
            let child = children[index], end = pos + child.nodeSize
            if end > from, body(child, nodeStart + pos, parent, index), child.content.size > 0 {
                let start = pos + 1
                child.content.nodesBetween(max(0, from - start), min(child.content.size, to - start), body,
                                           nodeStart: nodeStart + start, parent: child)
            }
            pos = end
            index += 1
        }
    }
}

final class PMNode {
    let type: PMNodeType
    let attrs: [String: Any]
    let content: PMFragment
    let marks: [PMMark]
    /// UTF-16 code units for text nodes, matching JavaScript string indexes.
    let text: [UInt16]?

    init(type: PMNodeType, attrs: [String: Any], content: PMFragment, marks: [PMMark], text: [UInt16]? = nil) {
        self.type = type
        self.attrs = attrs
        self.content = content
        self.marks = marks
        self.text = text
    }

    var isText: Bool { type.isText }
    var isBlock: Bool { type.isBlock }
    var isInline: Bool { type.isInline }
    var isTextblock: Bool { type.isTextblock }
    var inlineContent: Bool { type.inlineContent }
    var isLeaf: Bool { type.isLeaf }
    var isAtom: Bool { type.isAtom }
    var nodeSize: Int { text?.count ?? (isLeaf ? 1 : 2 + content.size) }
    var childCount: Int { content.childCount }
    var firstChild: PMNode? { content.firstChild }
    var lastChild: PMNode? { content.lastChild }
    func child(_ index: Int) -> PMNode { content.child(index) }
    func maybeChild(_ index: Int) -> PMNode? { content.maybeChild(index) }
    var textString: String { text.map { String(decoding: $0, as: UTF16.self) } ?? "" }

    func eq(_ other: PMNode) -> Bool {
        if self === other { return true }
        guard sameMarkup(other) else { return false }
        return isText ? text == other.text : content.eq(other.content)
    }

    func sameMarkup(_ other: PMNode) -> Bool { hasMarkup(other.type, other.attrs, other.marks) }

    func hasMarkup(_ type: PMNodeType, _ attrs: [String: Any], _ marks: [PMMark]) -> Bool {
        self.type === type && pmCompareDeep(self.attrs, attrs) && PMMark.sameSet(self.marks, marks)
    }

    func copy(_ content: PMFragment? = nil) -> PMNode {
        let content = content ?? .empty
        if content === self.content { return self }
        return PMNode(type: type, attrs: attrs, content: content, marks: marks)
    }

    func mark(_ marks: [PMMark]) -> PMNode {
        if PMMark.sameSet(marks, self.marks) { return self }
        return PMNode(type: type, attrs: attrs, content: content, marks: marks, text: text)
    }

    func withText(_ units: [UInt16]) -> PMNode {
        if units == text { return self }
        return PMNode(type: type, attrs: attrs, content: content, marks: marks, text: units)
    }

    func cut(_ from: Int, _ to: Int? = nil) -> PMNode {
        if let text {
            let to = to ?? text.count
            if from == 0 && to == text.count { return self }
            return withText(Array(text[from..<to]))
        }
        let to = to ?? content.size
        if from == 0 && to == content.size { return self }
        return copy(content.cut(from, to))
    }

    func slice(_ from: Int, _ to: Int? = nil, includeParents: Bool = false) throws -> PMSlice {
        let to = to ?? content.size
        if from == to { return .empty }
        let from$ = try resolve(from), to$ = try resolve(to)
        let depth = includeParents ? 0 : from$.sharedDepth(to)
        let start = from$.start(depth), node = from$.node(depth)
        let content = node.content.cut(from$.pos - start, to$.pos - start)
        return PMSlice(content, openStart: from$.depth - depth, openEnd: to$.depth - depth)
    }

    func replace(_ from: Int, _ to: Int, _ slice: PMSlice) throws -> PMNode {
        try pmReplace(resolve(from), resolve(to), slice)
    }

    func nodeAt(_ pos: Int) -> PMNode? {
        var node = self, pos = pos
        while true {
            guard let (index, offset) = try? node.content.findIndex(pos), let child = node.maybeChild(index) else {
                return nil
            }
            if offset == pos || child.isText { return child }
            node = child
            pos -= offset + 1
        }
    }

    func resolve(_ pos: Int) throws -> PMResolvedPos { try PMResolvedPos.resolve(self, pos) }

    func contentMatchAt(_ index: Int) throws -> PMContentMatch {
        guard let match = type.contentMatch.matchFragment(content, start: 0, end: index) else {
            throw PMReplaceError(message: "Called contentMatchAt on a node with invalid content")
        }
        return match
    }

    func canReplace(_ from: Int, _ to: Int, _ replacement: PMFragment = .empty,
                    start: Int = 0, end: Int? = nil) -> Bool {
        let end = end ?? replacement.childCount
        guard let one = (try? contentMatchAt(from))?.matchFragment(replacement, start: start, end: end),
              let two = one.matchFragment(content, start: to), two.validEnd else { return false }
        return (start..<end).allSatisfy { type.allowsMarks(replacement.child($0).marks) }
    }

    func canReplaceWith(_ from: Int, _ to: Int, _ nodeType: PMNodeType, marks: [PMMark]? = nil) -> Bool {
        if let marks, !type.allowsMarks(marks) { return false }
        guard let start = (try? contentMatchAt(from))?.matchType(nodeType),
              let end = start.matchFragment(content, start: to) else { return false }
        return end.validEnd
    }
}

struct PMSlice {
    let content: PMFragment
    let openStart: Int
    let openEnd: Int

    nonisolated(unsafe) static let empty = PMSlice(.empty, openStart: 0, openEnd: 0)

    init(_ content: PMFragment, openStart: Int, openEnd: Int) {
        self.content = content
        self.openStart = openStart
        self.openEnd = openEnd
    }

    var size: Int { content.size - openStart - openEnd }

    func insertAt(_ pos: Int, _ fragment: PMFragment) throws -> PMSlice? {
        try pmInsertInto(content, pos + openStart, fragment, openStart + 1, openEnd + 1, nil)
            .map { PMSlice($0, openStart: openStart, openEnd: openEnd) }
    }

    static func maxOpen(_ fragment: PMFragment, openIsolating: Bool = true) -> PMSlice {
        var openStart = 0, openEnd = 0
        var node = fragment.firstChild
        while let current = node, !current.isLeaf, openIsolating || !current.type.flag("isolating") {
            openStart += 1
            node = current.firstChild
        }
        node = fragment.lastChild
        while let current = node, !current.isLeaf, openIsolating || !current.type.flag("isolating") {
            openEnd += 1
            node = current.lastChild
        }
        return PMSlice(fragment, openStart: openStart, openEnd: openEnd)
    }
}

struct PMResolvedPos {
    let pos: Int
    let path: [(node: PMNode, index: Int, offset: Int)]
    let parentOffset: Int
    var depth: Int { path.count - 1 }

    private func resolveDepth(_ value: Int?) -> Int {
        guard let value else { return depth }
        return value < 0 ? depth + value : value
    }

    var parent: PMNode { node(depth) }
    var doc: PMNode { node(0) }
    func node(_ depth: Int? = nil) -> PMNode { path[resolveDepth(depth)].node }
    func index(_ depth: Int? = nil) -> Int { path[resolveDepth(depth)].index }

    func indexAfter(_ depth: Int? = nil) -> Int {
        let depth = resolveDepth(depth)
        return index(depth) + (depth == self.depth && textOffset == 0 ? 0 : 1)
    }

    func start(_ depth: Int? = nil) -> Int {
        let depth = resolveDepth(depth)
        return depth == 0 ? 0 : path[depth - 1].offset + 1
    }

    func end(_ depth: Int? = nil) -> Int {
        let depth = resolveDepth(depth)
        return start(depth) + node(depth).content.size
    }

    func before(_ depth: Int? = nil) -> Int {
        let depth = resolveDepth(depth)
        precondition(depth > 0, "There is no position before the top-level node")
        return depth == self.depth + 1 ? pos : path[depth - 1].offset
    }

    func after(_ depth: Int? = nil) -> Int {
        let depth = resolveDepth(depth)
        precondition(depth > 0, "There is no position after the top-level node")
        return depth == self.depth + 1 ? pos : path[depth - 1].offset + path[depth].node.nodeSize
    }

    var textOffset: Int { pos - path[path.count - 1].offset }

    var nodeAfter: PMNode? {
        let parent = self.parent, index = self.index(depth)
        if index == parent.childCount { return nil }
        let offset = pos - path[path.count - 1].offset, child = parent.child(index)
        return offset > 0 ? child.cut(offset) : child
    }

    var nodeBefore: PMNode? {
        let index = self.index(depth), offset = pos - path[path.count - 1].offset
        if offset > 0 { return parent.child(index).cut(0, offset) }
        return index == 0 ? nil : parent.child(index - 1)
    }

    func posAtIndex(_ index: Int, _ depth: Int? = nil) -> Int {
        let depth = resolveDepth(depth)
        let node = path[depth].node
        var pos = depth == 0 ? 0 : path[depth - 1].offset + 1
        for i in 0..<index { pos += node.child(i).nodeSize }
        return pos
    }

    func marks() -> [PMMark] {
        let parent = self.parent, index = self.index()
        if parent.content.size == 0 { return [] }
        if textOffset > 0 { return parent.child(index).marks }
        var main = parent.maybeChild(index - 1), other = parent.maybeChild(index)
        if main == nil { swap(&main, &other) }
        guard let main else { return [] }
        var marks = main.marks, i = 0
        while i < marks.count {
            if marks[i].type.inclusive == false, !(other.map { marks[i].isInSet($0.marks) } ?? false) {
                marks = marks[i].removeFromSet(marks)
            } else {
                i += 1
            }
        }
        return marks
    }

    func marksAcross(_ end: PMResolvedPos) -> [PMMark]? {
        guard let after = parent.maybeChild(index()), after.isInline else { return nil }
        var marks = after.marks, i = 0
        let next = end.parent.maybeChild(end.index())
        while i < marks.count {
            if marks[i].type.inclusive == false, !(next.map { marks[i].isInSet($0.marks) } ?? false) {
                marks = marks[i].removeFromSet(marks)
            } else {
                i += 1
            }
        }
        return marks
    }

    func sharedDepth(_ pos: Int) -> Int {
        var depth = self.depth
        while depth > 0 {
            if start(depth) <= pos && end(depth) >= pos { return depth }
            depth -= 1
        }
        return 0
    }

    static func resolve(_ doc: PMNode, _ pos: Int) throws -> PMResolvedPos {
        guard pos >= 0, pos <= doc.content.size else { throw PMReplaceError(message: "Position \(pos) out of range") }
        var path: [(PMNode, Int, Int)] = []
        var start = 0, parentOffset = pos, node = doc
        while true {
            let (index, offset) = try node.content.findIndex(parentOffset)
            let rem = parentOffset - offset
            path.append((node, index, start + offset))
            if rem == 0 { break }
            node = node.child(index)
            if node.isText { break }
            parentOffset = rem - 1
            start += offset + 1
        }
        return PMResolvedPos(pos: pos, path: path.map { (node: $0.0, index: $0.1, offset: $0.2) },
                             parentOffset: parentOffset)
    }
}

// MARK: Node.replace (prosemirror-model replace.ts)

func pmReplace(_ from$: PMResolvedPos, _ to$: PMResolvedPos, _ slice: PMSlice) throws -> PMNode {
    guard slice.openStart <= from$.depth else {
        throw PMReplaceError(message: "Inserted content deeper than insertion position")
    }
    guard from$.depth - slice.openStart == to$.depth - slice.openEnd else {
        throw PMReplaceError(message: "Inconsistent open depths")
    }
    return try pmReplaceOuter(from$, to$, slice, 0)
}

private func pmReplaceOuter(_ from$: PMResolvedPos, _ to$: PMResolvedPos, _ slice: PMSlice, _ depth: Int) throws -> PMNode {
    let index = from$.index(depth), node = from$.node(depth)
    if index == to$.index(depth) && depth < from$.depth - slice.openStart {
        let inner = try pmReplaceOuter(from$, to$, slice, depth + 1)
        return node.copy(node.content.replaceChild(index, inner))
    } else if slice.content.size == 0 {
        return try pmClose(node, pmReplaceTwoWay(from$, to$, depth))
    } else if slice.openStart == 0 && slice.openEnd == 0 && from$.depth == depth && to$.depth == depth {
        let parent = from$.parent, content = parent.content
        return try pmClose(parent, content.cut(0, from$.parentOffset).append(slice.content)
            .append(content.cut(to$.parentOffset)))
    } else {
        let (start, end) = try pmPrepareSliceForReplace(slice, from$)
        return try pmClose(node, pmReplaceThreeWay(from$, start, end, to$, depth))
    }
}

private func pmCheckJoin(_ main: PMNode, _ sub: PMNode) throws {
    guard sub.type.compatibleContent(main.type) else {
        throw PMReplaceError(message: "Cannot join \(sub.type.name) onto \(main.type.name)")
    }
}

private func pmJoinable(_ before$: PMResolvedPos, _ after$: PMResolvedPos, _ depth: Int) throws -> PMNode {
    let node = before$.node(depth)
    try pmCheckJoin(node, after$.node(depth))
    return node
}

private func pmAddNode(_ child: PMNode, _ target: inout [PMNode]) {
    if let last = target.last, child.isText, child.sameMarkup(last) {
        target[target.count - 1] = child.withText(last.text! + child.text!)
    } else {
        target.append(child)
    }
}

private func pmAddRange(_ start$: PMResolvedPos?, _ end$: PMResolvedPos?, _ depth: Int, _ target: inout [PMNode]) {
    let node = (end$ ?? start$)!.node(depth)
    var startIndex = 0
    let endIndex = end$?.index(depth) ?? node.childCount
    if let start$ {
        startIndex = start$.index(depth)
        if start$.depth > depth {
            startIndex += 1
        } else if start$.textOffset > 0 {
            pmAddNode(start$.nodeAfter!, &target)
            startIndex += 1
        }
    }
    var i = startIndex
    while i < endIndex {
        pmAddNode(node.child(i), &target)
        i += 1
    }
    if let end$, end$.depth == depth, end$.textOffset > 0 { pmAddNode(end$.nodeBefore!, &target) }
}

private func pmClose(_ node: PMNode, _ content: PMFragment) throws -> PMNode {
    guard node.type.validContent(content) else {
        throw PMReplaceError(message: "Invalid content for node \(node.type.name)")
    }
    return node.copy(content)
}

private func pmReplaceThreeWay(_ from$: PMResolvedPos, _ start$: PMResolvedPos, _ end$: PMResolvedPos,
                               _ to$: PMResolvedPos, _ depth: Int) throws -> PMFragment {
    let openStart = from$.depth > depth ? try pmJoinable(from$, start$, depth + 1) : nil
    let openEnd = to$.depth > depth ? try pmJoinable(end$, to$, depth + 1) : nil
    var content: [PMNode] = []
    pmAddRange(nil, from$, depth, &content)
    if let openStart, let openEnd, start$.index(depth) == end$.index(depth) {
        try pmCheckJoin(openStart, openEnd)
        pmAddNode(try pmClose(openStart, pmReplaceThreeWay(from$, start$, end$, to$, depth + 1)), &content)
    } else {
        if let openStart { pmAddNode(try pmClose(openStart, pmReplaceTwoWay(from$, start$, depth + 1)), &content) }
        pmAddRange(start$, end$, depth, &content)
        if let openEnd { pmAddNode(try pmClose(openEnd, pmReplaceTwoWay(end$, to$, depth + 1)), &content) }
    }
    pmAddRange(to$, nil, depth, &content)
    return PMFragment(content)
}

private func pmReplaceTwoWay(_ from$: PMResolvedPos, _ to$: PMResolvedPos, _ depth: Int) throws -> PMFragment {
    var content: [PMNode] = []
    pmAddRange(nil, from$, depth, &content)
    if from$.depth > depth {
        let type = try pmJoinable(from$, to$, depth + 1)
        pmAddNode(try pmClose(type, pmReplaceTwoWay(from$, to$, depth + 1)), &content)
    }
    pmAddRange(to$, nil, depth, &content)
    return PMFragment(content)
}

private func pmPrepareSliceForReplace(_ slice: PMSlice, _ along$: PMResolvedPos) throws
    -> (PMResolvedPos, PMResolvedPos) {
    let extra = along$.depth - slice.openStart, parent = along$.node(extra)
    var node = parent.copy(slice.content)
    var i = extra - 1
    while i >= 0 {
        node = along$.node(i).copy(PMFragment.from(node))
        i -= 1
    }
    return (try PMResolvedPos.resolve(node, slice.openStart + extra),
            try PMResolvedPos.resolve(node, node.content.size - slice.openEnd - extra))
}

func pmInsertInto(_ content: PMFragment, _ dist: Int, _ insert: PMFragment, _ openStart: Int, _ openEnd: Int,
                  _ parent: PMNode?) throws -> PMFragment? {
    let (index, offset) = try content.findIndex(dist)
    let child = content.maybeChild(index)
    if offset == dist || child?.isText == true {
        if let parent, openStart <= 0, openEnd <= 0, !parent.canReplace(index, index, insert) { return nil }
        return content.cut(0, dist).append(insert).append(content.cut(dist))
    }
    guard let child else { return nil }
    let inner = try pmInsertInto(child.content, dist - offset - 1, insert,
                                 index == 0 ? openStart - 1 : 0,
                                 index == content.childCount - 1 ? openEnd - 1 : 0, child)
    return inner.map { content.replaceChild(index, child.copy($0)) }
}

// MARK: ContentMatch (prosemirror-model content.ts)

final class PMContentMatch {
    let validEnd: Bool
    var next: [(type: PMNodeType, next: PMContentMatch)] = []
    private var wrapCache: [(PMNodeType, [PMNodeType]?)] = []

    nonisolated(unsafe) static let empty = PMContentMatch(validEnd: true)

    init(validEnd: Bool) { self.validEnd = validEnd }

    static func parse(_ string: String, nodeTypes: [PMNodeType]) throws -> PMContentMatch {
        var stream = PMTokenStream(string, nodeTypes: nodeTypes)
        if stream.next == nil { return .empty }
        let expression = try stream.parseExpr()
        if stream.next != nil { throw stream.error("Unexpected trailing text") }
        return PMContentMatch.dfa(PMContentMatch.nfa(expression))
    }

    func matchType(_ type: PMNodeType) -> PMContentMatch? {
        next.first { $0.type === type }?.next
    }

    func matchFragment(_ fragment: PMFragment, start: Int = 0, end: Int? = nil) -> PMContentMatch? {
        var current: PMContentMatch? = self
        var i = start
        let end = end ?? fragment.childCount
        while let match = current, i < end {
            current = match.matchType(fragment.child(i).type)
            i += 1
        }
        return current
    }

    var inlineContent: Bool { !next.isEmpty && next[0].type.isInline }

    var defaultType: PMNodeType? {
        next.first { !($0.type.isText || $0.type.hasRequiredAttrs()) }?.type
    }

    func compatible(_ other: PMContentMatch) -> Bool {
        next.contains { edge in other.next.contains { $0.type === edge.type } }
    }

    func fillBefore(_ after: PMFragment, toEnd: Bool = false, startIndex: Int = 0) -> PMFragment? {
        var seen: [PMContentMatch] = [self]
        func search(_ match: PMContentMatch, _ types: [PMNodeType]) -> PMFragment? {
            if let finished = match.matchFragment(after, start: startIndex), !toEnd || finished.validEnd {
                let nodes = types.compactMap { $0.createAndFill() }
                return nodes.count == types.count ? PMFragment.fromArray(nodes) : nil
            }
            for (type, next) in match.next where !(type.isText || type.hasRequiredAttrs()) && !seen.contains(where: { $0 === next }) {
                seen.append(next)
                if let found = search(next, types + [type]) { return found }
            }
            return nil
        }
        return search(self, [])
    }

    func findWrapping(_ target: PMNodeType) -> [PMNodeType]? {
        if let cached = wrapCache.first(where: { $0.0 === target }) { return cached.1 }
        let computed = computeWrapping(target)
        wrapCache.append((target, computed))
        return computed
    }

    private final class WrapStep {
        let match: PMContentMatch, type: PMNodeType?, via: WrapStep?
        init(_ match: PMContentMatch, _ type: PMNodeType?, _ via: WrapStep?) {
            self.match = match; self.type = type; self.via = via
        }
    }

    private func computeWrapping(_ target: PMNodeType) -> [PMNodeType]? {
        var seen = Set<String>()
        var active = [WrapStep(self, nil, nil)]
        while !active.isEmpty {
            let current = active.removeFirst(), match = current.match
            if match.matchType(target) != nil {
                var result: [PMNodeType] = []
                var step: WrapStep? = current
                while let node = step, let type = node.type { result.append(type); step = node.via }
                return result.reversed()
            }
            for (type, next) in match.next where !type.isLeaf && !type.hasRequiredAttrs() && !seen.contains(type.name)
                && (current.type == nil || next.validEnd) {
                active.append(WrapStep(type.contentMatch, type, current))
                seen.insert(type.name)
            }
        }
        return nil
    }

    // MARK: expression compilation

    indirect enum Expr {
        case choice([Expr]), seq([Expr]), plus(Expr), star(Expr), opt(Expr)
        case range(min: Int, max: Int, Expr), name(PMNodeType)
    }

    private final class Edge {
        let term: PMNodeType?
        var to: Int?
        init(_ term: PMNodeType?, _ to: Int?) { self.term = term; self.to = to }
    }

    private static func nfa(_ expr: Expr) -> [[Edge]] {
        var nfa: [[Edge]] = [[]]
        func node() -> Int { nfa.append([]); return nfa.count - 1 }
        @discardableResult func edge(_ from: Int, _ to: Int? = nil, _ term: PMNodeType? = nil) -> Edge {
            let edge = Edge(term, to)
            nfa[from].append(edge)
            return edge
        }
        func connect(_ edges: [Edge], _ to: Int) { edges.forEach { $0.to = to } }
        func compile(_ expr: Expr, _ from: Int) -> [Edge] {
            switch expr {
            case .choice(let exprs):
                return exprs.reduce([]) { $0 + compile($1, from) }
            case .seq(let exprs):
                var from = from, i = 0
                while true {
                    let next = compile(exprs[i], from)
                    if i == exprs.count - 1 { return next }
                    from = node()
                    connect(next, from)
                    i += 1
                }
            case .star(let inner):
                let loop = node()
                edge(from, loop)
                connect(compile(inner, loop), loop)
                return [edge(loop)]
            case .plus(let inner):
                let loop = node()
                connect(compile(inner, from), loop)
                connect(compile(inner, loop), loop)
                return [edge(loop)]
            case .opt(let inner):
                return [edge(from)] + compile(inner, from)
            case .range(let min, let max, let inner):
                var current = from
                for _ in 0..<min {
                    let next = node()
                    connect(compile(inner, current), next)
                    current = next
                }
                if max == -1 {
                    connect(compile(inner, current), current)
                } else if max > min {
                    for _ in min..<max {
                        let next = node()
                        edge(current, next)
                        connect(compile(inner, current), next)
                        current = next
                    }
                }
                return [edge(current)]
            case .name(let type):
                return [edge(from, nil, type)]
            }
        }
        connect(compile(expr, 0), node())
        return nfa
    }

    private static func nullFrom(_ nfa: [[Edge]], _ node: Int) -> [Int] {
        var result: [Int] = []
        func scan(_ node: Int) {
            let edges = nfa[node]
            if edges.count == 1, edges[0].term == nil, let to = edges[0].to { return scan(to) }
            result.append(node)
            for edge in edges where edge.term == nil {
                if let to = edge.to, !result.contains(to) { scan(to) }
            }
        }
        scan(node)
        return result.sorted(by: >)
    }

    private static func dfa(_ nfa: [[Edge]]) -> PMContentMatch {
        var labeled: [String: PMContentMatch] = [:]
        func explore(_ states: [Int]) -> PMContentMatch {
            var out: [(PMNodeType, [Int])] = []
            for node in states {
                for edge in nfa[node] {
                    guard let term = edge.term, let to = edge.to else { continue }
                    var setIndex = out.firstIndex { $0.0 === term }
                    for reachable in nullFrom(nfa, to) {
                        if setIndex == nil { out.append((term, [])); setIndex = out.count - 1 }
                        if !out[setIndex!].1.contains(reachable) { out[setIndex!].1.append(reachable) }
                    }
                }
            }
            let state = PMContentMatch(validEnd: states.contains(nfa.count - 1))
            labeled[states.map(String.init).joined(separator: ",")] = state
            for (term, rawStates) in out {
                let sorted = rawStates.sorted(by: >)
                let key = sorted.map(String.init).joined(separator: ",")
                state.next.append((term, labeled[key] ?? explore(sorted)))
            }
            return state
        }
        return explore(nullFrom(nfa, 0))
    }
}

private struct PMTokenStream {
    let string: String
    let nodeTypes: [PMNodeType]
    var inline: Bool?
    var pos = 0
    let tokens: [String]

    init(_ string: String, nodeTypes: [PMNodeType]) {
        self.string = string
        self.nodeTypes = nodeTypes
        var tokens: [String] = [], word = ""
        for character in string {
            if character.isLetter || character.isNumber || character == "_" {
                word.append(character)
            } else {
                if !word.isEmpty { tokens.append(word); word = "" }
                if !character.isWhitespace { tokens.append(String(character)) }
            }
        }
        if !word.isEmpty { tokens.append(word) }
        self.tokens = tokens
    }

    var next: String? { pos < tokens.count ? tokens[pos] : nil }
    mutating func eat(_ token: String) -> Bool {
        guard next == token else { return false }
        pos += 1
        return true
    }
    func error(_ message: String) -> PMReplaceError {
        PMReplaceError(message: "\(message) (in content expression '\(string)')")
    }

    mutating func parseExpr() throws -> PMContentMatch.Expr {
        var exprs: [PMContentMatch.Expr] = []
        repeat { exprs.append(try parseExprSeq()) } while eat("|")
        return exprs.count == 1 ? exprs[0] : .choice(exprs)
    }

    mutating func parseExprSeq() throws -> PMContentMatch.Expr {
        var exprs: [PMContentMatch.Expr] = []
        repeat { exprs.append(try parseExprSubscript()) } while next != nil && next != ")" && next != "|"
        return exprs.count == 1 ? exprs[0] : .seq(exprs)
    }

    mutating func parseExprSubscript() throws -> PMContentMatch.Expr {
        var expr = try parseExprAtom()
        while true {
            if eat("+") { expr = .plus(expr) }
            else if eat("*") { expr = .star(expr) }
            else if eat("?") { expr = .opt(expr) }
            else if eat("{") { expr = try parseExprRange(expr) }
            else { break }
        }
        return expr
    }

    mutating func parseNum() throws -> Int {
        guard let token = next, let value = Int(token) else { throw error("Expected number, got '\(next ?? "")'") }
        pos += 1
        return value
    }

    mutating func parseExprRange(_ expr: PMContentMatch.Expr) throws -> PMContentMatch.Expr {
        let min = try parseNum()
        var max = min
        if eat(",") { max = next != "}" ? try parseNum() : -1 }
        guard eat("}") else { throw error("Unclosed braced range") }
        return .range(min: min, max: max, expr)
    }

    func resolveName(_ name: String) throws -> [PMNodeType] {
        if let type = nodeTypes.first(where: { $0.name == name }) { return [type] }
        let result = nodeTypes.filter { $0.isInGroup(name) }
        guard !result.isEmpty else { throw error("No node type or group '\(name)' found") }
        return result
    }

    mutating func parseExprAtom() throws -> PMContentMatch.Expr {
        if eat("(") {
            let expr = try parseExpr()
            guard eat(")") else { throw error("Missing closing paren") }
            return expr
        }
        guard let token = next, token.first.map({ $0.isLetter || $0.isNumber || $0 == "_" }) == true else {
            throw error("Unexpected token '\(next ?? "")'")
        }
        let exprs = try resolveName(token).map { type -> PMContentMatch.Expr in
            if inline == nil { inline = type.isInline }
            else if inline != type.isInline { throw error("Mixing inline and block content") }
            return .name(type)
        }
        pos += 1
        return exprs.count == 1 ? exprs[0] : .choice(exprs)
    }
}

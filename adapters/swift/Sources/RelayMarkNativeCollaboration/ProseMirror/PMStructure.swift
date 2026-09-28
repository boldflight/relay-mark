import Foundation

// prosemirror-model NodeRange/blockRange and prosemirror-transform
// structure.ts (liftTarget, lift, canJoin, join, setNodeMarkup) as used by
// prosemirror-commands and TipTap keymaps. The v3 schema declares no
// linebreakReplacement, so join's newline conversion paths are absent.

struct PMNodeRange {
    let from$: PMResolvedPos
    let to$: PMResolvedPos
    let depth: Int

    var start: Int { from$.before(depth + 1) }
    var end: Int { to$.after(depth + 1) }
    var parent: PMNode { from$.node(depth) }
    var startIndex: Int { from$.index(depth) }
    var endIndex: Int { to$.indexAfter(depth) }
}

extension PMResolvedPos {
    func blockRange(_ other: PMResolvedPos? = nil, _ predicate: ((PMNode) -> Bool)? = nil) -> PMNodeRange? {
        let other = other ?? self
        if other.pos < pos { return other.blockRange(self, predicate) }
        var d = depth - (parent.inlineContent || pos == other.pos ? 1 : 0)
        while d >= 0 {
            if other.pos <= end(d) && (predicate.map { $0(node(d)) } ?? true) {
                return PMNodeRange(from$: self, to$: other, depth: d)
            }
            d -= 1
        }
        return nil
    }

    func sameParent(_ other: PMResolvedPos) -> Bool { pos - parentOffset == other.pos - other.parentOffset }
}

func pmContentBetween(_ doc: PMNode, _ from: Int, _ to: Int) throws -> Bool {
    let from$ = try doc.resolve(from)
    var dist = to - from, depth = from$.depth
    while dist > 0 && depth > 0 && from$.indexAfter(depth) == from$.node(depth).childCount {
        depth -= 1
        dist -= 1
    }
    if dist > 0 {
        var next = from$.node(depth).maybeChild(from$.indexAfter(depth))
        while dist > 0 {
            guard let current = next, !current.isLeaf else { return true }
            next = current.firstChild
            dist -= 1
        }
    }
    return false
}

private func pmCanCut(_ node: PMNode, _ start: Int, _ end: Int) -> Bool {
    (start == 0 || node.canReplace(start, node.childCount)) && (end == node.childCount || node.canReplace(0, end))
}

func pmLiftTarget(_ range: PMNodeRange) -> Int? {
    let content = range.parent.content.cutByIndex(range.startIndex, range.endIndex)
    var depth = range.depth, contentBefore = 0, contentAfter = 0
    while true {
        let node = range.from$.node(depth)
        let index = range.from$.index(depth) + contentBefore, endIndex = range.to$.indexAfter(depth) - contentAfter
        if depth < range.depth && node.canReplace(index, endIndex, content) { return depth }
        if depth == 0 || node.type.flag("isolating") || !pmCanCut(node, index, endIndex) { break }
        if index > 0 { contentBefore = 1 }
        if endIndex < node.childCount { contentAfter = 1 }
        depth -= 1
    }
    return nil
}

/// canAppendWithSubstitutedLinebreaks without a linebreak replacement,
/// including its unreturned compatibleContent check for empty nodes.
private func pmCanAppend(_ a: PMNode, _ b: PMNode) -> Bool {
    guard var match = try? a.contentMatchAt(a.childCount) else { return false }
    for child in b.content.children {
        guard let next = match.matchType(child.type), a.type.allowsMarks(child.marks) else { return false }
        match = next
    }
    return match.validEnd
}

func pmJoinable(_ a: PMNode?, _ b: PMNode?) -> Bool {
    guard let a, let b, !a.isLeaf else { return false }
    return pmCanAppend(a, b)
}

func pmCanJoin(_ doc: PMNode, _ pos: Int) -> Bool {
    guard let pos$ = try? doc.resolve(pos) else { return false }
    let index = pos$.index()
    return pmJoinable(pos$.nodeBefore, pos$.nodeAfter) && pos$.parent.canReplace(index, index + 1)
}

extension PMTransform {
    mutating func replaceWith(_ from: Int, _ to: Int, _ content: PMFragment) throws {
        try replace(from, to, PMSlice(content, openStart: 0, openEnd: 0))
    }

    mutating func insert(_ pos: Int, _ content: PMFragment) throws { try replaceWith(pos, pos, content) }

    mutating func lift(_ range: PMNodeRange, _ target: Int) throws {
        let from$ = range.from$, to$ = range.to$, depth = range.depth
        let gapStart = from$.before(depth + 1), gapEnd = to$.after(depth + 1)
        var start = gapStart, end = gapEnd
        var before = PMFragment.empty, openStart = 0
        var d = depth, splitting = false
        while d > target {
            if splitting || from$.index(d) > 0 {
                splitting = true
                before = PMFragment.from(from$.node(d).copy(before))
                openStart += 1
            } else {
                start -= 1
            }
            d -= 1
        }
        var after = PMFragment.empty, openEnd = 0
        d = depth
        splitting = false
        while d > target {
            if splitting || to$.after(d + 1) < to$.end(d) {
                splitting = true
                after = PMFragment.from(to$.node(d).copy(after))
                openEnd += 1
            } else {
                end += 1
            }
            d -= 1
        }
        try step(.replaceAround(from: start, to: end, gapFrom: gapStart, gapTo: gapEnd,
                                slice: PMSlice(before.append(after), openStart: openStart, openEnd: openEnd),
                                insert: before.size - openStart, structure: true))
    }

    mutating func join(_ pos: Int, depth: Int = 1) throws {
        let before$ = try doc.resolve(pos - depth), beforeType = before$.node().type
        let mapFrom = steps.count
        if beforeType.inlineContent {
            try clearIncompatible(pos + depth - 1, beforeType, match: try before$.node().contentMatchAt(before$.index()))
        }
        let start = map(pos - depth, from: mapFrom), end = map(pos + depth, from: mapFrom, assoc: -1)
        try step(.replace(from: start, to: end, slice: .empty, structure: true))
    }

    /// Maps through the steps added since `from`.
    func map(_ pos: Int, from: Int, assoc: Int = 1) -> Int {
        steps[from...].reduce(pos) { $1.map($0, assoc: assoc) }
    }

    private mutating func clearIncompatible(_ pos: Int, _ parentType: PMNodeType, match: PMContentMatch) throws {
        guard let node = doc.nodeAt(pos) else { throw PMReplaceError(message: "No node at \(pos)") }
        var match = match, replacements: [PMStep] = [], cur = pos + 1
        let pre = parentType.flag("code")
        for child in node.content.children {
            let end = cur + child.nodeSize
            if let allowed = match.matchType(child.type) {
                match = allowed
                guard child.marks.allSatisfy({ parentType.allowsMarkType($0.type) }) else {
                    throw PMReplaceError(message: "Mark removal on join is not supported")
                }
                if child.isText && !pre, let units = child.text {
                    var index = 0
                    while index < units.count {
                        let unit = units[index]
                        if unit == 10 || unit == 13 {
                            let length = unit == 13 && index + 1 < units.count && units[index + 1] == 10 ? 2 : 1
                            let space = PMSlice(PMFragment.from(child.type.isText
                                ? PMNode(type: child.type, attrs: [:], content: .empty,
                                         marks: parentType.allowedMarks(child.marks), text: [32]) : nil),
                                openStart: 0, openEnd: 0)
                            replacements.append(.replace(from: cur + index, to: cur + index + length, slice: space))
                            index += length
                        } else {
                            index += 1
                        }
                    }
                }
            } else {
                replacements.append(.replace(from: cur, to: end, slice: .empty))
            }
            cur = end
        }
        if !match.validEnd, let fill = match.fillBefore(.empty, toEnd: true) {
            try replace(cur, cur, PMSlice(fill, openStart: 0, openEnd: 0))
        }
        for replacement in replacements.reversed() { try step(replacement) }
    }

    mutating func setNodeMarkup(_ pos: Int, type: PMNodeType? = nil, attrs: [String: Any]? = nil,
                                marks: [PMMark]? = nil) throws {
        guard let node = doc.nodeAt(pos) else { throw PMReplaceError(message: "No node at given position") }
        let type = type ?? node.type
        let newNode = try type.create(attrs, .empty, marks: marks ?? node.marks)
        if node.isLeaf { return try replaceWith(pos, pos + node.nodeSize, PMFragment.from(newNode)) }
        guard type.validContent(node.content) else {
            throw PMReplaceError(message: "Invalid content for node type \(type.name)")
        }
        try step(.replaceAround(from: pos, to: pos + node.nodeSize, gapFrom: pos + 1, gapTo: pos + node.nodeSize - 1,
                                slice: PMSlice(PMFragment.from(newNode), openStart: 0, openEnd: 0), insert: 1, structure: true))
    }
}

import Foundation
import CoreFoundation

// A port of prosemirror-transform 1.12.2 replace.ts (replaceStep, Fitter,
// replaceRange, deleteRange, replaceRangeWith) and the replace steps and
// step maps they emit. Control flow mirrors the JavaScript source.

enum PMStep {
    case addMark(from: Int, to: Int, mark: PMMark)
    case removeMark(from: Int, to: Int, mark: PMMark)
    case attr(pos: Int, name: String, value: Any)
    case docAttr(name:String,value:Any)
    case replace(from: Int, to: Int, slice: PMSlice, structure: Bool = false)
    case replaceAround(from: Int, to: Int, gapFrom: Int, gapTo: Int, slice: PMSlice, insert: Int, structure: Bool = false)

    func apply(_ doc: PMNode) throws -> PMNode {
        switch self {
        case let .addMark(from, to, mark):
            let old = try doc.slice(from, to), resolved = try doc.resolve(from)
            let parent = resolved.node(resolved.sharedDepth(to))
            let content = pmMapInlineFragment(old.content, parent: parent) { node, parent in
                guard node.isAtom, parent.type.allowsMarkType(mark.type) else { return node }
                return node.mark(mark.addToSet(node.marks))
            }
            return try doc.replace(from, to, PMSlice(content, openStart: old.openStart, openEnd: old.openEnd))
        case let .removeMark(from, to, mark):
            let old = try doc.slice(from, to)
            let content = pmMapInlineFragment(old.content, parent: doc) { node, _ in node.mark(mark.removeFromSet(node.marks)) }
            return try doc.replace(from, to, PMSlice(content, openStart: old.openStart, openEnd: old.openEnd))
        case let .docAttr(name,value):
            // Maintained prosemirror-transform DocAttrStep.apply, same doc content.
            guard doc.type.attrs.contains(where:{$0.name==name}) else {throw PMReplaceError(message:"Unknown document attribute")}
            var attrs=doc.attrs;attrs[name]=value
            return try doc.type.create(attrs,doc.content,marks:doc.marks)
        case let .attr(pos, name, value):
            // prosemirror-transform 1.12.2 AttrStep.apply: replace only the
            // opening token; the open Slice preserves the node's rich children.
            guard let node = doc.nodeAt(pos) else { throw PMReplaceError(message: "No node at attribute step position") }
            var attrs=node.attrs;attrs[name]=value
            let updated=try node.type.create(attrs,.empty,marks:node.marks)
            return try doc.replace(pos,pos+1,PMSlice(PMFragment.from(updated),openStart:0,openEnd:node.isLeaf ? 0 : 1))
        case let .replace(from, to, slice, structure):
            if structure, try pmContentBetween(doc, from, to) {
                throw PMReplaceError(message: "Structure replace would overwrite content")
            }
            return try doc.replace(from, to, slice)
        case let .replaceAround(from, to, gapFrom, gapTo, slice, insert, structure):
            if structure, try pmContentBetween(doc, from, gapFrom) || pmContentBetween(doc, gapTo, to) {
                throw PMReplaceError(message: "Structure gap-replace would overwrite content")
            }
            let gap = try doc.slice(gapFrom, gapTo)
            guard gap.openStart == 0, gap.openEnd == 0 else { throw PMReplaceError(message: "Gap is not a flat range") }
            guard let inserted = try slice.insertAt(insert, gap.content) else {
                throw PMReplaceError(message: "Content does not fit in gap")
            }
            return try doc.replace(from, to, inserted)
        }
    }

    /// Exact maintained Step.toJSON shape, including upstream Slice fields.
    func json() -> [String:Any] {
        switch self {
        case let .addMark(from,to,mark):return ["stepType":"addMark","from":from,"to":to,"mark":mark.json()]
        case let .removeMark(from,to,mark):return ["stepType":"removeMark","from":from,"to":to,"mark":mark.json()]
        case let .docAttr(name,value):return ["stepType":"docAttr","attr":name,"value":value]
        case let .attr(pos,name,value):return ["stepType":"attr","pos":pos,"attr":name,"value":value]
        case let .replace(from,to,slice,structure):
            var result:[String:Any]=["stepType":"replace","from":from,"to":to]
            if slice.size != 0 { result["slice"]=slice.json() }
            if structure { result["structure"]=true };return result
        case let .replaceAround(from,to,gapFrom,gapTo,slice,insert,structure):
            var result:[String:Any]=["stepType":"replaceAround","from":from,"to":to,"gapFrom":gapFrom,"gapTo":gapTo,"insert":insert]
            if slice.size != 0 { result["slice"]=slice.json() }
            if structure { result["structure"]=true };return result
        }
    }

    /// StepMap ranges: (start, oldSize, newSize) triples.
    var ranges: [(Int, Int, Int)] {
        switch self {
        case .docAttr,.attr, .addMark, .removeMark: return []
        case let .replace(from, to, slice, _):
            return [(from, to - from, slice.size)]
        case let .replaceAround(from, to, gapFrom, gapTo, slice, insert, _):
            return [(from, gapFrom - from, insert), (gapTo, to - gapTo, slice.size - insert)]
        }
    }

    /// StepMap.map with ProseMirror's default association of 1.
    func map(_ pos: Int, assoc: Int = 1) -> Int {
        var diff = 0
        for (start, oldSize, newSize) in ranges {
            let adjusted = start
            if adjusted > pos { break }
            let end = adjusted + oldSize
            if pos <= end {
                let side = oldSize == 0 ? assoc : pos == adjusted ? -1 : pos == end ? 1 : assoc
                return adjusted + diff + (side < 0 ? 0 : newSize)
            }
            diff += newSize - oldSize
        }
        return pos + diff
    }
}

// Exact mapFragment algorithm from prosemirror-transform 1.12.2 mark_step.ts.
private func pmMapInlineFragment(_ fragment: PMFragment, parent: PMNode,
                                 transform: (PMNode, PMNode) -> PMNode) -> PMFragment {
    PMFragment.fromArray(fragment.children.map { original in
        var child = original
        if child.content.size > 0 { child = child.copy(pmMapInlineFragment(child.content, parent: child, transform: transform)) }
        return child.isInline ? transform(child, parent) : child
    })
}

struct PMTransform {
    private(set) var doc: PMNode
    private(set) var steps: [PMStep] = []

    init(_ doc: PMNode) { self.doc = doc }

    mutating func step(_ step: PMStep) throws {
        doc = try step.apply(doc)
        steps.append(step)
    }

    func map(_ pos: Int, assoc: Int = 1) -> Int {
        steps.reduce(pos) { $1.map($0, assoc: assoc) }
    }

    // Exact bounded traversal/coalescing from prosemirror-transform 1.12.2 mark.ts.
    mutating func addMark(_ from: Int, _ to: Int, _ mark: PMMark) throws {
        var removed: [PMStep] = [], added: [PMStep] = [], removing: Int?, adding: Int?
        doc.content.nodesBetween(from, to, { node, pos, parent, _ in
            guard node.isInline, let parent, !mark.isInSet(node.marks), parent.type.allowsMarkType(mark.type) else { return true }
            let start = max(pos, from), end = min(pos + node.nodeSize, to), set = mark.addToSet(node.marks)
            for old in node.marks where !old.isInSet(set) {
                if let index = removing, case let .removeMark(a,b,previous) = removed[index], b == start, previous.eq(old) {
                    removed[index] = .removeMark(from:a,to:end,mark:old)
                } else { removed.append(.removeMark(from:start,to:end,mark:old)); removing = removed.count - 1 }
            }
            if let index = adding, case let .addMark(a,b,_) = added[index], b == start {
                added[index] = .addMark(from:a,to:end,mark:mark)
            } else { added.append(.addMark(from:start,to:end,mark:mark)); adding = added.count - 1 }
            return true
        }, parent: doc)
        for change in removed + added { try step(change) }
    }

    // Maintained removeMark accepts a concrete Mark, MarkType, or all marks.
    // Type removal must retain each encountered authored attribute payload.
    mutating func removeMark(_ from: Int, _ to: Int, mark: PMMark? = nil, type: PMMarkType? = nil) throws {
        var matches: [(mark: PMMark, from: Int, to: Int, step: Int)] = [], visited = 0
        doc.content.nodesBetween(from, to, { node, pos, _, _ in
            guard node.isInline else { return true }; visited += 1
            let removed = node.marks.filter { candidate in
                if let type { return candidate.type === type }
                if let mark { return candidate.eq(mark) }
                return true
            }
            let end = min(pos + node.nodeSize, to)
            for style in removed {
                if let index = matches.lastIndex(where: { $0.step == visited - 1 && $0.mark.eq(style) }) {
                    matches[index].to = end; matches[index].step = visited
                } else { matches.append((style,max(pos,from),end,visited)) }
            }
            return true
        }, parent: doc)
        for change in matches { try step(.removeMark(from:change.from,to:change.to,mark:change.mark)) }
    }

    mutating func replace(_ from: Int, _ to: Int? = nil, _ slice: PMSlice = .empty) throws {
        if let step = try pmReplaceStep(doc, from, to ?? from, slice) { try self.step(step) }
    }

    mutating func delete(_ from: Int, _ to: Int) throws { try replace(from, to, .empty) }

    mutating func replaceRange(_ from: Int, _ to: Int, _ slice: PMSlice) throws {
        var from = from, to = to
        if slice.size == 0 { return try deleteRange(from, to) }
        let from$ = try doc.resolve(from), to$ = try doc.resolve(to)
        if pmFitsTrivially(from$, to$, slice) { return try step(.replace(from: from, to: to, slice: slice)) }
        var targetDepths = pmCoveredDepths(from$, to$)
        if targetDepths.last == 0 { targetDepths.removeLast() }
        var preferredTarget = -(from$.depth + 1)
        targetDepths.insert(preferredTarget, at: 0)
        var d = from$.depth, pos = from$.pos - 1
        while d > 0 {
            let type = from$.node(d).type
            if type.flag("defining") || type.flag("definingAsContext") || type.flag("isolating") { break }
            if targetDepths.contains(d) { preferredTarget = d }
            else if from$.before(d) == pos { targetDepths.insert(-d, at: 1) }
            d -= 1
            pos -= 1
        }
        let preferredTargetIndex = targetDepths.firstIndex(of: preferredTarget)!
        // As in JavaScript, an empty open level contributes a null left node.
        var leftNodes: [PMNode?] = [], preferredDepth = slice.openStart
        var content = slice.content, i = 0
        while true {
            let node = content.firstChild
            leftNodes.append(node)
            if i == slice.openStart { break }
            guard let node else { throw PMReplaceError(message: "Open slice level has no content") }
            content = node.content
            i += 1
        }
        var depth = preferredDepth - 1
        while depth >= 0 {
            guard let leftNode = leftNodes[depth] else { break }
            let defines = pmDefinesContent(leftNode.type)
            if defines, !leftNode.sameMarkup(from$.node(abs(preferredTarget) - 1)) { preferredDepth = depth }
            else if defines || !leftNode.type.isTextblock { break }
            depth -= 1
        }
        var j = slice.openStart
        while j >= 0 {
            let openDepth = (j + preferredDepth + 1) % (slice.openStart + 1)
            if leftNodes.indices.contains(openDepth), let insert = leftNodes[openDepth] {
                for k in 0..<targetDepths.count {
                    var targetDepth = targetDepths[(k + preferredTargetIndex) % targetDepths.count], expand = true
                    if targetDepth < 0 { expand = false; targetDepth = -targetDepth }
                    let parent = from$.node(targetDepth - 1), index = from$.index(targetDepth - 1)
                    if parent.canReplaceWith(index, index, insert.type, marks: insert.marks) {
                        return try replace(from$.before(targetDepth), expand ? to$.after(targetDepth) : to,
                            PMSlice(pmCloseFragment(slice.content, 0, slice.openStart, openDepth, nil),
                                    openStart: openDepth, openEnd: slice.openEnd))
                    }
                }
            }
            j -= 1
        }
        let startSteps = steps.count
        var index = targetDepths.count - 1
        while index >= 0 {
            try replace(from, to, slice)
            if steps.count > startSteps { break }
            let depth = targetDepths[index]
            index -= 1
            if depth < 0 { continue }
            from = from$.before(depth)
            to = to$.after(depth)
        }
    }

    mutating func replaceRangeWith(_ from: Int, _ to: Int, _ node: PMNode) throws {
        var from = from, to = to
        if !node.isInline, from == to, try doc.resolve(from).parent.content.size > 0,
           let point = try pmInsertPoint(doc, from, node.type) {
            from = point
            to = point
        }
        try replaceRange(from, to, PMSlice(PMFragment.from(node), openStart: 0, openEnd: 0))
    }

    mutating func deleteRange(_ from: Int, _ to: Int) throws {
        var from = from, to = to
        var from$ = try doc.resolve(from), to$ = try doc.resolve(to)
        if from$.parent.isTextblock, to$.parent.isTextblock, from$.start() != to$.start(),
           from$.parentOffset == 0, to$.parentOffset == 0 {
            let shared = from$.sharedDepth(to)
            var isolated = false
            var d = from$.depth
            while d > shared { if from$.node(d).type.flag("isolating") { isolated = true }; d -= 1 }
            d = to$.depth
            while d > shared { if to$.node(d).type.flag("isolating") { isolated = true }; d -= 1 }
            if !isolated {
                d = from$.depth
                while d > 0 && from == from$.start(d) { from = from$.before(d); d -= 1 }
                d = to$.depth
                while d > 0 && to == to$.start(d) { to = to$.before(d); d -= 1 }
                from$ = try doc.resolve(from)
                to$ = try doc.resolve(to)
            }
        }
        let covered = pmCoveredDepths(from$, to$)
        for (i, depth) in covered.enumerated() {
            let last = i == covered.count - 1
            if (last && depth == 0) || from$.node(depth).type.contentMatch.validEnd {
                return try delete(from$.start(depth), to$.end(depth))
            }
            if depth > 0, last || from$.node(depth - 1).canReplace(from$.index(depth - 1), to$.indexAfter(depth - 1)) {
                return try delete(from$.before(depth), to$.after(depth))
            }
        }
        var d = 1
        while d <= from$.depth && d <= to$.depth {
            if from - from$.start(d) == from$.depth - d, to > from$.end(d), to$.end(d) - to != to$.depth - d,
               from$.start(d - 1) == to$.start(d - 1),
               from$.node(d - 1).canReplace(from$.index(d - 1), to$.index(d - 1)) {
                return try delete(from$.before(d), to)
            }
            d += 1
        }
        try delete(from, to)
    }

    /// Transaction.insertText with explicit or inherited marks.
    mutating func insertText(_ text: [UInt16], _ from: Int, _ to: Int, schema: PMSchema, marks: [PMMark]? = nil) throws {
        if text.isEmpty { return try deleteRange(from, to) }
        let from$ = try doc.resolve(from), to$ = try doc.resolve(to)
        let marks = marks ?? (to == from ? from$.marks() : (from$.marksAcross(to$) ?? []))
        try replaceRangeWith(from, to, schema.text(text, marks: marks))
    }
}

func pmReplaceStep(_ doc: PMNode, _ from: Int, _ to: Int, _ slice: PMSlice) throws -> PMStep? {
    if from == to && slice.size == 0 { return nil }
    let from$ = try doc.resolve(from), to$ = try doc.resolve(to)
    if pmFitsTrivially(from$, to$, slice) { return .replace(from: from, to: to, slice: slice) }
    return try PMFitter(from$, to$, slice).fit()
}

func pmFitsTrivially(_ from$: PMResolvedPos, _ to$: PMResolvedPos, _ slice: PMSlice) -> Bool {
    slice.openStart == 0 && slice.openEnd == 0 && from$.start() == to$.start() &&
        from$.parent.canReplace(from$.index(), to$.index(), slice.content)
}

private func pmDefinesContent(_ type: PMNodeType) -> Bool { type.flag("defining") || type.flag("definingForContent") }

func pmCoveredDepths(_ from$: PMResolvedPos, _ to$: PMResolvedPos) -> [Int] {
    var result: [Int] = []
    var d = min(from$.depth, to$.depth)
    while d >= 0 {
        let start = from$.start(d)
        if start < from$.pos - (from$.depth - d) || to$.end(d) > to$.pos + (to$.depth - d) ||
            from$.node(d).type.flag("isolating") || to$.node(d).type.flag("isolating") { break }
        if start == to$.start(d) || (d == from$.depth && d == to$.depth && from$.parent.inlineContent &&
            to$.parent.inlineContent && d > 0 && to$.start(d - 1) == start - 1) {
            result.append(d)
        }
        d -= 1
    }
    return result
}

private func pmCloseFragment(_ fragment: PMFragment, _ depth: Int, _ oldOpen: Int, _ newOpen: Int,
                             _ parent: PMNode?) -> PMFragment {
    var fragment = fragment
    if depth < oldOpen, let first = fragment.firstChild {
        fragment = fragment.replaceChild(0, first.copy(pmCloseFragment(first.content, depth + 1, oldOpen, newOpen, first)))
    }
    if depth > newOpen, let parent, let match = try? parent.contentMatchAt(0),
       let before = match.fillBefore(fragment) {
        let start = before.append(fragment)
        if let after = match.matchFragment(start)?.fillBefore(.empty, toEnd: true) {
            fragment = start.append(after)
        } else {
            fragment = start
        }
    }
    return fragment
}

func pmInsertPoint(_ doc: PMNode, _ pos: Int, _ nodeType: PMNodeType) throws -> Int? {
    let pos$ = try doc.resolve(pos)
    if pos$.parent.canReplaceWith(pos$.index(), pos$.index(), nodeType) { return pos }
    if pos$.parentOffset == 0 {
        var d = pos$.depth - 1
        while d >= 0 {
            let index = pos$.index(d)
            if pos$.node(d).canReplaceWith(index, index, nodeType) { return pos$.before(d + 1) }
            if index > 0 { return nil }
            d -= 1
        }
    }
    if pos$.parentOffset == pos$.parent.content.size {
        var d = pos$.depth - 1
        while d >= 0 {
            let index = pos$.indexAfter(d)
            if pos$.node(d).canReplaceWith(index, index, nodeType) { return pos$.after(d + 1) }
            if index < pos$.node(d).childCount { return nil }
            d -= 1
        }
    }
    return nil
}

// MARK: Fitter

private struct PMFittable {
    let sliceDepth: Int
    let frontierDepth: Int
    let parent: PMNode?
    var inject: PMFragment?
    var wrap: [PMNodeType]?
}

private final class PMFitter {
    let from$: PMResolvedPos
    let to$: PMResolvedPos
    var unplaced: PMSlice
    var frontier: [(type: PMNodeType, match: PMContentMatch)] = []
    var placed: PMFragment = .empty

    init(_ from$: PMResolvedPos, _ to$: PMResolvedPos, _ unplaced: PMSlice) throws {
        self.from$ = from$
        self.to$ = to$
        self.unplaced = unplaced
        for i in 0...from$.depth {
            let node = from$.node(i)
            frontier.append((node.type, try node.contentMatchAt(from$.indexAfter(i))))
        }
        var i = from$.depth
        while i > 0 {
            placed = PMFragment.from(from$.node(i).copy(placed))
            i -= 1
        }
    }

    var depth: Int { frontier.count - 1 }

    func fit() throws -> PMStep? {
        while unplaced.size > 0 {
            if let fit = findFittable() { try placeNodes(fit) }
            else if !openMore() { dropNode() }
        }
        let moveInline = mustMoveInline(), placedSize = placed.size - depth - from$.depth
        let from$ = self.from$
        guard let to$ = try close(moveInline < 0 ? self.to$ : from$.doc.resolve(moveInline)) else { return nil }
        var content = placed, openStart = from$.depth, openEnd = to$.depth
        while openStart > 0 && openEnd > 0 && content.childCount == 1 {
            content = content.firstChild!.content
            openStart -= 1
            openEnd -= 1
        }
        let slice = PMSlice(content, openStart: openStart, openEnd: openEnd)
        if moveInline > -1 {
            return .replaceAround(from: from$.pos, to: moveInline, gapFrom: self.to$.pos, gapTo: self.to$.end(),
                                  slice: slice, insert: placedSize)
        }
        if slice.size > 0 || from$.pos != self.to$.pos { return .replace(from: from$.pos, to: to$.pos, slice: slice) }
        return nil
    }

    private func findFittable() -> PMFittable? {
        var startDepth = unplaced.openStart
        var current = unplaced.content, openEnd = unplaced.openEnd, d = 0
        while d < startDepth {
            let node = current.firstChild!
            if current.childCount > 1 { openEnd = 0 }
            if node.type.flag("isolating") && openEnd <= d { startDepth = d; break }
            current = node.content
            d += 1
        }
        for pass in 1...2 {
            var sliceDepth = pass == 1 ? startDepth : unplaced.openStart
            while sliceDepth >= 0 {
                var fragment: PMFragment, parent: PMNode? = nil
                if sliceDepth > 0 {
                    parent = pmContentAt(unplaced.content, sliceDepth - 1).firstChild
                    fragment = parent!.content
                } else {
                    fragment = unplaced.content
                }
                let first = fragment.firstChild
                var frontierDepth = depth
                while frontierDepth >= 0 {
                    let (type, match) = frontier[frontierDepth]
                    if pass == 1 {
                        var inject: PMFragment?
                        let fits: Bool
                        if let first {
                            if match.matchType(first.type) != nil { fits = true }
                            else if let filled = match.fillBefore(PMFragment.from(first)) { inject = filled; fits = true }
                            else { fits = false }
                        } else {
                            fits = parent.map { type.compatibleContent($0.type) } ?? false
                        }
                        if fits {
                            return PMFittable(sliceDepth: sliceDepth, frontierDepth: frontierDepth, parent: parent, inject: inject)
                        }
                    } else if let first, let wrap = match.findWrapping(first.type) {
                        return PMFittable(sliceDepth: sliceDepth, frontierDepth: frontierDepth, parent: parent, wrap: wrap)
                    }
                    if let parent, match.matchType(parent.type) != nil { break }
                    frontierDepth -= 1
                }
                sliceDepth -= 1
            }
        }
        return nil
    }

    private func openMore() -> Bool {
        let content = unplaced.content, openStart = unplaced.openStart
        var openEnd = unplaced.openEnd
        if pmMaxOpen(content, -1) <= openStart { return false }
        if unplaced.size > 1 && pmMaxOpen(content, 1) > openEnd { openEnd += 1 }
        unplaced = PMSlice(content, openStart: openStart + 1, openEnd: openEnd)
        return true
    }

    private func dropNode() {
        let content = unplaced.content, openStart = unplaced.openStart, openEnd = unplaced.openEnd
        let inner = pmContentAt(content, openStart)
        if inner.childCount <= 1 && openStart > 0 {
            let openAtEnd = content.size - openStart <= openStart + inner.size
            unplaced = PMSlice(pmDropFromFragment(content, openStart - 1, 1), openStart: openStart - 1,
                               openEnd: openAtEnd ? openStart - 1 : openEnd)
        } else {
            unplaced = PMSlice(pmDropFromFragment(content, openStart, 1), openStart: openStart, openEnd: openEnd)
        }
    }

    private func placeNodes(_ fit: PMFittable) throws {
        while depth > fit.frontierDepth { closeFrontierNode() }
        if let wrap = fit.wrap { for type in wrap { try openFrontierNode(type) } }
        let slice = unplaced, fragment = fit.parent?.content ?? slice.content
        let openStart = slice.openStart - fit.sliceDepth
        var taken = 0, add: [PMNode] = []
        var (type, match) = (frontier[fit.frontierDepth].type, frontier[fit.frontierDepth].match)
        if let inject = fit.inject {
            add.append(contentsOf: inject.children)
            guard let injected = match.matchFragment(inject) else { throw PMReplaceError(message: "Invalid injection") }
            match = injected
        }
        var openEndCount = (fragment.size + fit.sliceDepth) - (slice.content.size - slice.openEnd)
        while taken < fragment.childCount {
            let next = fragment.child(taken)
            guard let matches = match.matchType(next.type) else { break }
            taken += 1
            if taken > 1 || openStart == 0 || next.content.size > 0 {
                match = matches
                add.append(pmCloseNodeStart(next.mark(type.allowedMarks(next.marks)), taken == 1 ? openStart : 0,
                                            taken == fragment.childCount ? openEndCount : -1))
            }
        }
        let toEnd = taken == fragment.childCount
        if !toEnd { openEndCount = -1 }
        placed = pmAddToFragment(placed, fit.frontierDepth, PMFragment.fromArray(add))
        frontier[fit.frontierDepth].match = match
        if toEnd && openEndCount < 0, let parent = fit.parent, parent.type === frontier[depth].type, frontier.count > 1 {
            closeFrontierNode()
        }
        var current = fragment
        for _ in 0..<max(openEndCount, 0) {
            let node = current.lastChild!
            frontier.append((node.type, try node.contentMatchAt(node.childCount)))
            current = node.content
        }
        unplaced = !toEnd ? PMSlice(pmDropFromFragment(slice.content, fit.sliceDepth, taken),
                                    openStart: slice.openStart, openEnd: slice.openEnd)
            : fit.sliceDepth == 0 ? .empty
            : PMSlice(pmDropFromFragment(slice.content, fit.sliceDepth - 1, 1), openStart: fit.sliceDepth - 1,
                      openEnd: openEndCount < 0 ? slice.openEnd : fit.sliceDepth - 1)
    }

    private func mustMoveInline() -> Int {
        guard to$.parent.isTextblock else { return -1 }
        let top = frontier[depth]
        if !top.type.isTextblock || pmContentAfterFits(to$, to$.depth, top.type, top.match, false) == nil { return -1 }
        if to$.depth == depth, let level = findCloseLevel(to$), level.depth == depth { return -1 }
        var depth = to$.depth, after = to$.after(depth)
        while depth > 1 {
            depth -= 1
            guard after == to$.end(depth) else { break }
            after += 1
        }
        return after
    }

    private func findCloseLevel(_ to$: PMResolvedPos) -> (depth: Int, fit: PMFragment, move: PMResolvedPos)? {
        var i = min(depth, to$.depth)
        scan: while i >= 0 {
            defer { i -= 1 }
            let (type, match) = frontier[i]
            let dropInner = i < to$.depth && to$.end(i + 1) == to$.pos + (to$.depth - (i + 1))
            guard let fit = pmContentAfterFits(to$, i, type, match, dropInner) else { continue }
            var d = i - 1
            while d >= 0 {
                let (type, match) = frontier[d]
                guard let matches = pmContentAfterFits(to$, d, type, match, true), matches.childCount == 0 else {
                    continue scan
                }
                d -= 1
            }
            let move = dropInner ? (try? to$.doc.resolve(to$.after(i + 1))) ?? to$ : to$
            return (i, fit, move)
        }
        return nil
    }

    private func close(_ to$: PMResolvedPos) throws -> PMResolvedPos? {
        guard let close = findCloseLevel(to$) else { return nil }
        while depth > close.depth { closeFrontierNode() }
        if close.fit.childCount > 0 { placed = pmAddToFragment(placed, close.depth, close.fit) }
        let moved = close.move
        var d = close.depth + 1
        while d <= moved.depth {
            let node = moved.node(d)
            let add = node.type.contentMatch.fillBefore(node.content, toEnd: true, startIndex: moved.index(d))
            try openFrontierNode(node.type, node.attrs, add)
            d += 1
        }
        return moved
    }

    private func openFrontierNode(_ type: PMNodeType, _ attrs: [String: Any]? = nil, _ content: PMFragment? = nil) throws {
        guard let matched = frontier[depth].match.matchType(type) else {
            throw PMReplaceError(message: "Cannot open \(type.name) here")
        }
        frontier[depth].match = matched
        placed = pmAddToFragment(placed, depth, PMFragment.from(try type.create(attrs, content ?? .empty)))
        frontier.append((type, type.contentMatch))
    }

    private func closeFrontierNode() {
        let open = frontier.removeLast()
        if let add = open.match.fillBefore(.empty, toEnd: true), add.childCount > 0 {
            placed = pmAddToFragment(placed, frontier.count, add)
        }
    }
}

private func pmDropFromFragment(_ fragment: PMFragment, _ depth: Int, _ count: Int) -> PMFragment {
    if depth == 0 { return fragment.cutByIndex(count, fragment.childCount) }
    return fragment.replaceChild(0, fragment.firstChild!.copy(pmDropFromFragment(fragment.firstChild!.content, depth - 1, count)))
}

private func pmAddToFragment(_ fragment: PMFragment, _ depth: Int, _ content: PMFragment) -> PMFragment {
    if depth == 0 { return fragment.append(content) }
    return fragment.replaceChild(fragment.childCount - 1,
        fragment.lastChild!.copy(pmAddToFragment(fragment.lastChild!.content, depth - 1, content)))
}

private func pmMaxOpen(_ fragment: PMFragment, _ side: Int) -> Int {
    var fragment = fragment, count = 0
    while true {
        guard let child = side < 0 ? fragment.firstChild : fragment.lastChild, !child.isAtom else { return count }
        fragment = child.content
        count += 1
    }
}

private func pmContentAt(_ fragment: PMFragment, _ depth: Int) -> PMFragment {
    var fragment = fragment
    for _ in 0..<depth { fragment = fragment.firstChild!.content }
    return fragment
}

private func pmCloseNodeStart(_ node: PMNode, _ openStart: Int, _ openEnd: Int) -> PMNode {
    if openStart <= 0 { return node }
    var fragment = node.content
    if openStart > 1 {
        fragment = fragment.replaceChild(0, pmCloseNodeStart(fragment.firstChild!, openStart - 1,
                                                             fragment.childCount == 1 ? openEnd - 1 : 0))
    }
    if openStart > 0 {
        fragment = (node.type.contentMatch.fillBefore(fragment) ?? .empty).append(fragment)
        if openEnd <= 0, let end = node.type.contentMatch.matchFragment(fragment)?.fillBefore(.empty, toEnd: true) {
            fragment = fragment.append(end)
        }
    }
    return node.copy(fragment)
}

private func pmContentAfterFits(_ to$: PMResolvedPos, _ depth: Int, _ type: PMNodeType, _ match: PMContentMatch,
                                _ open: Bool) -> PMFragment? {
    let node = to$.node(depth), index = open ? to$.indexAfter(depth) : to$.index(depth)
    if index == node.childCount && !type.compatibleContent(node.type) { return nil }
    guard let fit = match.fillBefore(node.content, toEnd: true, startIndex: index) else { return nil }
    return pmInvalidMarks(type, node.content, index) ? nil : fit
}

private func pmInvalidMarks(_ type: PMNodeType, _ fragment: PMFragment, _ start: Int) -> Bool {
    (start..<max(start, fragment.childCount)).contains { !type.allowsMarks(fragment.child($0).marks) }
}

// prosemirror-model 1.25.12 Node/Mark/Slice.toJSON, matching the browser wire.
extension PMNode {
    func json() -> [String:Any] {
        var result:[String:Any]=["type":type.name]
        if !attrs.isEmpty { result["attrs"]=attrs }
        if content.size != 0 { result["content"]=content.children.map { $0.json() } }
        if !marks.isEmpty { result["marks"]=marks.map { $0.json() } }
        if isText { result["text"]=textString };return result
    }
}
extension PMMark {
    func json() -> [String:Any] {
        var result:[String:Any]=["type":type.name]
        if !attrs.isEmpty { result["attrs"]=attrs };return result
    }
}
extension PMSlice {
    func json() -> Any {
        if content.size == 0 { return NSNull() }
        var result:[String:Any]=["content":content.children.map { $0.json() }]
        if openStart>0 { result["openStart"]=openStart }
        if openEnd>0 { result["openEnd"]=openEnd };return result
    }
}

// Maintained Step.fromJSON / Node.fromJSON / Slice.fromJSON for the packaged
// canonical command result. Closed-document validation remains in the shared
// schema/command owner; open Slice nodes are intentionally decoded as partial.
extension PMStep {
    static func fromJSON(_ json: [String: Any], schema: PMSchema) throws -> PMStep {
        func number(_ key: String) throws -> Int {
            guard let value = json[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite, value.doubleValue.rounded() == value.doubleValue,
                  value.doubleValue >= 0, value.doubleValue <= 1_000_000_000 else { throw PMReplaceError(message: "Invalid step position") }
            return value.intValue
        }
        func mark(_ json: [String: Any]) throws -> PMMark {
            guard let name = json["type"] as? String, let type = schema.marks[name] else { throw PMReplaceError(message: "Unknown mark") }
            return type.create(json["attrs"] as? [String: Any])
        }
        func node(_ json: [String: Any]) throws -> PMNode {
            guard let name = json["type"] as? String, let type = schema.nodes[name] else { throw PMReplaceError(message: "Unknown node") }
            let marks = try (json["marks"] as? [[String: Any]] ?? []).map(mark)
            if type.isText {
                guard let text = json["text"] as? String, !text.isEmpty else { throw PMReplaceError(message: "Invalid text") }
                return schema.text(Array(text.utf16), marks: marks)
            }
            return try type.create(json["attrs"] as? [String: Any], PMFragment.fromArray(try (json["content"] as? [[String: Any]] ?? []).map(node)), marks: marks)
        }
        func slice() throws -> PMSlice {
            guard let value = json["slice"] as? [String: Any] else { return .empty }
            return PMSlice(PMFragment.fromArray(try (value["content"] as? [[String: Any]] ?? []).map(node)),
                openStart: value["openStart"] as? Int ?? 0, openEnd: value["openEnd"] as? Int ?? 0)
        }
        switch json["stepType"] as? String {
        case "replace": return try .replace(from: number("from"), to: number("to"), slice: slice(), structure: json["structure"] as? Bool ?? false)
        case "replaceAround": return try .replaceAround(from: number("from"), to: number("to"), gapFrom: number("gapFrom"), gapTo: number("gapTo"), slice: slice(), insert: number("insert"), structure: json["structure"] as? Bool ?? false)
        case "addMark", "removeMark":
            guard let raw = json["mark"] as? [String: Any] else { throw PMReplaceError(message: "Missing mark") }
            let from = try number("from"), to = try number("to"), value = try mark(raw)
            return json["stepType"] as? String == "addMark" ? .addMark(from: from, to: to, mark: value) : .removeMark(from: from, to: to, mark: value)
        case "attr":
            guard let name = json["attr"] as? String, let value = json["value"] else { throw PMReplaceError(message: "Missing attribute") }
            return try .attr(pos: number("pos"), name: name, value: value)
        case "docAttr":
            guard let name = json["attr"] as? String, let value = json["value"] else { throw PMReplaceError(message: "Missing document attribute") }
            return .docAttr(name: name, value: value)
        default: throw PMReplaceError(message: "Unknown step")
        }
    }
}

import Foundation

// prosemirror-commands 1.7.2 (joinBackward, joinForward, deleteBarrier,
// joinMaybeClear, selectNodeBackward/Forward, lift), prosemirror-schema-list
// liftListItem, and the TipTap commands and keymaps the canonical browser editor
// binds to Backspace and Delete, in the browser's plugin order.
//
// TipTap builds keymap plugins from its extensions in reverse order within a
// priority, and a chain dispatches whatever it built even when one of its
// commands returns false. PMState therefore accumulates every step so later
// handlers see the same intermediate document the browser would.

enum PMSelection: Equatable {
    case text(Int)
    case node(Int)
}

struct PMState {
    var transform: PMTransform
    var selection: PMSelection

    var doc: PMNode { transform.doc }
    var head: Int {
        switch selection {
        case .text(let pos), .node(let pos): return pos
        }
    }
}

typealias PMCommand = (PMState) throws -> PMState?

enum PMCommands {
    // MARK: Selection search (prosemirror-state Selection.findFrom / near / map)

    static func findSelectionIn(_ node: PMNode, _ pos: Int, _ index: Int, _ dir: Int, textOnly: Bool = false) -> PMSelection? {
        if node.inlineContent { return .text(pos) }
        var i = index - (dir > 0 ? 0 : 1), pos = pos
        while dir > 0 ? i < node.childCount : i >= 0 {
            let child = node.child(i)
            if !child.isAtom {
                if let inner = findSelectionIn(child, pos + dir, dir < 0 ? child.childCount : 0, dir, textOnly: textOnly) {
                    return inner
                }
            } else if !textOnly && !child.isText {
                return .node(pos - (dir < 0 ? child.nodeSize : 0))
            }
            pos += child.nodeSize * dir
            i += dir
        }
        return nil
    }

    static func findFrom(_ pos$: PMResolvedPos, _ dir: Int, textOnly: Bool = false) -> PMSelection? {
        if pos$.parent.inlineContent { return .text(pos$.pos) }
        if let inner = findSelectionIn(pos$.parent, pos$.pos, pos$.index(), dir, textOnly: textOnly) { return inner }
        var depth = pos$.depth - 1
        while depth >= 0 {
            let found = dir < 0
                ? findSelectionIn(pos$.node(depth), pos$.before(depth + 1), pos$.index(depth), dir, textOnly: textOnly)
                : findSelectionIn(pos$.node(depth), pos$.after(depth + 1), pos$.index(depth) + 1, dir, textOnly: textOnly)
            if let found { return found }
            depth -= 1
        }
        return nil
    }

    static func near(_ pos$: PMResolvedPos, bias: Int = 1) -> PMSelection? {
        findFrom(pos$, bias) ?? findFrom(pos$, -bias)
    }

    /// Selection.map through the steps added since `from`.
    static func mapped(_ transform: PMTransform, _ selection: PMSelection, from: Int) -> PMSelection {
        switch selection {
        case .text(let head):
            let pos = transform.map(head, from: from)
            guard let pos$ = try? transform.doc.resolve(pos) else { return .text(pos) }
            return pos$.parent.inlineContent ? .text(pos) : near(pos$) ?? .text(pos)
        case .node(let anchor):
            let pos = transform.map(anchor, from: from)
            guard let pos$ = try? transform.doc.resolve(pos) else { return .node(pos) }
            return pos$.nodeAfter != nil ? .node(pos) : near(pos$) ?? .node(pos)
        }
    }

    private static func extended(_ state: PMState, _ build: (inout PMTransform) throws -> Void) throws -> PMState {
        var transform = state.transform
        let from = transform.steps.count
        try build(&transform)
        return PMState(transform: transform, selection: mapped(transform, state.selection, from: from))
    }

    private static func textblockAt(_ node: PMNode?, start: Bool, only: Bool = false) -> Bool {
        var scan = node
        while let current = scan {
            if current.isTextblock { return true }
            if only && current.childCount != 1 { return false }
            scan = start ? current.firstChild : current.lastChild
        }
        return false
    }

    private static func selectable(_ node: PMNode) -> Bool { !node.isText }

    private static func findCutBefore(_ pos$: PMResolvedPos) -> PMResolvedPos? {
        guard !pos$.parent.type.flag("isolating") else { return nil }
        var i = pos$.depth - 1
        while i >= 0 {
            if pos$.index(i) > 0 { return try? pos$.doc.resolve(pos$.before(i + 1)) }
            if pos$.node(i).type.flag("isolating") { break }
            i -= 1
        }
        return nil
    }

    private static func findCutAfter(_ pos$: PMResolvedPos) -> PMResolvedPos? {
        guard !pos$.parent.type.flag("isolating") else { return nil }
        var i = pos$.depth - 1
        while i >= 0 {
            let parent = pos$.node(i)
            if pos$.index(i) + 1 < parent.childCount { return try? pos$.doc.resolve(pos$.after(i + 1)) }
            if parent.type.flag("isolating") { break }
            i -= 1
        }
        return nil
    }

    private static func cursor(_ state: PMState) throws -> PMResolvedPos? {
        guard case .text(let head) = state.selection else { return nil }
        return try state.doc.resolve(head)
    }

    // MARK: prosemirror-commands

    private static func joinMaybeClear(_ state: PMState, _ pos$: PMResolvedPos) throws -> PMState? {
        guard let before = pos$.nodeBefore, let after = pos$.nodeAfter,
              before.type.compatibleContent(after.type) else { return nil }
        let index = pos$.index()
        if before.content.size == 0 && pos$.parent.canReplace(index - 1, index) {
            return try extended(state) { try $0.delete(pos$.pos - before.nodeSize, pos$.pos) }
        }
        guard pos$.parent.canReplace(index, index + 1), after.isTextblock || pmCanJoin(state.doc, pos$.pos) else { return nil }
        return try extended(state) { try $0.join(pos$.pos) }
    }

    private static func deleteBarrier(_ state: PMState, _ cut$: PMResolvedPos, dir: Int) throws -> PMState? {
        let doc = state.doc
        guard let before = cut$.nodeBefore, let after = cut$.nodeAfter else { return nil }
        let isolated = before.type.flag("isolating") || after.type.flag("isolating")
        if !isolated, let joined = try joinMaybeClear(state, cut$) { return joined }
        let canDelAfter = !isolated && cut$.parent.canReplace(cut$.index(), cut$.index() + 1)
        if canDelAfter, let match = try? before.contentMatchAt(before.childCount),
           let conn = match.findWrapping(after.type), match.matchType(conn.first ?? after.type)?.validEnd == true {
            return try extended(state) { transform in
                let end = cut$.pos + after.nodeSize
                var wrap = PMFragment.empty
                for type in conn.reversed() { wrap = PMFragment.from(try type.create(nil, wrap)) }
                wrap = PMFragment.from(before.copy(wrap))
                try transform.step(.replaceAround(from: cut$.pos - 1, to: end, gapFrom: cut$.pos, gapTo: end,
                    slice: PMSlice(wrap, openStart: 1, openEnd: 0), insert: conn.count, structure: true))
                let joinAt$ = try transform.doc.resolve(end + 2 * conn.count)
                if let next = joinAt$.nodeAfter, next.type === before.type, pmCanJoin(transform.doc, joinAt$.pos) {
                    try transform.join(joinAt$.pos)
                }
            }
        }
        let selectionAfter = after.type.flag("isolating") || (dir > 0 && isolated) ? nil : findFrom(cut$, 1)
        var range: PMNodeRange?
        switch selectionAfter {
        case .text(let pos)?:
            let pos$ = try doc.resolve(pos)
            range = pos$.blockRange(pos$)
        case .node(let pos)?:
            let from$ = try doc.resolve(pos)
            range = from$.blockRange(try doc.resolve(pos + (from$.nodeAfter?.nodeSize ?? 0)))
        case nil:
            range = nil
        }
        if let range, let target = pmLiftTarget(range), target >= cut$.depth {
            return try extended(state) { try $0.lift(range, target) }
        }
        if canDelAfter && textblockAt(after, start: true, only: true) && textblockAt(before, start: false) {
            var at = before, wrap: [PMNode] = []
            while true {
                wrap.append(at)
                if at.isTextblock { break }
                guard let last = at.lastChild else { return nil }
                at = last
            }
            var afterText = after, afterDepth = 1
            while !afterText.isTextblock {
                guard let first = afterText.firstChild else { return nil }
                afterText = first
                afterDepth += 1
            }
            if at.canReplace(at.childCount, at.childCount, afterText.content) {
                return try extended(state) { transform in
                    var end = PMFragment.empty
                    for node in wrap.reversed() { end = PMFragment.from(node.copy(end)) }
                    try transform.step(.replaceAround(from: cut$.pos - wrap.count, to: cut$.pos + after.nodeSize,
                        gapFrom: cut$.pos + afterDepth, gapTo: cut$.pos + after.nodeSize - afterDepth,
                        slice: PMSlice(end, openStart: wrap.count, openEnd: 0), insert: 0, structure: true))
                }
            }
        }
        return nil
    }

    static func joinBackward(_ state: PMState) throws -> PMState? {
        guard let cursor$ = try cursor(state), cursor$.parent.isTextblock, cursor$.parentOffset == 0 else { return nil }
        guard let cut$ = findCutBefore(cursor$) else {
            guard let range = cursor$.blockRange(), let target = pmLiftTarget(range) else { return nil }
            return try extended(state) { try $0.lift(range, target) }
        }
        guard let before = cut$.nodeBefore else { return nil }
        if let barrier = try deleteBarrier(state, cut$, dir: -1) { return barrier }
        if cursor$.parent.content.size == 0 && (textblockAt(before, start: false) || selectable(before)) {
            var depth = cursor$.depth
            while true {
                if let step = try pmReplaceStep(state.doc, cursor$.before(depth), cursor$.after(depth), .empty),
                   step.slice.size < step.to - step.from {
                    var transform = state.transform
                    let from = transform.steps.count
                    try transform.step(step)
                    let selection: PMSelection = textblockAt(before, start: false)
                        ? findFrom(try transform.doc.resolve(transform.map(cut$.pos, from: from, assoc: -1)), -1) ?? .text(0)
                        : .node(cut$.pos - before.nodeSize)
                    return PMState(transform: transform, selection: selection)
                }
                if depth == 1 || cursor$.node(depth - 1).childCount > 1 { break }
                depth -= 1
            }
        }
        if before.isAtom && cut$.depth == cursor$.depth - 1 {
            return try extended(state) { try $0.delete(cut$.pos - before.nodeSize, cut$.pos) }
        }
        return nil
    }

    static func joinForward(_ state: PMState) throws -> PMState? {
        guard let cursor$ = try cursor(state), cursor$.parent.isTextblock,
              cursor$.parentOffset == cursor$.parent.content.size,
              let cut$ = findCutAfter(cursor$), let after = cut$.nodeAfter else { return nil }
        if let barrier = try deleteBarrier(state, cut$, dir: 1) { return barrier }
        if cursor$.parent.content.size == 0 && (textblockAt(after, start: true) || selectable(after)),
           let step = try pmReplaceStep(state.doc, cursor$.before(), cursor$.after(), .empty),
           step.slice.size < step.to - step.from {
            var transform = state.transform
            let from = transform.steps.count
            try transform.step(step)
            let selection: PMSelection = textblockAt(after, start: true)
                ? findFrom(try transform.doc.resolve(transform.map(cut$.pos, from: from)), 1) ?? .text(0)
                : .node(transform.map(cut$.pos, from: from))
            return PMState(transform: transform, selection: selection)
        }
        if after.isAtom && cut$.depth == cursor$.depth - 1 {
            return try extended(state) { try $0.delete(cut$.pos, cut$.pos + after.nodeSize) }
        }
        return nil
    }

    static func selectNodeBackward(_ state: PMState) throws -> PMState? {
        guard case .text(let head) = state.selection else { return nil }
        let head$ = try state.doc.resolve(head)
        var cut$: PMResolvedPos? = head$
        if head$.parent.isTextblock {
            guard head$.parentOffset == 0 else { return nil }
            cut$ = findCutBefore(head$)
        }
        guard let cut$, let node = cut$.nodeBefore, selectable(node) else { return nil }
        return PMState(transform: state.transform, selection: .node(cut$.pos - node.nodeSize))
    }

    static func selectNodeForward(_ state: PMState) throws -> PMState? {
        guard case .text(let head) = state.selection else { return nil }
        let head$ = try state.doc.resolve(head)
        var cut$: PMResolvedPos? = head$
        if head$.parent.isTextblock {
            guard head$.parentOffset == head$.parent.content.size else { return nil }
            cut$ = findCutAfter(head$)
        }
        guard let cut$, let node = cut$.nodeAfter, selectable(node) else { return nil }
        return PMState(transform: state.transform, selection: .node(cut$.pos))
    }

    /// prosemirror-commands lift, as TipTap's lift(type) once the type is active.
    static func lift(_ state: PMState) throws -> PMState? {
        guard let cursor$ = try cursor(state), let range = cursor$.blockRange(), let target = pmLiftTarget(range) else {
            return nil
        }
        return try extended(state) { try $0.lift(range, target) }
    }

    // MARK: prosemirror-schema-list

    static func liftListItem(_ state: PMState, item: String) throws -> PMState? {
        guard let from$ = try cursor(state),
              let range = from$.blockRange(from$, { $0.childCount > 0 && $0.firstChild?.type.name == item }) else {
            return nil
        }
        if from$.node(range.depth - 1).type.name == item {
            let itemType = from$.node(range.depth - 1).type
            return try extended(state) { transform in
                var range = range
                let commandStart = transform.steps.count
                let end = range.end, endOfList = range.to$.end(range.depth)
                if end < endOfList {
                    try transform.step(.replaceAround(from: end - 1, to: endOfList, gapFrom: end, gapTo: endOfList,
                        slice: PMSlice(PMFragment.from(try itemType.create(nil, PMFragment.from(range.parent.copy()))),
                                       openStart: 1, openEnd: 0), insert: 1, structure: true))
                    range = PMNodeRange(from$: try transform.doc.resolve(range.from$.pos),
                                        to$: try transform.doc.resolve(endOfList), depth: range.depth)
                }
                guard let target = pmLiftTarget(range) else { throw PMReplaceError(message: "No lift target") }
                try transform.lift(range, target)
                let after$ = try transform.doc.resolve(transform.map(end, from: commandStart, assoc: -1) - 1)
                if pmCanJoin(transform.doc, after$.pos), after$.nodeBefore?.type === after$.nodeAfter?.type {
                    try transform.join(after$.pos)
                }
            }
        }
        let list = range.parent
        var transform = state.transform
        let from = transform.steps.count
        var pos = range.end, index = range.endIndex - 1
        while index > range.startIndex {
            pos -= list.child(index).nodeSize
            try transform.delete(pos - 1, pos + 1)
            index -= 1
        }
        let start$ = try transform.doc.resolve(range.start)
        guard let item = start$.nodeAfter, transform.map(range.end, from: from) == range.start + item.nodeSize else { return nil }
        let atStart = range.startIndex == 0, atEnd = range.endIndex == list.childCount
        let parent = start$.node(-1), indexBefore = start$.index(-1)
        guard parent.canReplace(indexBefore + (atStart ? 0 : 1), indexBefore + 1,
                                item.content.append(atEnd ? .empty : PMFragment.from(list))) else { return nil }
        let startPos = start$.pos, endPos = startPos + item.nodeSize
        let sides = (atStart ? PMFragment.empty : PMFragment.from(list.copy(.empty)))
            .append(atEnd ? .empty : PMFragment.from(list.copy(.empty)))
        try transform.step(.replaceAround(from: startPos - (atStart ? 1 : 0), to: endPos + (atEnd ? 1 : 0),
            gapFrom: startPos + 1, gapTo: endPos - 1,
            slice: PMSlice(sides, openStart: atStart ? 0 : 1, openEnd: atEnd ? 0 : 1), insert: atStart ? 0 : 1))
        return PMState(transform: transform, selection: mapped(transform, state.selection, from: from))
    }

    // MARK: TipTap commands and helpers

    private static func active(_ state: PMState, _ name: String) -> Bool {
        guard let pos$ = try? state.doc.resolve(state.head) else { return false }
        return (1...max(1, pos$.depth)).contains { $0 <= pos$.depth && pos$.node($0).type.name == name }
    }

    static func deleteCurrentNode(_ state: PMState) throws -> PMState? {
        let pos$ = try state.doc.resolve(state.head), current = pos$.node()
        guard current.content.size == 0 else { return nil }
        var depth = pos$.depth
        while depth > 0 {
            if pos$.node(depth).type === current.type {
                return try extended(state) { try $0.delete(pos$.before(depth), pos$.after(depth)) }
            }
            depth -= 1
        }
        return nil
    }

    static func clearNodes(_ state: PMState) throws -> PMState {
        var visits: [(PMNode, Int)] = []
        state.doc.content.nodesBetween(state.head, state.head, { node, pos, _, _ in visits.append((node, pos)); return true })
        return try extended(state) { transform in
            let from = transform.steps.count
            for (node, pos) in visits where !node.isText {
                let from$ = try transform.doc.resolve(transform.map(pos, from: from))
                let to$ = try transform.doc.resolve(transform.map(pos + node.nodeSize, from: from))
                guard let range = from$.blockRange(to$) else { continue }
                let target = pmLiftTarget(range)
                if node.isTextblock, let type = try from$.parent.contentMatchAt(from$.index()).defaultType {
                    try transform.setNodeMarkup(range.start, type: type)
                }
                if let target { try transform.lift(range, target) }
            }
        }
    }

    /// TipTap core Keymap's Backspace clearNodes branch for an empty
    /// non-paragraph textblock at the start of the document or an isolating cell.
    static func clearEmptyStart(_ state: PMState) throws -> PMState? {
        guard let anchor$ = try cursor(state) else { return nil }
        let parent = anchor$.parent, head = anchor$.pos
        let parent$ = parent.isTextblock && head > 0 ? try state.doc.resolve(head - 1) : anchor$
        let parentPos = anchor$.pos - anchor$.parentOffset
        let atStart: Bool
        if parent$.parent.type.flag("isolating") && parent$.parent.childCount == 1 { atStart = parentPos == anchor$.pos }
        else if case .text(let first)? = findSelectionIn(state.doc, 0, 0, 1) { atStart = first == head }
        else { atStart = false }
        guard parent.isTextblock, parent.content.size == 0, atStart, parent.type.name != "paragraph" else { return nil }
        return try clearNodes(state)
    }

    static func hoistBranchingNestedList(_ state: PMState, item: String, wrappers: [String]) throws -> PMState? {
        guard let from$ = try cursor(state), from$.parent.isTextblock,
              from$.parentOffset == from$.parent.content.size else { return nil }
        var itemDepth = -1, depth = from$.depth
        while depth > 0 {
            if from$.node(depth).type.name == item { itemDepth = depth; break }
            depth -= 1
        }
        guard itemDepth >= 0 else { return nil }
        let listItem = from$.node(itemDepth), indexInItem = from$.index(itemDepth)
        guard indexInItem + 1 < listItem.childCount else { return nil }
        let nextChild = listItem.child(indexInItem + 1)
        guard wrappers.contains(nextChild.type.name),
              nextChild.content.children.contains(where: { $0.type.name == item && $0.childCount > 1 }),
              let nested = try state.doc.resolve(from$.after()).nodeAfter, wrappers.contains(nested.type.name),
              nested.childCount > 0 else { return nil }
        let nestedPos = from$.after(), insertPos = from$.after(itemDepth)
        return try extended(state) { transform in
            let from = transform.steps.count
            try transform.delete(nestedPos, nestedPos + nested.nodeSize)
            try transform.insert(transform.map(insertPos, from: from), nested.content)
        }
    }

    static func joinItemForward(_ state: PMState) throws -> PMState? {
        guard let point = pmJoinPoint(state.doc, state.head, dir: 1) else { return nil }
        do { return try extended(state) { try $0.join(point, depth: 2) } }
        catch is PMReplaceError { return nil }
    }

    /// One command in a TipTap chain: TipTap rebuilds the chain state from the
    /// live transaction for each command. ProseMirror commands receive it as
    /// their state; TipTap commands also read the editor's committed state.
    private enum ChainCommand {
        case prosemirror(PMCommand)
        case live((_ original: PMState, _ live: PMState) throws -> PMState?)
    }

    /// TipTap chain().a().b().run(): the transaction is dispatched even when
    /// a command returns false; the result is whether every command succeeded.
    private static func chain(_ state: PMState, _ commands: [ChainCommand]) throws -> (PMState, Bool) {
        var live = state, success = true
        for command in commands {
            let next: PMState?
            switch command {
            case .prosemirror(let run): next = try run(live)
            case .live(let run): next = try run(state, live)
            }
            if let next { live = next } else { success = false }
        }
        return (live, success)
    }

    // MARK: ListKeymap (TipTap extension-list)

    private static func listBackspace(_ state: PMState, item: String, wrappers: [String]) throws -> (PMState, Bool) {
        guard let anchor$ = try cursor(state) else { return (state, false) }
        let previous = try state.doc.resolve(max(0, anchor$.pos - 2)).node()
        if !active(state, item) && wrappers.contains(previous.type.name) {
            let list$ = try state.doc.resolve(anchor$.before() - 1)
            var last: Int?
            list$.node().content.nodesBetween(0, list$.node().content.size, { node, pos, _, _ in
                if node.type.name == item { last = pos }
                return true
            })
            guard let last else { return (state, false) }
            let lastItem$ = try state.doc.resolve(list$.start() + last + 1)
            let cutFrom = anchor$.start() - 1, cutTo = anchor$.end() + 1, target = lastItem$.end()
            let cut = ChainCommand.live { original, live in
                let slice = try original.doc.slice(cutFrom, cutTo)
                var transform = live.transform
                let from = transform.steps.count
                try transform.deleteRange(cutFrom, cutTo)
                let newPos = transform.map(target, from: from)
                try transform.insert(newPos, slice.content)
                return PMState(transform: transform, selection: .text(max(newPos - 1, 0)))
            }
            return try chain(state, [cut, .prosemirror(joinForward)])
        }
        guard active(state, item), anchor$.parentOffset == 0 else { return (state, false) }
        let itemDepth = anchor$.depth - 1
        guard itemDepth >= 0, anchor$.node(itemDepth).type.name == item, anchor$.index(itemDepth) == 0 else {
            return (state, false)
        }
        return try chain(state, [.prosemirror { try liftListItem($0, item: item) }])
    }

    private static func listItemPos(_ state: PMState, item: String) throws -> (pos: Int, depth: Int)? {
        let from$ = try state.doc.resolve(state.head)
        var depth = from$.depth, pos = from$.pos
        while depth > 0 {
            if from$.node(depth).type.name == item { return (pos, depth) }
            depth -= 1
            pos -= 1
        }
        return nil
    }

    private static func nodeDepth(_ state: PMState, item: String, at pos: Int) throws -> Int {
        let pos$ = try state.doc.resolve(pos)
        var depth = 20
        while depth > 0 {
            if depth <= pos$.depth, pos$.node(depth).type.name == item { return depth }
            depth -= 1
        }
        return 0
    }

    private static func listDelete(_ state: PMState, item: String) throws -> (PMState, Bool) {
        guard active(state, item), let anchor$ = try cursor(state) else { return (state, false) }
        var depth = anchor$.depth, itemStart: Int?
        while depth > 0 {
            if anchor$.node(depth).type.name == item { itemStart = anchor$.before(depth); break }
            depth -= 1
        }
        guard let itemStart, anchor$.pos + 1 == (try state.doc.resolve(itemStart + 1)).end() else { return (state, false) }
        guard let position = try listItemPos(state, item: item) else { return (state, false) }
        let nextDepth = try nodeDepth(state, item: item, at: position.pos + 4)
        if nextDepth > 0 && nextDepth > position.depth {
            let target = state.head + 4
            let focus = ChainCommand.live { _, live in
                PMState(transform: live.transform, selection: .text(min(max(target, 0), live.doc.content.size)))
            }
            let liftItem = ChainCommand.prosemirror { state in active(state, item) ? try lift(state) : nil }
            return try chain(state, [focus, liftItem, .prosemirror(joinBackward)])
        }
        if nextDepth > 0 && nextDepth < position.depth {
            return try chain(state, [.prosemirror(joinForward), .prosemirror(joinBackward)])
        }
        if let joined = try joinItemForward(state) { return (joined, true) }
        return (state, false)
    }

    // MARK: Keymaps in browser plugin order

    private static let lists: [(item: String, wrappers: [String])] = [
        ("listItem", ["bulletList", "orderedList"]), ("taskItem", ["taskList"]),
    ]

    /// Runs `first`-style handlers, carrying state changes made by chains that return false.
    private static func run(_ state: PMState, _ handlers: [(PMState) throws -> (PMState, Bool)]) throws -> PMState {
        var state = state
        for handler in handlers {
            let (next, handled) = try handler(state)
            state = next
            if handled { break }
        }
        return state
    }

    private static func first(_ commands: [PMCommand]) -> (PMState) throws -> (PMState, Bool) {
        { state in
            for command in commands { if let next = try command(state) { return (next, true) } }
            return (state, false)
        }
    }

    static func backspace(_ state: PMState) throws -> PMState {
        try run(state, [
            first([codeBlockBackspace]),
            { state in
                var state = state, handled = false
                for list in lists {
                    let (next, done) = try listBackspace(state, item: list.item, wrappers: list.wrappers)
                    state = next
                    handled = handled || done
                }
                return (state, handled)
            },
            first([blockquoteBackspace]),
            first([clearEmptyStart, joinBackward, selectNodeBackward]),
        ])
    }

    static func delete(_ state: PMState) throws -> PMState {
        try run(state, [
            first([{ try hoistBranchingNestedList($0, item: "taskItem", wrappers: ["taskList"]) }]),
            first([{ try hoistBranchingNestedList($0, item: "listItem", wrappers: ["bulletList", "orderedList"]) }]),
            { state in
                var state = state, handled = false
                for list in lists {
                    let (next, done) = try listDelete(state, item: list.item)
                    state = next
                    handled = handled || done
                }
                return (state, handled)
            },
            first([deleteCurrentNode, joinForward, selectNodeForward]),
        ])
    }

    /// Blockquote handleBackspace (TipTap extension-blockquote).
    static func blockquoteBackspace(_ state: PMState) throws -> PMState? {
        guard let from$ = try cursor(state), from$.parentOffset == 0, from$.depth - 1 >= 0 else { return nil }
        let parent = from$.node(from$.depth - 1), index = from$.index(from$.depth - 1)
        guard index > 0 else { return nil }
        if parent.type.name == "blockquote" { return try lift(state) }
        let previous = parent.child(index - 1)
        guard previous.type.name == "blockquote", previous.lastChild?.isTextblock == true else { return nil }
        let targetPos = from$.before() - 2, content = from$.parent.content
        var transform = state.transform
        try transform.replace(targetPos, from$.after(), PMSlice(content, openStart: 0, openEnd: 0))
        return PMState(transform: transform, selection: .text(targetPos + content.size))
    }

    /// CodeBlock Backspace: clear an empty code block, or one at the document start.
    static func codeBlockBackspace(_ state: PMState) throws -> PMState? {
        guard let anchor$ = try cursor(state), anchor$.parent.type.name == "codeBlock",
              anchor$.pos == 1 || anchor$.parent.content.size == 0 else { return nil }
        return try clearNodes(state)
    }
}

/// prosemirror-transform joinPoint.
func pmJoinPoint(_ doc: PMNode, _ pos: Int, dir: Int = -1) -> Int? {
    guard let pos$ = try? doc.resolve(pos) else { return nil }
    var pos = pos, d = pos$.depth
    while true {
        var before: PMNode?, after: PMNode?, index = pos$.index(d)
        if d == pos$.depth {
            before = pos$.nodeBefore
            after = pos$.nodeAfter
        } else if dir > 0 {
            before = pos$.node(d + 1)
            index += 1
            after = pos$.node(d).maybeChild(index)
        } else {
            before = pos$.node(d).maybeChild(index - 1)
            after = pos$.node(d + 1)
        }
        if let before, !before.isTextblock, pmJoinable(before, after), pos$.node(d).canReplace(index, index + 1) {
            return pos
        }
        if d == 0 { break }
        pos = dir < 0 ? pos$.before(d) : pos$.after(d)
        d -= 1
    }
    return nil
}

extension PMStep {
    var from: Int {
        switch self {
        case let .replace(from, _, _, _): return from
        case let .replaceAround(from, _, _, _, _, _, _): return from
        }
    }

    var to: Int {
        switch self {
        case let .replace(_, to, _, _): return to
        case let .replaceAround(_, to, _, _, _, _, _): return to
        }
    }

    var slice: PMSlice {
        switch self {
        case let .replace(_, _, slice, _): return slice
        case let .replaceAround(_, _, _, _, slice, _, _): return slice
        }
    }
}

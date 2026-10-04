import * as Y from 'yjs'

// Identity only. The host binds selections to a document and determines edit intent.
const MAX_RUNS = 4096, MAX_UNITS = 131072
const integer = value => Number.isSafeInteger(value) && value >= 0
function keys(value, expected) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).sort().join(',') !== [...expected].sort().join(',')) throw Error('Invalid text item fields')
}
function selection(value) {
  keys(value, ['runs'])
  if (!Array.isArray(value.runs) || value.runs.length > MAX_RUNS) throw Error('Invalid text item selection')
  let total = 0
  const intervals = new Map()
  return value.runs.map(run => {
    keys(run, ['item', 'type', 'count'])
    keys(run.item, ['client', 'clock']); keys(run.type, ['client', 'clock'])
    if (!integer(run.count) || run.count === 0 || (total += run.count) > MAX_UNITS) throw Error('Invalid text item run bounds')
    if ([run.item, run.type].some(id => !integer(id.client) || !integer(id.clock) || id.clock >= 2 ** 32) ||
        run.item.clock + run.count > 2 ** 32) throw Error('Invalid text item identity')
    const position = Y.createRelativePositionFromJSON({ item: run.item, type: run.type, assoc: 0 })
    const type = Y.createRelativePositionFromJSON({ type: run.type, assoc: 0 })
    const client = position.item.client, start = position.item.clock, end = start + run.count
    const known = intervals.get(client) || []
    if (known.some(([a, b]) => start < b && end > a)) throw Error('Overlapping text item identity')
    known.push([start, end]); intervals.set(client, known)
    return { position, typePosition: type, count: run.count }
  })
}
function plain(type) {
  return type.toDelta().map(part => {
    if (typeof part.insert !== 'string') throw Error('Text item atoms are unsupported')
    return part.insert
  }).join('')
}
function validUnicode(text) {
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i)
    if (code >= 0xD800 && code <= 0xDBFF) {
      const next = text.charCodeAt(++i)
      if (!(next >= 0xDC00 && next <= 0xDFFF)) throw Error('Text item selection splits a surrogate pair')
    } else if (code >= 0xDC00 && code <= 0xDFFF) throw Error('Text item selection splits a surrogate pair')
  }
}
function reachable(root) {
  const found = new Map(), pending = [[root, []]]
  let visited = 0
  while (pending.length) {
    const [type, path] = pending.pop()
    if (++visited > 65536 || path.length > 128) throw Error('Text item document traversal limit exceeded')
    if (type instanceof Y.XmlText) found.set(type, path)
    else if (type instanceof Y.XmlFragment) {
      if (visited + pending.length + type.length > 65536) throw Error('Text item document traversal limit exceeded')
      const children = type.toArray()
      for (let i = children.length - 1; i >= 0; i--) pending.push([children[i], [...path, i]])
    }
  }
  return found
}
export function captureTextItems(root, input) {
  keys(input, ['path', 'index', 'length'])
  if (!Array.isArray(input.path) || input.path.length > 128 || input.path.some(i => !integer(i)) ||
      !integer(input.index) || !integer(input.length) || input.length > MAX_UNITS ||
      !Number.isSafeInteger(input.index + input.length)) throw Error('Invalid text item range')
  let leaf = root
  for (const index of input.path) {
    if (!(leaf instanceof Y.XmlFragment) || index >= leaf.length) throw Error('Invalid text item path')
    leaf = leaf.get(index)
  }
  if (!(leaf instanceof Y.XmlText) || input.index + input.length > leaf.length) throw Error('Expected text item leaf range')
  validUnicode(plain(leaf).slice(input.index, input.index + input.length))
  const runs = []
  let previous = null
  for (let index = input.index; index < input.index + input.length; index++) {
    const position = Y.createRelativePositionFromTypeIndex(leaf, index, 0)
    if (previous && previous.item.client === position.item.client && previous.item.clock + runs.at(-1).count === position.item.clock) runs.at(-1).count++
    else {
      if (runs.length === MAX_RUNS) throw Error('Too many text item runs')
      runs.push({ item: { client: position.item.client, clock: position.item.clock },
        type: { client: position.type.client, clock: position.type.clock }, count: 1 }); previous = position
    }
  }
  const result = { runs }
  selection(result)
  return result
}
export function resolveTextItems(doc, root, input) {
  const runs = selection(input), paths = reachable(root), units = [], unavailableRuns = []
  const text = new Map()
  let collapsedUnits = 0
  for (const [runIndex, run] of runs.entries()) {
    const { position, typePosition, count } = run
    const type = Y.createAbsolutePositionFromRelativePosition(typePosition, doc, false)?.type
    if (!type || !paths.has(type)) { unavailableRuns.push(runIndex); continue }
    if (!text.has(type)) text.set(type, plain(type))
    const pending = []
    let deleted = 0, unavailable = false
    for (let offset = 0; offset < count; offset++) {
      const item = { client: position.item.client, clock: position.item.clock + offset }
      const relative = assoc => Y.createRelativePositionFromJSON({ type: position.type, item, assoc })
      const a = Y.createAbsolutePositionFromRelativePosition(relative(0), doc, false)
      const b = Y.createAbsolutePositionFromRelativePosition(relative(-1), doc, false)
      if (!a || !b) { unavailable = true; break }
      // Item references alone ignore the supplied type in Yjs. Validate the binding explicitly.
      if (a.type !== type || b.type !== type) throw Error('Text item type mismatch')
      if (a.index === b.index) { deleted++; continue }
      if (b.index !== a.index + 1) throw Error('Invalid text item extent')
      const actual = Y.createRelativePositionFromTypeIndex(type, a.index, 0).item
      if (!actual || actual.client !== item.client || actual.clock !== item.clock) throw Error('Text item identity mismatch')
      pending.push({ path: paths.get(type), index: a.index, length: 1, text: text.get(type).slice(a.index, b.index) })
    }
    if (unavailable) unavailableRuns.push(runIndex)
    else { for (const unit of pending) units.push(unit); collapsedUnits += deleted }
  }
  // Output follows current document order even when input runs are reordered.
  units.sort((a, b) => {
    for (let i = 0; i < Math.min(a.path.length, b.path.length); i++) if (a.path[i] !== b.path[i]) return a.path[i] - b.path[i]
    return a.path.length - b.path.length || a.index - b.index
  })
  const segments = []
  for (const unit of units) {
    const last = segments.at(-1)
    if (last && last.index + last.length === unit.index && JSON.stringify(last.path) === JSON.stringify(unit.path)) { last.length++; last.text += unit.text }
    else {
      if (segments.length === MAX_RUNS) throw Error('Too many resolved text item segments')
      segments.push({ ...unit })
    }
  }
  for (const segment of segments) validUnicode(segment.text)
  return { segments, collapsedUnits, unavailableRuns }
}

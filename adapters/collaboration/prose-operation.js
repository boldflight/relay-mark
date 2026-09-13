import * as Y from 'yjs'

// Canonical prose mutation shared by caller-owned document adapters.
// The host owns the document, root, transaction origin and UndoManager.
export function node(value) {
  if (value.kind === 'text') {
    const text = new Y.XmlText()
    text.applyDelta(value.delta || [])
    return text
  }
  if (value.kind !== 'element' || typeof value.name !== 'string') throw Error('Invalid XML node')
  const element = new Y.XmlElement(value.name)
  for (const [key, attribute] of Object.entries(value.attributes || {})) element.setAttribute(key, attribute)
  element.insert(0, (value.children || []).map(node))
  return element
}
export function snapshot(value) {
  if (value instanceof Y.XmlText) return { kind: 'text', delta: value.toDelta() }
  if (value instanceof Y.XmlElement) return {
    kind: 'element', name: value.nodeName, attributes: value.getAttributes(), children: value.toArray().map(snapshot)
  }
  return { kind: 'fragment', children: value.toArray().map(snapshot) }
}
export function range(target, index, length = 0) {
  if (!Number.isInteger(index) || !Number.isInteger(length) || index < 0 || length < 0 || index + length > target.length) throw Error('Invalid UTF-16 range')
}
const hardBreakCharacter = '\u2028'
function inlineLength(p) {
  if (p.nodeName === 'horizontalRule') return 1
  return p.toArray().reduce((n, child) => n + (child instanceof Y.XmlText ? child.length : 1), 0)
}
export function proseBlocks(documentRoot) {
  const blocks = []
  function walk(parent) {
    for (const p of parent.toArray()) {
      if (!(p instanceof Y.XmlElement)) throw Error('Unsupported prose structure')
      const attrs = p.getAttributes()
      if (['paragraph', 'heading', 'codeBlock', 'horizontalRule'].includes(p.nodeName)) {
        const allowed = p.nodeName === 'heading' ? ['level'] : p.nodeName === 'codeBlock' ? ['language'] : []
        if (Object.keys(attrs).some(key => !allowed.includes(key))) throw Error('Unsupported prose attributes')
        if (p.nodeName === 'horizontalRule' && p.length) throw Error('Unsupported rule content')
        for (const child of p.toArray()) {
          if (child instanceof Y.XmlText) continue
          if (p.nodeName !== 'codeBlock' && child instanceof Y.XmlElement && child.nodeName === 'hardBreak' && !child.length && !Object.keys(child.getAttributes()).length) continue
          throw Error('Unsupported prose inline content')
        }
        blocks.push({ p, length: inlineLength(p) })
      } else if (['blockquote', 'bulletList', 'orderedList', 'listItem'].includes(p.nodeName)) {
        if (Object.keys(attrs).some(key => p.nodeName !== 'orderedList' || key !== 'start')) throw Error('Unsupported prose container attributes')
        if (['bulletList', 'orderedList'].includes(p.nodeName) && p.toArray().some(n => n.nodeName !== 'listItem')) throw Error('Unsupported list children')
        walk(p)
      } else throw Error('Unsupported prose structure')
    }
  }
  walk(documentRoot)
  return blocks
}
function removeBlock(block, documentRoot) {
  let element = block.p
  while (element && element !== documentRoot) {
    const parent = element.parent
    parent.delete(parent.toArray().indexOf(element), 1)
    if (parent.length || parent === documentRoot) return
    element = parent
  }
}
function sliceInline(p, start) {
  const result = []
  for (const child of p.toArray()) {
    const length = child instanceof Y.XmlText ? child.length : 1
    if (start >= length) { start -= length; continue }
    if (child instanceof Y.XmlText) {
      const delta = []
      for (const run of child.toDelta()) {
        if (typeof run.insert !== 'string') throw Error('Unsupported text embed')
        if (start >= run.insert.length) { start -= run.insert.length; continue }
        delta.push({ ...run, insert: run.insert.slice(start) }); start = 0
      }
      result.push({ kind: 'text', delta })
    } else { result.push(snapshot(child)); start = 0 }
  }
  return result
}
function deleteInline(p, start, end) {
  let offset = 0
  const spans = p.toArray().map(child => {
    const length = child instanceof Y.XmlText ? child.length : 1
    const result = { child, start: offset, end: offset + length }; offset += length; return result
  })
  for (const span of spans.reverse()) {
    const from = Math.max(start, span.start), to = Math.min(end, span.end)
    if (to <= from) continue
    if (span.child instanceof Y.XmlText) span.child.delete(from - span.start, to - from)
    else p.delete(p.toArray().indexOf(span.child), 1)
  }
}
function insertInline(p, offset, content, attributes, inserted = null) {
  if (!content) return
  let index = 0, target = null, local = offset
  const children = p.toArray()
  for (; index < children.length; index++) {
    const child = children[index], length = child instanceof Y.XmlText ? child.length : 1
    if (child instanceof Y.XmlText && local <= length) { target = child; break }
    if (local === 0) break
    local -= length
  }
  if (!target) { target = new Y.XmlText(); p.insert(index, [target]); local = 0 }
  // Yjs may add null resets to the supplied attribute map. Do not mutate
  // the canonical operation evidence or reuse those resets on another leaf.
  const parts = p.nodeName === 'codeBlock' ? [content] : content.split(hardBreakCharacter)
  if (parts.length === 1) { target.insert(local, content, { ...attributes }); inserted?.(target, local, content.length); return }
  // Splitting an inline text to insert a break moves only that text's suffix;
  // all other XmlText siblings and the block itself retain their Yjs identities.
  const tail = sliceInline({ toArray: () => [target] }, local)
  target.delete(local, target.length - local)
  target.insert(local, parts[0], { ...attributes })
  const additions = []
  for (const part of parts.slice(1)) {
    additions.push(new Y.XmlElement('hardBreak'))
    const text = new Y.XmlText(); text.insert(0, part, { ...attributes }); additions.push(text)
  }
  for (const item of tail) additions.push(node(item))
  p.insert(p.toArray().indexOf(target) + 1, additions)
}
function paragraph(content, attributes, tail = [], hooks = null) {
  const p = new Y.XmlElement('paragraph')
  // Populate after integration: insertInline relies on live Yjs lengths.
  return { p, populate: () => {
    insertInline(p, 0, content, attributes, hooks?.inserted)
    const copied = tail.map(node); p.insert(p.length, copied)
    if (copied.length) hooks?.copied(copied)
  } }
}
export function replaceProse(input, targetDoc, targetRoot, origin, hooks = null) {
  const blocks = proseBlocks(targetRoot)
  if (!blocks.length) throw Error('Empty document must be enrolled with a paragraph')
  const total = blocks.reduce((n, b) => n + b.length, blocks.length - 1)
  range({ length: total }, input.start, input.end - input.start)
  function locate(offset) {
    for (let i = 0; i < blocks.length; i++) {
      if (offset <= blocks[i].length) return [i, offset]
      offset -= blocks[i].length + 1
    }
    throw Error('Invalid prose offset')
  }
  const [first, start] = locate(input.start), [last, end] = locate(input.end)
  const firstRule = blocks[first].p.nodeName === 'horizontalRule'
  const lastRule = blocks[last].p.nodeName === 'horizontalRule'
  const lines = first === last && blocks[first].p.nodeName === 'codeBlock' ? [input.text] : input.text.split('\n')
  const tail = lastRule ? [] : sliceInline(blocks[last].p, end)
  // A cross-block merge must not smuggle inline marks/breaks into literal code.
  if (first !== last && blocks[first].p.nodeName === 'codeBlock' && tail.some(n => n.kind !== 'text' || n.delta.some(r => Object.keys(r.attributes || {}).length))) throw Error('Cannot merge marked prose into a code block')
  hooks?.tail(blocks[last].p, end, first !== last || lines.length !== 1)
  targetDoc.transact(() => {
    if (first === last && !firstRule && lines.length === 1) {
      deleteInline(blocks[first].p, start, end)
      insertInline(blocks[first].p, start, input.text, input.attributes || {}, hooks?.inserted)
      return
    }
    let destination = blocks[first].p
    if (firstRule) {
      if (first === last && start === end && !input.text) return
      const parent = destination.parent, index = parent.toArray().indexOf(destination) + (start === 1 ? 1 : 0)
      const created = new Y.XmlElement('paragraph'); parent.insert(index, [created]); destination = created
      if (start === 0 && (first !== last || end === 1)) removeBlock(blocks[first], targetRoot)
    } else deleteInline(destination, start, inlineLength(destination))
    for (let i = last; i > first; i--) {
      if (i === last && lastRule && end === 0) continue
      removeBlock(blocks[i], targetRoot)
    }
    insertInline(destination, firstRule ? 0 : start, lines[0], input.attributes || {}, hooks?.inserted)
    if (lines.length === 1) {
      const copied = tail.map(node); destination.insert(destination.length, copied)
      if (copied.length) hooks?.copied(copied)
    }
    else {
      const additions = lines.slice(1).map((line, i) => paragraph(line, input.attributes || {}, i === lines.length - 2 ? tail : [], hooks))
      const parent = destination.parent
      if (parent instanceof Y.XmlElement && parent.nodeName === 'listItem' && parent.length === 1) {
        const list = parent.parent
        const items = additions.map(({p}) => { const item = new Y.XmlElement('listItem'); item.insert(0, [p]); return item })
        list.insert(list.toArray().indexOf(parent) + 1, items)
      } else parent.insert(parent.toArray().indexOf(destination) + 1, additions.map(a => a.p))
      additions.forEach(a => a.populate())
    }
  }, origin)
}

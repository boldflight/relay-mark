import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {relayMarkToProseMirror, proseMirrorToRelayMark} from '../src/document-adapter.js'
import {renderDocument, projectDocumentMarkdown} from '../src/document-source.js'

// Shared with the Elixir adapter: one meaning of an agent-written run.
const fixture = JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/ai-authored-mark.json', import.meta.url)))

test('ai_authored maps between AST and ProseMirror, renders marked, and leaves only the words in Markdown', () => {
  assert.deepEqual(relayMarkToProseMirror(fixture.ast), fixture.prosemirror)
  assert.deepEqual(proseMirrorToRelayMark(fixture.prosemirror), fixture.ast)
  assert.equal(renderDocument(fixture.ast), fixture.html)
  assert.equal(projectDocumentMarkdown(fixture.ast), fixture.markdown)
})

test('ai_authored needs its run', () => {
  const run = fixture.ast.blocks[0].content[2]
  for (const broken of [{...run, run_id: ''}, {type: run.type, content: run.content}, {...run, extra: 1}]) {
    const ast = structuredClone(fixture.ast)
    ast.blocks[0].content[2] = broken
    assert.throws(() => relayMarkToProseMirror(ast))
  }
})

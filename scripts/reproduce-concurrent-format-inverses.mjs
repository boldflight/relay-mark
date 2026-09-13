// Acceptance reproduction: exits 1 until independent inverses converge in both orders.
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'
import { webcrypto } from 'node:crypto'

const fixture = JSON.parse(readFileSync(new URL('../test/fixtures/concurrent-format-inverses.json', import.meta.url)))
const bundle = readFileSync(new URL('../adapters/swift/Sources/RelayMarkCollaboration/Resources/yjs-runtime.js', import.meta.url), 'utf8')
const outcomes = []
for (const order of [['aUndo', 'bUndo'], ['bUndo', 'aUndo']]) {
  const context = { crypto: webcrypto, TextEncoder, TextDecoder, console,
    setTimeout: () => 0, clearTimeout() {}, setInterval: () => 0, clearInterval() {} }
  runInNewContext(bundle, context)
  const call = (name, args = null) => JSON.parse(context.relayCollaborationCall(name, JSON.stringify(args)))
  call('apply', fixture.baseline)
  const expected = call('snapshot'), scope = 'same-qualified-test'
  let replay = call('createAttributionReplay', { scope_token: scope, binding: fixture.binding })
  let error = null, accepted = 0
  for (const name of ['add', 'clear', ...order]) {
    try {
      replay = call('applyAttributionRecord', { replay_json: replay.replay_json,
        expected: { scope_token: scope, binding: fixture.binding, replay_sha256: replay.replay_sha256, cut: replay.cut },
        record_json: JSON.stringify(fixture.records[name]) })
      accepted++
    } catch (failure) { error = failure.message; break }
  }
  const snapshot = call('snapshot')
  const converged = accepted === 4 && JSON.stringify(snapshot) === JSON.stringify(expected)
  outcomes.push({ order, accepted, error, converged, snapshot })
}
console.log(JSON.stringify(outcomes, null, 2))
if (!outcomes.every(value => value.converged)) process.exitCode = 1

import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fixtureURL, swiftFixtureURL, generate, verify } from '../scripts/collaboration-conformance.mjs'

test('portable collaboration fixtures converge and Swift resource remains identical', () => {
  const json = readFileSync(fixtureURL, 'utf8')
  assert.equal(readFileSync(swiftFixtureURL, 'utf8'), json)
  const fixture = JSON.parse(json)
  assert.deepEqual(generate(), fixture)
  verify(fixture)
})

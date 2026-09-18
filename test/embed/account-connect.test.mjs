import {test} from 'node:test'
import assert from 'node:assert/strict'
import {createHash} from 'node:crypto'
import {startConnection, consumeConnection} from '../../assets/embed/account-connect.mjs'

const memory = () => {
  const values = new Map()
  return {getItem: k => values.get(k), setItem: (k, v) => values.set(k, v), removeItem: k => values.delete(k)}
}

test('connection sends only a challenge and state; verifier and invitation remain in browser storage', async () => {
  const storage = memory()
  const url = new URL(await startConnection({service: 'https://fluently.test', project: 'project-1',
    returnTo: 'https://customer.test/checkout?private=query#tab=cart', storage, key: 'pending', invitation: 'guest-secret', hostKey: 'session-A'}))
  const pending = JSON.parse(storage.getItem('pending'))
  assert.equal(url.origin, 'https://fluently.test')
  assert.equal(url.searchParams.get('return_to'), 'https://customer.test/checkout?private=query#tab=cart')
  assert.equal(pending.returnTo, 'https://customer.test/checkout?private=query#tab=cart')
  assert.equal(url.searchParams.get('challenge'), createHash('sha256').update(pending.verifier).digest('base64url'))
  assert.equal(url.searchParams.get('state'), pending.state)
  assert.ok(!url.href.includes(pending.verifier))
  assert.ok(!url.href.includes('guest-secret'))
  assert.deepEqual(consumeConnection({storage, key: 'pending', state: pending.state, hostKey: 'session-A'}), pending)
  assert.equal(consumeConnection({storage, key: 'pending', state: pending.state, hostKey: 'session-A'}), null)
})

test('wrong state, expiry, changed host user, and corrupt pending data reject the callback', () => {
  for (const change of [{state: 'wrong'}, {hostKey: 'other-user'}, {now: 700001}, {now: 99999}]) {
    const storage = memory()
    storage.setItem('pending', JSON.stringify({state: 'expected', hostKey: 'session-A', created: 100000}))
    assert.equal(consumeConnection({storage, key: 'pending', state: 'expected', hostKey: 'session-A', now: 100001, ...change}), null)
    assert.equal(storage.getItem('pending'), undefined)
  }
  const storage = memory()
  storage.setItem('pending', 'invalid-json')
  assert.equal(consumeConnection({storage, key: 'pending', state: 'expected', hostKey: ''}), null)
})

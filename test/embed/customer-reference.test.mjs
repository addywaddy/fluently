import {test} from 'node:test'
import assert from 'node:assert/strict'
import {customerReference, hostIdentityKey} from '../../assets/embed/customer-reference.mjs'

function fixture(value, {count = 1, excluded = false} = {}) {
  const calls = []
  return {calls, root: {querySelectorAll(selector) {
    calls.push(selector)
    if (selector === '[') throw new Error('invalid selector')
    return Array.from({length: count}, () => ({
      closest: () => excluded,
      getAttribute: attribute => {calls.push(attribute); return value},
      get textContent() { throw new Error('Must not read DOM text') },
      get value() { throw new Error('Must not read form values') }
    }))
  }}}
}
const config = {userSelector: '#customer', userAttribute: 'data-customer-ref'}

test('only reads the configured data attribute; disabled mode never queries DOM', () => {
  const {root, calls} = fixture('abc_123-XYZ')
  assert.deepEqual(customerReference(root, {}), {state: 'disabled', value: null})
  assert.deepEqual(calls, [])
  assert.deepEqual(customerReference(root, config), {state: 'present', value: 'abc_123-XYZ'})
  assert.deepEqual(calls, ['#customer', 'data-customer-ref'])
  assert.equal(customerReference(root, {userSelector: '#customer'}).value, 'abc_123-XYZ')
  assert.equal(calls.at(-1), 'data-fluently-user-ref')
})

test('missing, excluded, ambiguous and invalid references never capture a value', () => {
  for (const [value, options] of [[null, {}], ['', {}], ['abc', {count: 0}], ['abc', {count: 2}], ['abc', {excluded: true}],
    ['a'.repeat(201), {}], ['customer@example.test', {}], ['with spaces', {}], ['line\nbreak', {}], ['trailing\n', {}], ['trailing\r', {}], ['é', {}]]) {
    assert.equal(customerReference(fixture(value, options).root, config).value, null)
  }
  for (const settings of [{...config, userSelector: '['}, {...config, userSelector: 'a'.repeat(257)}, {...config, userAttribute: 'value'}, {...config, userAttribute: 'textContent'}]) {
    assert.equal(customerReference(fixture('secret').root, settings).state, 'invalid')
  }
  assert.equal(customerReference(fixture('a'.repeat(200)).root, config).value.length, 200)
})

test('session binding changes on reference arrival, removal, replacement or configuration change', () => {
  const present = hostIdentityKey(fixture('user-A').root, config)
  for (const other of [hostIdentityKey(fixture('user-B').root, config), hostIdentityKey(fixture(null).root, config),
    hostIdentityKey(fixture('user-A').root, {...config, sessionKey: 'new-login'}),
    hostIdentityKey(fixture('user-A').root, {...config, userSelector: '#different'})]) assert.notEqual(present, other)
  assert.equal(hostIdentityKey(fixture('user-A').root, config), present)
  assert.equal(hostIdentityKey(fixture(null).root, {sessionKey: 'existing-session'}), 'existing-session')
})

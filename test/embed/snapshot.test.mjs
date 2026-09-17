import {test} from 'node:test'
import assert from 'node:assert/strict'
import {snapshotNodeAllowed, snapshotSize, privateSelector, snapshotUnavailableReason} from '../../assets/embed/snapshot-policy.mjs'
const node = extra => ({nodeType: 1, tagName: 'DIV', closest: () => null, querySelector: () => null, ...extra})
test('capture excludes private ancestors, controls, shadow roots, and unsafe SVG subtrees', () => {
  assert.equal(snapshotNodeAllowed(node()), true)
  assert.equal(snapshotNodeAllowed(node({closest: () => ({})})), false)
  assert.equal(snapshotNodeAllowed(node({shadowRoot: {}})), false)
  assert.equal(snapshotNodeAllowed(node({tagName: 'svg', querySelector: () => ({})})), false)
  assert.equal(snapshotNodeAllowed({nodeType: 3}), true)
  assert.equal(snapshotNodeAllowed({nodeType: 8}), false)
  for (const selector of ['[data-feedback-exclude]', '[data-feedback-mask]', 'input', 'textarea', 'select', 'iframe', 'canvas', 'slot']) assert.ok(privateSelector.includes(selector))
})
test('snapshots preserve aspect ratio and bound pixel dimensions', () => {
  assert.deepEqual(snapshotSize(2400, 800), {width: 1200, height: 400})
  assert.deepEqual(snapshotSize(40, 30), {width: 40, height: 30})
  for (const size of [0, -1, Infinity, 8001]) assert.throws(() => snapshotSize(size, 100))
})


test('preflight disables unsupported captures while ordinary images remain supported', () => {
  globalThis.getComputedStyle = element => element.style
  const target = node({isConnected: true, parentElement: null, querySelectorAll: () => [],
    style: {display: 'block', visibility: 'visible', opacity: '1'},
    getBoundingClientRect: () => ({width: 40, height: 40})})
  assert.equal(snapshotUnavailableReason({...target, tagName: 'IMG'}), null)
  assert.match(snapshotUnavailableReason({...target, shadowRoot: {}}), /unsupported/)
  assert.match(snapshotUnavailableReason({...target, closest: () => ({})}), /private/)
  assert.match(snapshotUnavailableReason({...target, isConnected: false}), /no longer/)
  assert.match(snapshotUnavailableReason({...target, hidden: true}), /hidden/)
  assert.match(snapshotUnavailableReason({...target, namespaceURI: 'http://www.w3.org/2000/svg', tagName: 'path'}), /whole illustration/)
  assert.match(snapshotUnavailableReason({...target, querySelectorAll: () => ({length: 1501})}), /too large/)
})

import {test} from 'node:test'
import assert from 'node:assert/strict'
import {resolve, capture, excluded} from '../../assets/embed/anchor.mjs'
// Small DOM contract fakes keep the resolver tests dependency-free; the separate-origin fixture exercises real DOM integration.
globalThis.CSS = {escape: value => value.replace(/["\\]/g, '\\$&')}
globalThis.getComputedStyle = element => element.style
function element(attrs = {}, shown = true) {
  return {tagName: 'BUTTON', nodeType: 1, id: attrs.id || '', textContent: 'Continue', parentElement: null,
    style: {display: shown ? 'block' : 'none', visibility: 'visible', opacity: '1'},
    getAttribute: key => attrs[key] || null, closest: () => null, querySelector: () => null,
    getBoundingClientRect: () => ({left: 10, top: 20, width: 100, height: 40})}
}
const anchor = {version: 1, platform: 'web', type: 'dom', target: {tag: 'button', selector: '#pay', feedback_id: 'pay'}, point: {x: .5, y: .5}}
test('explicit ID selects the single visible responsive representation', () => {
  const desktop = element({}, false), mobile = element()
  const result = resolve(JSON.parse(JSON.stringify(anchor)), {querySelectorAll: () => [desktop, mobile]})
  assert.equal(result.element, mobile)
})
test('hidden, missing, and ambiguous anchors have no pin', () => {
  assert.equal(resolve(anchor, {querySelectorAll: () => [element({}, false)]}).state, 'hidden')
  assert.equal(resolve(anchor, {querySelectorAll: () => []}).state, 'missing')
  assert.equal(resolve(anchor, {querySelectorAll: () => [element(), element()]}).state, 'ambiguous')
})
test('excluded elements never resolve even with stable IDs', () => {
  const target = element(); target.closest = () => ({})
  assert.equal(resolve(anchor, {querySelectorAll: () => [target]}).state, 'missing')
  assert.throws(() => capture(target, 20, 30), /excluded/)
})
test('positional selector without semantic evidence is uncertain', () => {
  const positional = {...anchor, target: {tag: 'button', selector: 'button:nth-of-type(1)'}}
  assert.equal(resolve(positional, {}).state, 'uncertain')
})
test('capture with stable identity excludes values and text and stores a relative point', () => {
  const target = element({id: 'pay', 'data-feedback-id': 'pay'}); target.value = 'private'
  globalThis.document = {documentElement: {}}
  const result = capture(target, 60, 40)
  assert.deepEqual(result.point, {x: .5, y: .5})
  assert.equal(result.target.feedback_id, 'pay')
  assert.equal(result.target.text, undefined)
  assert.equal(JSON.stringify(result).includes('private'), false)
})
test('sensitive descendants exclude a containing region', () => {
  const target = element(); target.querySelector = () => ({})
  assert.equal(excluded(target), true)
})
test('semantic mismatch never resolves a reused selector', () => {
  const semantic = {...anchor, target: {tag: 'button', selector: '#pay', id: 'pay', text: 'Different label'}}
  assert.equal(resolve(semantic, {querySelectorAll: () => [element()]}).state, 'missing')
})

test('closed details hides its children even if they have layout rectangles', () => {
  const target = element()
  target.parentElement = {tagName: 'DETAILS', nodeType: 1, hasAttribute: () => false, querySelector: () => null, parentElement: null}
  assert.equal(resolve(anchor, {querySelectorAll: () => [target]}).state, 'hidden')
})

test('image identity survives serialization without query strings or fragments', () => {
  globalThis.document = {documentElement: {}, baseURI: 'https://example.com/'}
  const image = element({src: '/logo.svg?token=secret#private', alt: 'Company'})
  image.tagName = 'IMG'; image.textContent = ''; image.parentElement = {children: [image], tagName: 'BODY', getAttribute: () => null}
  image.parentElement.id = 'header'
  const saved = JSON.parse(JSON.stringify(capture(image, 20, 30)))
  assert.equal(saved.target.image_src, 'https://example.com/logo.svg')
  assert.equal(saved.target.label, 'Company')
  assert.equal(resolve(saved, {querySelectorAll: () => [image]}).element, image)
  const changed = {...image, getAttribute: key => key === 'src' ? '/other.svg' : image.getAttribute(key)}
  assert.equal(resolve(saved, {querySelectorAll: () => [changed]}).state, 'missing')
  const privateCapture = capture(image, 20, 30, {captureText: false})
  assert.equal(privateCapture.target.image_src, undefined)
})
test('duplicate images remain ambiguous without a unique selector match', () => {
  globalThis.document = {baseURI: 'https://example.com/'}
  const image = element({src: '/logo.svg'}); image.tagName = 'IMG'
  const saved = {version: 1, platform: 'web', type: 'dom', target: {tag: 'img', selector: '#removed', image_src: 'https://example.com/logo.svg'}}
  assert.equal(resolve(saved, {querySelectorAll: selector => selector === '#removed' ? [] : [image, {...image}]}).state, 'ambiguous')
})

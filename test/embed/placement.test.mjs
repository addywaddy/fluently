import test from 'node:test'
import assert from 'node:assert/strict'
import {placement} from '../../assets/embed/placement.mjs'

globalThis.innerWidth = 1000
globalThis.innerHeight = 800
globalThis.getComputedStyle = element => ({position: element.position || 'static'})
const target = (top, position = 'static', parentElement = null) => ({
  position, parentElement,
  getBoundingClientRect: () => ({left: 100, top, width: 200, height: 80})
})

test('document pin coordinates stay unchanged as the page scrolls', () => {
  const before = placement(target(500), {left: 0, top: 0})
  const after = placement(target(200), {left: 0, top: -300})
  assert.deepEqual(after, before)
  assert.equal(after.position, 'absolute')
  assert.equal(after.top, 508)
})

test('accounts for a positioned body and horizontal scrolling', () => {
  const result = placement(target(200), {left: -40, top: -280})
  assert.equal(result.left, 332)
  assert.equal(result.top, 488)
})

test('fixed and sticky ancestors keep viewport coordinates', () => {
  for (const position of ['fixed', 'sticky']) {
    const result = placement(target(20, 'static', {position}), {left: 0, top: -300})
    assert.equal(result.position, 'fixed')
    assert.equal(result.top, 28)
  }
})

test('offscreen anchors retain document coordinates for native re-entry', () => {
  const result = placement(target(-200), {left: 0, top: -700})
  assert.equal(result.outside, true)
  assert.equal(result.top, 508)
})

test('nested scrolling updates the target offset within the document', () => {
  const before = placement(target(500), {left: 0, top: -100})
  const after = placement(target(300), {left: 0, top: -100})
  assert.equal(before.top - after.top, 200)
})


test('resizing preserves the inset from the top-right corner', () => {
  const rect = {left: 100, top: 200, width: 900, height: 80}
  const element = {getBoundingClientRect: () => rect}
  const before = placement(element, {left: 0, top: 0})
  rect.width = 320
  rect.height = 160
  const after = placement(element, {left: 0, top: 0})
  assert.equal(100 + 900 - before.left, 8)
  assert.equal(rect.left + rect.width - after.left, 8)
  assert.equal(after.top, before.top)
  assert.equal(before.left, 992)
  assert.equal(before.top, 208)
})

test('badges follow target relocation and stay inside very small targets', () => {
  const element = {getBoundingClientRect: () => ({left: 20, top: 40, width: 10, height: 6})}
  const result = placement(element, {left: 0, top: 0})
  assert.equal(result.left, 25)
  assert.equal(result.top, 43)
})

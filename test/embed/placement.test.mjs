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
const point = {x: 0.5, y: 0.5}

test('document pin coordinates stay unchanged as the page scrolls', () => {
  const before = placement(target(500), point, {left: 0, top: 0})
  const after = placement(target(200), point, {left: 0, top: -300})
  assert.deepEqual(after, before)
  assert.equal(after.position, 'absolute')
  assert.equal(after.top, 540)
})

test('accounts for a positioned body and horizontal scrolling', () => {
  const result = placement(target(200), point, {left: -40, top: -280})
  assert.equal(result.left, 240)
  assert.equal(result.top, 520)
})

test('fixed and sticky ancestors keep viewport coordinates', () => {
  for (const position of ['fixed', 'sticky']) {
    const result = placement(target(20, 'static', {position}), point, {left: 0, top: -300})
    assert.equal(result.position, 'fixed')
    assert.equal(result.top, 60)
  }
})

test('offscreen anchors retain document coordinates for native re-entry', () => {
  const result = placement(target(-200), point, {left: 0, top: -700})
  assert.equal(result.outside, true)
  assert.equal(result.top, 540)
})

test('nested scrolling updates the target offset within the document', () => {
  const before = placement(target(500), point, {left: 0, top: -100})
  const after = placement(target(300), point, {left: 0, top: -100})
  assert.equal(before.top - after.top, 200)
})

import {test} from 'node:test'
import assert from 'node:assert/strict'
import {reviewerPresentation, renderReviewerBadge} from '../../assets/embed/reviewer-identity.mjs'

const document = {createElement() { return {
  ownerDocument: document, dataset: {}, attributes: {},
  setAttribute(key, value) { this.attributes[key] = value },
  replaceChildren(...children) { this.children = children },
  set innerHTML(_) { throw new Error('Identity must not be rendered as HTML') }
}}}

test('authorized account identity renders name and an initials avatar', () => {
  const badge = document.createElement('div')
  renderReviewerBadge(badge, {name: 'Jane Smith', kind: 'account'})
  assert.equal(badge.dataset.account, 'true')
  assert.equal(badge.title, 'Fluently account')
  assert.equal(badge.children[0].textContent, 'JS')
  assert.equal(badge.children[0].attributes['aria-hidden'], 'true')
  assert.equal(badge.children[1].textContent, 'Commenting as Jane Smith')
})

test('guest and invalidated identities are not presented as Fluently accounts', () => {
  const badge = document.createElement('div')
  renderReviewerBadge(badge, {name: 'Jane Smith', kind: 'account'})
  renderReviewerBadge(badge, null)
  assert.equal(badge.dataset.account, 'false')
  assert.equal(badge.children[1].textContent, 'Commenting as Guest')
  assert.equal(reviewerPresentation({name: 'Jane Smith', kind: 'guest'}).account, false)
  assert.equal(reviewerPresentation({name: 'Jane Smith', kind: 'pseudonymous'}).account, false)
})

test('names are rendered as text, bounded, and support non-ASCII initials', () => {
  const badge = document.createElement('div')
  renderReviewerBadge(badge, {name: '<img onerror=bad>', kind: 'guest'})
  assert.equal(badge.children[1].textContent, 'Commenting as <img onerror=bad>')
  assert.equal(reviewerPresentation({name: '  Élodie Müller  '}).initials, 'ÉM')
  assert.equal(reviewerPresentation({name: '   '}).name, 'Guest')
  assert.equal(reviewerPresentation({name: 'a'.repeat(100)}).name.length, 80)
})

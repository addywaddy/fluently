// No absolute coordinates are persisted. Explicit identity wins; uncertainty stays visible in the list.
const excludedSelector = '[data-feedback-exclude],script,style,iframe,input,textarea,select,[contenteditable]:not([contenteditable="false"])'
export function excluded(element) {
  return !element || Boolean(element.closest(excludedSelector)) || Boolean(element.querySelector(excludedSelector))
}
const bounded = value => typeof value === 'string' ? value.trim().replace(/\s+/g, ' ').slice(0, 160) : ''
export function imageSource(element) {
  if (element.tagName.toLowerCase() !== 'img') return ''
  try {
    const sourceAttribute = element.getAttribute('src')
    if (!sourceAttribute) return ''
    const url = new URL(sourceAttribute, document.baseURI)
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) return ''
    const source = url.origin + url.pathname
    return source.length <= 1000 ? source : ''
  } catch { return '' }
}
export function capture(element, x, y, {captureText = true} = {}) {
  if (excluded(element)) throw new Error('This area is excluded from feedback. Select a non-sensitive element.')
  const target = {tag: element.tagName.toLowerCase(), selector: selectorFor(element)}
  for (const [key, attribute] of [['feedback_id', 'data-feedback-id'], ['id', 'id'], ['role', 'role']]) {
    const value = bounded(element.getAttribute(attribute))
    if (value) target[key] = value
  }
  // Only a selected target without stable identity needs bounded semantic text. Installations can disable it.
  if (captureText && !target.feedback_id && !target.id) {
    target.text = bounded(element.textContent)
    target.label = bounded(element.getAttribute('aria-label') || (target.tag === 'img' ? element.getAttribute('alt') : ''))
    if (target.tag === 'img') target.image_src = imageSource(element)
  }
  const rect = element.getBoundingClientRect()
  const fraction = (value, start, size) => Math.max(0, Math.min(1, size ? (value - start) / size : 0.5))
  return {version: 1, platform: 'web', type: 'dom', target, point: {x: fraction(x, rect.left, rect.width), y: fraction(y, rect.top, rect.height)}}
}
export function selectorFor(element) {
  const parts = []
  for (let node = element; node && node !== document.documentElement && parts.length < 10; node = node.parentElement) {
    const tag = node.tagName.toLowerCase()
    if (node.id && node.id.length <= 160) { parts.unshift(`#${CSS.escape(node.id)}`); break }
    const siblings = [...node.parentElement.children].filter(child => child.tagName === node.tagName)
    parts.unshift(`${tag}:nth-of-type(${siblings.indexOf(node) + 1})`)
  }
  return parts.join(' > ').slice(0, 1000)
}
export function visible(element) {
  const rect = element.getBoundingClientRect()
  if (!rect.width || !rect.height) return false
  for (let node = element; node && node.nodeType === 1; node = node.parentElement) {
    if (node.tagName === 'DETAILS' && !node.hasAttribute('open')) {
      const summary = node.querySelector('summary')
      if (element !== node && (!summary || (element !== summary && !summary.contains(element)))) return false
    }
    const style = getComputedStyle(node)
    if (style.display === 'none' || style.visibility === 'hidden' || style.visibility === 'collapse' || Number(style.opacity) === 0 || node.hidden || node.inert) return false
  }
  return true
}
export function resolve(anchor, root = document) {
  if (anchor?.version !== 1 || anchor.platform !== 'web' || anchor.type !== 'dom') return {state: 'unsupported'}
  const target = anchor.target
  if (!target || typeof target.selector !== 'string') return {state: 'missing'}
  const query = selector => { try { return [...root.querySelectorAll(selector)] } catch { return [] } }
  const match = element => !excluded(element) && element.tagName.toLowerCase() === target.tag &&
    (!target.role || element.getAttribute('role') === target.role) &&
    (!target.label || bounded(element.getAttribute('aria-label') || (target.tag === 'img' ? element.getAttribute('alt') : '')) === target.label) &&
    (!target.image_src || imageSource(element) === target.image_src) &&
    (!target.text || bounded(element.textContent) === target.text)
  let candidates
  if (target.feedback_id) {
    // Desktop/mobile twins can use different tags. A shared explicit ID is authoritative.
    candidates = query(`[data-feedback-id="${CSS.escape(target.feedback_id)}"]`).filter(el => !excluded(el))
  } else if (target.id) {
    candidates = query(`#${CSS.escape(target.id)}`).filter(match)
  } else {
    // A positional selector alone cannot establish identity after a layout change.
    if (!target.text && !target.label && !target.image_src) return {state: 'uncertain'}
    candidates = query(target.selector).filter(match)
    if (!candidates.length) candidates = query(target.tag).filter(match)
  }
  if (!candidates.length) return {state: 'missing'}
  const displayed = candidates.filter(visible)
  if (!displayed.length) return {state: 'hidden'}
  if (displayed.length !== 1) return {state: 'ambiguous'}
  return {state: 'resolved', element: displayed[0]}
}
export function context() {
  const ua = navigator.userAgent
  const browser = /Firefox\//.test(ua) ? 'Firefox' : /Edg\//.test(ua) ? 'Edge' : /Chrome\//.test(ua) ? 'Chrome' : /Safari\//.test(ua) ? 'Safari' : 'Other'
  return {viewport: {width: innerWidth, height: innerHeight}, scroll: {x: scrollX, y: scrollY}, browser}
}
export function pageURL() { return location.origin + location.pathname }

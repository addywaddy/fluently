import {renderReviewerBadge} from './reviewer-identity.mjs'
import {customerReference, hostIdentityKey} from './customer-reference.mjs'
import {startConnection, consumeConnection} from './account-connect.mjs'
import {capture, resolve, context, pageURL, visible, excluded} from './anchor.mjs'
import {placement} from './placement.mjs'
import {captureSnapshot} from './snapshot.mjs'
import {snapshotUnavailableReason} from './snapshot-policy.mjs'

// Shared by the website embed and the packaged Chrome content script.
export async function startEmbed(script, {activate = false} = {}) {
  const demo = script?.dataset.demo === 'true' && new URL(script.src).origin === location.origin
  const project = script?.dataset.project
  if (!(demo || project)) return
  if (document.readyState === 'loading') await new Promise(resolve => document.addEventListener('DOMContentLoaded', resolve, {once: true}))
  if (document.querySelector('fluently-feedback')) return
  const service = new URL(script.src).origin
  const storageKey = `fluently:${service}:${project}`
  const connectKey = storageKey + ':connect'
  const currentHostKey = () => demo ? '' : hostIdentityKey(document, script.dataset)
  const hostKey = currentHostKey()
  const reference = demo ? {value: null} : customerReference(document, script.dataset)
  const fragment = new URLSearchParams(location.hash.slice(1))
  let invitation = demo ? null : fragment.get('fluently')
  const accountEntry = !demo && (activate || fragment.get('fluently_account') === '1')
  const connectionCode = !demo && fragment.get('fluently_code')
  const connectionState = !demo && fragment.get('fluently_state')
  const connectionResult = !demo && fragment.get('fluently_result')
  if (!demo && ['fluently', 'fluently_account', 'fluently_code', 'fluently_state', 'fluently_result'].some(key => fragment.has(key))) {
    for (const key of ['fluently', 'fluently_account', 'fluently_code', 'fluently_state', 'fluently_result']) fragment.delete(key)
    history.replaceState(history.state, '', location.pathname + location.search + (fragment.size ? '#' + fragment : ''))
  }
  let token = null
  try {
    if (!demo) {
      const stored = sessionStorage.getItem(storageKey)
      if (stored?.startsWith('{')) { const saved = JSON.parse(stored); if (saved.hostKey === hostKey && reference.state !== 'invalid') token = saved.token; else { sessionStorage.removeItem(storageKey); revokeToken(saved.token) } }
      else if (!hostKey) token = stored // pre-account guest sessions
      else if (stored) { sessionStorage.removeItem(storageKey); revokeToken(stored) }
    }
  } catch { /* memory-only session */ }
  if (demo || invitation || token || accountEntry || connectionState) await initialize()

  function revokeToken(value) {
    if (!value || demo) return
    fetch(`${service}/api/projects/${encodeURIComponent(project)}/session`, {
      method: 'DELETE', mode: 'cors', credentials: 'omit', referrerPolicy: 'no-referrer',
      headers: {Authorization: `Bearer ${value}`}, keepalive: true
    }).catch(() => {})
  }

  async function initialize() {
    if (!document.body) await new Promise(resolve => document.addEventListener('DOMContentLoaded', resolve, {once: true}))
    const host = document.createElement('fluently-feedback')
    host.dataset.feedbackExclude = ''
    host.style.cssText = 'all:initial!important;position:absolute!important;inset:0!important;pointer-events:none!important;z-index:2147483646!important;display:block!important;'
    const shadow = host.attachShadow({mode: 'open'})
    const style = document.createElement('style')
    if (script.dataset.styleNonce) style.nonce = script.dataset.styleNonce
    style.textContent = `
      .menu{position:fixed;z-index:1;min-width:170px;max-width:calc(100vw - 16px);padding:5px;background:white;border:1px solid #ccd6e4;border-radius:9px;box-shadow:0 8px 28px #14243a30;pointer-events:auto;font:13px/1.5 system-ui,sans-serif}.menu button{display:block;width:100%;text-align:left;white-space:nowrap}.controls{display:flex;align-items:center;justify-content:flex-start;gap:8px;flex-wrap:nowrap;height:56px;overflow-x:auto;padding:8px;background:white;border:1px solid #ccd6e4;border-radius:12px;box-shadow:0 5px 22px #14243a25;pointer-events:none;max-width:calc(100vw - 100px);min-width:0;position:relative;z-index:0;transform:translateX(68px);clip-path:inset(0 0 0 calc(100% - 56px) round 28px);opacity:0;visibility:hidden;transition:transform .4s cubic-bezier(.22,.61,.36,1),clip-path .4s cubic-bezier(.22,.61,.36,1),opacity .3s ease,visibility 0s .4s}.controls>*{flex-shrink:0;white-space:nowrap}.controls[data-open="true"]{transform:translateX(0);clip-path:inset(0 round 12px);opacity:1;visibility:visible;pointer-events:auto;transition-delay:0s}
      :host{all:initial;color-scheme:light}*{box-sizing:border-box}button,input,textarea,select{font:inherit}button{cursor:pointer}button:disabled{opacity:.5;cursor:wait}button:focus-visible,input:focus-visible,textarea:focus-visible,select:focus-visible{outline:3px solid #1689d5;outline-offset:3px}
      .bar,.panel,.hint,.pin{font:13px/1.5 system-ui,sans-serif;color:#273140;pointer-events:auto}.bar{position:fixed;bottom:max(16px,env(safe-area-inset-bottom));right:max(16px,env(safe-area-inset-right));display:flex;flex-direction:row;align-items:center;gap:12px;max-width:calc(100vw - 32px);pointer-events:none}
      button{background:#f4f8fc;border:1px solid #ccd6e4;border-radius:6px;padding:8px 12px;color:#1c597c}.primary{background:#167dbd;color:white;border-color:#167dbd}.panel{position:fixed;right:16px;top:16px;bottom:88px;width:350px;max-width:calc(100vw - 32px);overflow:auto;padding:20px;background:white;border:1px solid #ccd6e4;border-radius:12px;box-shadow:0 10px 40px #14243a30}.panel h2{font-size:19px;margin:0 0 15px}.panel p{margin:10px 0;overflow-wrap:anywhere}.panel label{display:block;margin:12px 0}.panel input,.panel textarea,.panel select{display:block;width:100%;padding:10px;border:1px solid #bccbdb;border-radius:6px;margin-top:6px;background:white;color:#273140}.panel textarea{min-height:100px;resize:vertical}.row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.row h2{flex:1;margin:0}.muted{font-size:11px;color:#657387}.error{color:#a3313e;font-size:12px}.thread{display:block;width:100%;text-align:left;margin-top:10px;overflow-wrap:anywhere}.message{padding:12px 0;border-bottom:1px solid #e5ebf1;white-space:pre-wrap;overflow-wrap:anywhere}.message strong{font-size:12px}.message time{display:block;font-size:10px;color:#657387}.pin{position:fixed;transform:translate(-50%,-50%);border:2px solid white;box-shadow:0 0 0 1px #167dbd;width:28px;height:28px;padding:0;background:#167dbd;color:white;border-radius:50% 50% 3px 50%;font-size:11px}.hint{position:fixed;top:16px;left:16px;padding:10px 14px;background:#243447;color:white;border-radius:8px;max-width:calc(100vw - 32px);pointer-events:none}.outline{position:fixed;border:2px solid #1689d5;background:#1689d510;pointer-events:none}.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0)}[hidden]{display:none!important}
      .controls select{padding:8px;border:1px solid #ccd6e4;border-radius:6px;background:#f4f8fc;color:#1c597c;font:13px/1.5 system-ui,sans-serif}
      .reviewer-identity{display:flex;align-items:center;gap:8px;min-width:0;font:12px/1.4 system-ui,sans-serif;color:#657387}.reviewer-avatar{display:grid;place-items:center;flex:none;width:30px;height:30px;border-radius:50%;background:#eef1f5;border:1px solid #d6dce3;font-weight:600;color:#657387}.reviewer-identity[data-account="true"] .reviewer-avatar{background:#e8f5ff;border-color:#b5daf2;color:#0f6398}.reviewer-name{max-width:180px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.panel .reviewer-name{max-width:none;white-space:normal;overflow-wrap:anywhere}.panel .reviewer-identity{margin:12px 0}
      .snapshot{display:block;max-width:100%;height:auto;margin:12px 0;border:1px solid #ccd6e4;border-radius:6px}
      .launcher{position:relative;z-index:1;display:grid;place-items:center;flex:none;width:56px;height:56px;padding:3px;border:1px solid #d6dce3;border-radius:50%;background:white;box-shadow:0 4px 18px #14243a30;pointer-events:auto;transition:box-shadow .15s,border-color .15s}.launcher svg{display:block;width:48px;height:48px;border-radius:50%;overflow:hidden;filter:grayscale(1);opacity:.7;transform:rotate(0deg);transition:transform .6s cubic-bezier(.22,.61,.36,1),filter .6s ease,opacity .6s ease}.launcher:hover svg{opacity:1}.launcher[aria-pressed="true"]{border-color:#2093df;box-shadow:0 0 0 3px #2093df26,0 4px 18px #14243a30}.launcher[aria-pressed="true"] svg{filter:grayscale(0);opacity:1}@media(prefers-reduced-motion:reduce){.launcher,.launcher svg,.controls{transition:none}}
    `
    shadow.append(style)
    const el = (tag, text, className) => {
      const node = document.createElement(tag)
      if (text) node.textContent = text
      if (className) node.className = className
      return node
    }
    const button = (label, action, className) => {
      const b = el('button', label, className); b.type = 'button'; b.addEventListener('click', action); return b
    }
    const bar = el('div', '', 'bar')
    const panel = el('section', '', 'panel'); panel.hidden = true; panel.setAttribute('aria-label', 'Fluently feedback')
    const pins = el('div'); pins.hidden = true
    const menu = el('div', '', 'menu'); menu.hidden = true
    menu.setAttribute('role', 'menu'); menu.setAttribute('aria-label', 'Fluently actions')
    const hint = el('div', 'Click or right-click an element · Esc to cancel', 'hint'); hint.hidden = true
    const outline = el('div', '', 'outline'); outline.hidden = true
    const live = el('div', '', 'sr'); live.setAttribute('role', 'status'); live.setAttribute('aria-live', 'polite')
    shadow.append(pins, outline, hint, bar, panel, live, menu)
    document.body.append(host)
    let reviewIdentity = {name: 'Guest', kind: 'guest'}, identityReady = false, reviewView = 'all'
    let armed = false, threads = [], page = pageURL(), draft = null, selected = null, filter = 'open', frame = null, loading = false
    let panelMode = '', lastFocus = null, busy = false, countLabel = '', destroyed = false, selectedAnchor = null
    let commenting = false, menuSnapshot = null, menuFocus = null, logoRotation = 0
    const announce = text => { live.textContent = text }
    const errorBox = () => { const node = el('p', '', 'error'); node.setAttribute('role', 'alert'); return node }
    const toggle = button('', () => setCommenting(!commenting), 'launcher')
    toggle.disabled = true
    toggle.setAttribute('aria-label', 'Commenting: off')
    toggle.title = 'Turn commenting on'
    // Inline the existing Fluently mark so embeds need no extra image/CSP request.
    const logo = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    logo.setAttribute('viewBox', '0 0 200 200'); logo.setAttribute('fill', 'none')
    logo.setAttribute('aria-hidden', 'true'); logo.setAttribute('focusable', 'false')
    for (const [tag, attrs] of [
      ['circle', {cx: '100', cy: '100', r: '100', fill: '#2093DF'}],
      ['path', {d: 'M-50 109C99 148 49 69 99 69C149 69 84 146.726 149 148C214 149.275 251 109 251 109', stroke: '#93D4FF', 'stroke-width': '25'}],
      ['path', {d: 'M-44 89C105 128 55 49 105 49C155 49 90 126.726 155 128C220 129.275 257 89 257 89', stroke: 'white', 'stroke-width': '17'}]
    ]) {
      const shape = document.createElementNS('http://www.w3.org/2000/svg', tag)
      for (const [name, value] of Object.entries(attrs)) shape.setAttribute(name, value)
      logo.append(shape)
    }
    toggle.append(logo)
    toggle.setAttribute('aria-pressed', 'false')
    const addButton = button('Add comment', () => setArmed(!armed))
    const controls = el('div', '', 'controls'); controls.inert = true; controls.setAttribute('aria-hidden', 'true')
    const listButton = button('Threads', () => showList())
    const exit = button('Exit', endReview)
    const reviewerBadge = el('div'); reviewerBadge.dataset.reviewIdentity = ''
    renderReviewerBadge(reviewerBadge, reviewIdentity)
    const connectButton = button('Continue with Fluently', connectAccount)
    const reviewVisibility = el('select'); reviewVisibility.setAttribute('aria-label', 'Review visibility'); reviewVisibility.hidden = true
    for (const [value, text] of [['all', 'All reviews'], ['mine', 'My reviews']]) {
      const option = el('option', text); option.value = value; reviewVisibility.append(option)
    }
    reviewVisibility.addEventListener('change', () => {
      reviewView = reviewVisibility.value; threads = []; closePanel(); setArmed(false); renderPins(); refresh(true)
    })
    controls.append(reviewerBadge, reviewVisibility, addButton, listButton, exit)
    if (!demo) controls.append(connectButton)
    function updateReviewIdentity(identity) {
      const next = identity || {name: 'Guest', kind: 'guest'}
      if (identityReady && panelMode === 'draft' && (next.name !== reviewIdentity.name || next.kind !== reviewIdentity.kind)) closePanel()
      reviewIdentity = next
      for (const badge of shadow.querySelectorAll('[data-review-identity]')) renderReviewerBadge(badge, reviewIdentity)
      connectButton.hidden = reviewIdentity.kind === 'account'
      reviewVisibility.hidden = reviewIdentity.kind !== 'account'
      if (reviewVisibility.hidden) { reviewView = 'all'; reviewVisibility.value = 'all' }
    }
    bar.append(controls, toggle)
    const saveDemo = el('a', 'Create account')
    if (demo) {
      saveDemo.href = '/signup'; saveDemo.style.cssText = 'color:#1c597c;padding:8px'
      controls.append(saveDemo)
    }
    const menuAdd = button('Add comment', () => {
      const snapshot = menuSnapshot
      closeContext()
      if (snapshot && snapshot.page === pageURL()) { beginDraft(snapshot); lastFocus = addButton }
    })
    menuAdd.setAttribute('role', 'menuitem'); menu.append(menuAdd)
    menu.addEventListener('keydown', event => {
      if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) { event.preventDefault(); menuAdd.focus() }
      if (event.key === 'Tab') closeContext(true)
    })
    function setCommenting(value) {
      if (value !== commenting) {
        logoRotation += value ? 360 : -360
        logo.style.transform = `rotate(${logoRotation}deg)`
      }
      commenting = value; pins.hidden = !value
      controls.dataset.open = String(value); controls.inert = !value; controls.setAttribute('aria-hidden', String(!value))
      toggle.setAttribute('aria-label', value ? 'Commenting: on' : 'Commenting: off')
      toggle.title = value ? 'Turn commenting off' : 'Turn commenting on'
      toggle.setAttribute('aria-pressed', String(value))
      setArmed(false)
      if (!value) closePanel()
      announce(value ? 'Commenting enabled. Right-click an element or use Add comment.' : 'Commenting disabled.')
    }
    function setArmed(value) {
      closeContext()
      armed = commenting && identityReady && value; hint.hidden = !commenting; outline.hidden = true
      hint.textContent = armed ? 'Click an element · Esc to cancel' : 'Right-click an element to comment, or use Add comment · Esc to exit'
      addButton.textContent = armed ? 'Cancel selection' : 'Add comment'; addButton.setAttribute('aria-pressed', String(armed))
      if (armed) { closePanel(); announce('Choose an element. Press Escape to cancel.') }
    }
    function openPanel(title, mode) {
      selectedAnchor = null; outline.hidden = true
      lastFocus = shadow.activeElement || document.activeElement
      panelMode = mode; panel.hidden = false; panel.replaceChildren()
      const heading = el('div', '', 'row')
      const h = el('h2', title); h.tabIndex = -1
      heading.append(h, button('Close', () => mode === 'join' ? cleanup() : closePanel())); panel.append(heading)
      h.focus()
    }
    function closePanel() { panel.hidden = true; panelMode = ''; draft = null; selected = null; selectedAnchor = null; if (lastFocus?.isConnected) lastFocus.focus({preventScroll:true}); outline.hidden = true }
    async function api(path, method = 'GET', data) {
      if (destroyed || (!demo && currentHostKey() !== hostKey)) { endReview(); throw new Error('The website user changed. Reopen the review link.') }
      const base = demo ? `${service}/demo` : `${service}/api/projects/${encodeURIComponent(project)}`
      const response = await fetch(`${base}${path}`, {
        method, mode: demo ? 'same-origin' : 'cors', credentials: demo ? 'same-origin' : 'omit',
        // no-referrer makes non-CORS writes send Origin: null in WebKit.
        // Send only the origin for first-party requests, never paths or queries.
        referrerPolicy: demo ? 'strict-origin' : 'no-referrer',
        headers: {'Content-Type': 'application/json', ...(demo ? {'x-csrf-token': document.querySelector('meta[name="csrf-token"]')?.content || ''} : token ? {Authorization: `Bearer ${token}`} : {})},
        body: data ? JSON.stringify(data) : undefined,
        signal: AbortSignal.timeout(15000)
      })
      if (destroyed || (!demo && currentHostKey() !== hostKey)) { endReview(); throw new Error('Review session ended.') }
      const result = response.status === 204 ? {} : await response.json()
      if (!response.ok) {
        if (!demo && [401, 403, 404].includes(response.status) && token) { token = null; identityReady = false; updateReviewIdentity(null); threads = []; renderPins(); setCommenting(false); try { sessionStorage.removeItem(storageKey) } catch {} }
        const error = new Error(result.error?.message || 'Request failed'); error.status = response.status; throw error }
      return result
    }
    async function submit(form, operation, error) {
      if (busy) return
      busy = true
      const buttons = [...form.querySelectorAll('button')]; buttons.forEach(b => b.disabled = true)
      error.textContent = ''
      try { await operation() }
      catch (e) { error.textContent = e.message || 'Connection failed. Please retry.' }
      finally { busy = false; buttons.forEach(b => b.disabled = false) }
    }
    function saveToken(value) {
      token = value
      try { sessionStorage.setItem(storageKey, JSON.stringify({token, hostKey})) }
      catch { announce('Session storage unavailable. Reopen the review link after reloading.') }
    }
    async function connectAccount() {
      try {
        const url = await startConnection({service, project, returnTo: location.href,
          storage: sessionStorage, key: connectKey, invitation, hostKey})
        if (!destroyed) location.assign(url)
      } catch {
        openPanel('Connection unavailable', 'error')
        panel.append(el('p', 'Enable browser session storage to continue with Fluently. You can still use a guest invitation.'))
      }
    }
    function endReview() {
      if (destroyed) return
      const previous = token
      token = null
      try { sessionStorage.removeItem(storageKey); sessionStorage.removeItem(connectKey) } catch {}
      revokeToken(previous)
      window.dispatchEvent(new Event('fluently:exit'))
      cleanup()
    }
    function hostIdentityChanged() { if (!demo) endReview() }
    function nameForm(notice = '') {
      bar.hidden = true
      openPanel('Join the review', 'join')
      if (notice) panel.append(el('p', notice, 'muted'))
      if (reference.state === 'invalid') { panel.append(el('p', 'The website’s customer reference configuration is invalid or ambiguous. Ask the project owner to check its selector and data attribute.', 'error')); return }
      panel.append(button('Continue with Fluently', connectAccount))
      if (!invitation) { panel.append(el('p', 'Project members can connect their Fluently account. Guest reviewers need a current invitation link.')); return }
      panel.append(el('p', 'Choose a display name. Everyone with this project’s review link can see its feedback.'))
      if (reference.value) panel.append(el('p', 'Your website-provided customer reference will be attached as unverified metadata.', 'muted'))
      const form = el('form'), label = el('label', 'Your display name'), input = el('input')
      input.required = true; input.maxLength = 80; input.autocomplete = 'nickname'; label.append(input)
      const send = el('button', 'Start reviewing', 'primary'); send.type = 'submit'
      const error = errorBox(); form.append(label, send, error); panel.append(form)
      form.addEventListener('submit', event => {
        event.preventDefault()
        submit(form, async () => {
          const result = await api('/sessions', 'POST', {token: invitation, name: input.value.trim(), external_ref: reference.value})
          saveToken(result.token); updateReviewIdentity(result.reviewer); invitation = null
          bar.hidden = false; closePanel(); await refresh(true)
        }, error)
      })
      input.focus()
    }
    function position() {
      let hidden = 0
      const matching = threads.filter(t => t.status === filter)
      const origin = host.getBoundingClientRect()
      // Complete layout reads before writing styles, avoiding a layout flush
      // between every pin on pages with many threads.
      const positions = matching.map(thread => {
        const result = resolve(thread.anchor)
        return result.state === 'resolved' ? {...placement(result.element, origin), element: result.element} : null
      })
      const groups = new Map()
      for (const [i, location] of positions.entries()) {
        const pin = pins.children[i]
        if (!pin) continue
        pin.hidden = !location
        if (pin.hidden) { hidden++; continue }
        // Offscreen document pins remain rendered so they return with native
        // scrolling, without waiting for a scroll handler to unhide them.
        if (location.outside) hidden++
        const group = groups.get(location.element)
        if (group) {
          group.threads.push(matching[i]); pin.hidden = true
          continue
        }
        groups.set(location.element, {pin, threads: [matching[i]], index: i})
        pin.style.position = location.position
        pin.style.left = `${location.left}px`; pin.style.top = `${location.top}px`
      }
      for (const {pin, threads: grouped, index} of groups.values()) {
        pin.feedbackThreads = grouped
        pin.textContent = grouped.length > 1 ? `${grouped.length}+` : String(index + 1)
        pin.setAttribute('aria-label', grouped.length > 1 ? `Open ${grouped.length} comments on this element` : `Open comment ${index + 1}: ${grouped[0].messages[0]?.body.slice(0, 60) || ''}`)
      }
      const label = `${matching.length} ${filter} · ${hidden} hidden in this view`
      if (countLabel !== label) { listButton.textContent = label; countLabel = label }
      if (selectedAnchor) restoreOutline()
    }
    function schedule() { if (!frame && !destroyed) frame = requestAnimationFrame(() => {frame = null; position()}) }
    function renderPins() {
      outline.hidden = true
      pins.replaceChildren()
      threads.filter(t => t.status === filter).forEach((thread, i) => {
        const pin = button(String(i + 1), () => {
          const grouped = pin.feedbackThreads || [thread]
          if (grouped.length === 1) { showThread(grouped[0]); return }
          setArmed(false); openPanel('Comments on this element', 'group')
          selectedAnchor = grouped[0].anchor; restoreOutline()
          for (const item of grouped) panel.append(button(item.messages[0]?.body || 'Comment', () => showThread(item), 'thread'))
        }, 'pin')
        pin.setAttribute('aria-label', `Open comment ${i + 1}: ${thread.messages[0]?.body.slice(0, 60) || ''}`)
        const highlight = () => {
          if (selectedAnchor) { restoreOutline(); return }
          const result = resolve(thread.anchor)
          if (result.state === 'resolved') outlineElement(result.element)
        }
        pin.addEventListener('pointerenter', highlight)
        pin.addEventListener('focus', highlight)
        pin.addEventListener('pointerleave', restoreOutline)
        pin.addEventListener('blur', restoreOutline)
        pins.append(pin)
      })
      position()
    }
    async function refresh(report = false) {
      if ((!demo && !token) || loading || destroyed) return
      loading = true
      const requestedPage = page, requestedView = reviewView
      try {
        let offset = 0, result, all = []
        do {
          result = await api(`/comments?page=${encodeURIComponent(requestedPage)}&offset=${offset}&view=${requestedView}`)
          if (result.identity) updateReviewIdentity(result.identity)
          if (demo && result.registered) { saveDemo.textContent = 'My workspace'; saveDemo.href = '/app' }
          all.push(...result.data); offset = result.next_offset
        } while (offset != null && all.length < 1000)
        if (requestedPage !== page || requestedView !== reviewView || destroyed) return
        identityReady = true; toggle.disabled = false
        if (activate) { activate = false; setCommenting(true) }
        const previous = selected && threads.find(t => t.id === selected)
        threads = all; renderPins()
        const current = selected && threads.find(t => t.id === selected)
        if ((panelMode === 'thread' || panelMode === 'delete') && selected && !current) {
          closePanel(); announce('This thread has been deleted.')
        }
        if (panelMode === 'thread' && current && !panel.querySelector('textarea')?.value && JSON.stringify(previous) !== JSON.stringify(current)) showThread(current)
        if (panelMode === 'list') showList(false)
        if (report) announce('Feedback loaded.')
      } catch (e) {
        if (destroyed) return
        if (e.status === 401 || e.status === 403 || e.status === 404) { token = null; identityReady = false; updateReviewIdentity(null); threads = []; renderPins(); setCommenting(false); toggle.disabled = true; try { sessionStorage.removeItem(storageKey) } catch {} ; report = true }
        if (report) { openPanel('Feedback unavailable', 'error'); if (!demo) panel.append(button('Continue with Fluently', connectAccount)); panel.append(el('p', e.message, 'error'), el('p', 'If the session expired or was revoked, reopen a current review link.')); }
      } finally {
        loading = false
        if (!destroyed && (requestedView !== reviewView || requestedPage !== page)) refresh(true)
      }
    }
    function showList(focus = true) {
      setArmed(false)
      if (focus) openPanel('Page feedback', 'list')
      else { panel.replaceChildren(); panel.append(el('h2', 'Page feedback'), button('Close', closePanel)) }
      const select = el('select'); select.setAttribute('aria-label', 'Thread status')
      for (const value of ['open', 'resolved']) { const option = el('option', value); option.value = value; select.append(option) }
      select.value = filter
      select.addEventListener('change', () => {filter = select.value; renderPins(); showList()})
      panel.append(select, el('p', 'Pins are hidden when their target is absent, ambiguous, excluded, or outside this view.', 'muted'))
      if (demo) panel.append(el('p', 'Feedback goes to the Fluently team. Guest access lasts 14 days in this browser; clearing cookies loses access. Creating an account does not claim guest feedback.', 'muted'))
      const matching = threads.filter(t => t.status === filter)
      if (!matching.length) panel.append(el('p', 'No threads yet. Add a comment to an element on this page.'))
      for (const [i, thread] of matching.entries()) {
        const state = resolve(thread.anchor).state
        panel.append(button(`${i + 1}. ${thread.messages[0]?.body || 'Comment'}${state === 'resolved' ? '' : ` · target ${state}`}`, () => showThread(thread), 'thread'))
      }
      if (threads.length >= 1000) panel.append(el('p', 'Showing the first 1,000 threads on this page. Use the API for the full history.', 'muted'))
    }
    function showThread(thread) {
      setArmed(false); openPanel('Comment thread', 'thread'); selected = thread.id
      selectedAnchor = thread.anchor; restoreOutline()
      if (thread.snapshot) {
        const section = el('div'), error = errorBox()
        const view = button('View element snapshot', async () => {
          view.disabled = true; error.textContent = ''
          try {
            const result = await api(`/comments/${thread.id}/snapshot`)
            const img = el('img', '', 'snapshot'); img.alt = 'Element when this comment was created'; img.src = result.data.data_url
            section.replaceChildren(el('p', 'Captured when posted · may differ from the current page', 'muted'), img)
          } catch (e) { error.textContent = e.message; view.disabled = false }
        })
        section.append(view, error); panel.append(section)
      }
      for (const [index, message] of thread.messages.entries()) {
        const item = el('article', '', 'message')
        const time = el('time', new Date(message.created_at).toLocaleString()); time.dateTime = message.created_at
        item.append(el('strong', message.author.name), time, el('p', message.body)); panel.append(item)
        if (message.can_delete) item.append(button(index === 0 ? 'Delete thread' : 'Delete reply', () => confirmDeletion(thread, message, index === 0)))
      }
      panel.append(el('p', `${thread.status} · ${thread.context.viewport.width} × ${thread.context.viewport.height} · target ${resolve(thread.anchor).state === 'resolved' ? 'found' : resolve(thread.anchor).state}`, 'muted'))
      const statusError = errorBox()
      const statusButton = button(thread.status === 'open' ? 'Resolve thread' : 'Reopen thread', async () => {
        statusButton.disabled = true
        try {
          const result = await api(`/comments/${thread.id}`, 'PATCH', {status: thread.status === 'open' ? 'resolved' : 'open'})
          threads = threads.map(t => t.id === thread.id ? result.data : t); renderPins(); showThread(result.data)
        } catch (e) { statusError.textContent = e.message; statusButton.disabled = false }
      })
      panel.append(statusButton, statusError)
      messageForm('Reply', async body => {
        const result = await api(`/comments/${thread.id}/replies`, 'POST', {body})
        threads = threads.map(t => t.id === thread.id ? result.data : t); showThread(result.data)
      })
    }
    function confirmDeletion(thread, message, entireThread) {
      openPanel(entireThread ? 'Delete this thread?' : 'Delete this reply?', 'delete')
      selected = thread.id
      selectedAnchor = thread.anchor; restoreOutline()
      panel.append(el('p', entireThread ? 'This permanently deletes the comment, all replies, and its pin. This cannot be undone.' : 'This permanently deletes your reply. The rest of the thread will remain. This cannot be undone.'))
      const error = errorBox()
      const cancel = button('Cancel', () => {
        const current = threads.find(t => t.id === thread.id)
        if (current) showThread(current); else closePanel()
      })
      const remove = button(entireThread ? 'Permanently delete thread' : 'Permanently delete reply', async () => {
        if (busy) return
        busy = true; remove.disabled = true; cancel.disabled = true; error.textContent = ''
        try {
          const result = await api(`/comments/${thread.id}/messages/${message.id}`, 'DELETE')
          if (result.deleted_thread) {
            threads = threads.filter(t => t.id !== thread.id); renderPins(); closePanel()
            announce('Thread deleted.'); listButton.focus()
          } else {
            threads = threads.map(t => t.id === thread.id ? result.data : t)
            renderPins(); showThread(result.data); announce('Reply deleted.')
          }
        } catch (e) { error.textContent = e.message || 'Could not delete. Please retry.' }
        finally { busy = false; remove.disabled = false; cancel.disabled = false }
      })
      const actions = el('div', '', 'row'); actions.append(cancel, remove)
      panel.append(el('div', message.body, 'message'), actions, error)
      cancel.focus()
    }
    function messageForm(labelText, action) {
      const form = el('form'), label = el('label', labelText), input = el('textarea')
      input.required = true; input.maxLength = 4000; label.append(input)
      const send = el('button', labelText === 'Reply' ? 'Reply' : 'Post comment', 'primary'); send.type = 'submit'
      const error = errorBox(); form.append(label, send, error); panel.append(form)
      form.addEventListener('submit', event => {
        event.preventDefault()
        if (!input.value.trim()) { input.setCustomValidity('Write a comment first.'); input.reportValidity(); return }
        submit(form, () => action(input.value.trim()), error)
      })
      input.addEventListener('input', () => input.setCustomValidity(''))
      input.focus()
    }
    function choose(event) {
      if (!armed || event.composedPath().includes(host)) return
      event.preventDefault(); event.stopImmediatePropagation()
      try {
        const anchor = capture(event.target, event.clientX, event.clientY, {captureText: script.dataset.captureText !== 'false'})
        const snapshot = {anchor, context: context(), page: pageURL(), element: event.target}
        beginDraft(snapshot)
      } catch (e) { announce(e.message); hint.textContent = e.message + ' · Esc to cancel' }
    }
    function beginDraft(snapshot) {
      if (!identityReady) return
      const {anchor, element} = snapshot
      setArmed(false); openPanel('New comment', 'draft'); draft = {anchor, context: snapshot.context, page: snapshot.page}
      selectedAnchor = anchor; restoreOutline()
      panel.append(el('p', `Attached to ${anchor.target.feedback_id || anchor.target.id || anchor.target.tag}`, 'muted'))
      const identity = el('div'); identity.dataset.reviewIdentity = ''; renderReviewerBadge(identity, reviewIdentity); panel.append(identity)
      if (demo && reviewIdentity.kind !== 'account') panel.append(el('p', 'Share feedback with the Fluently team. Other visitors cannot see your comments. Guest access uses a browser cookie and is separate from a Fluently account.', 'muted'))
      if (anchor.target.text) panel.append(el('p', `Target text included: “${anchor.target.text}”`, 'muted'))
      let image = null, capturing = false
      const snapshotBox = el('div'), preview = el('div'), snapshotError = errorBox()
      const unavailable = el('p', '', 'muted'); unavailable.id = 'snapshot-unavailable'
      const snapshotTarget = () => element?.isConnected && visible(element) && !excluded(element)
        ? element : resolve(anchor).element
      const refreshAvailability = () => {
        const reason = snapshotUnavailableReason(snapshotTarget())
        attach.disabled = capturing || Boolean(reason)
        attach.style.cursor = reason ? 'not-allowed' : ''
        unavailable.textContent = reason ? `${reason} You can still post a comment.` : ''
        unavailable.hidden = !reason
      }
      const attach = button('Attach element snapshot', async () => {
        capturing = true; attach.disabled = true; snapshotError.textContent = ''
        try {
          const target = snapshotTarget()
          const reason = snapshotUnavailableReason(target)
          if (reason) throw new Error(reason)
          let timer
          try {
            image = await Promise.race([captureSnapshot(target), new Promise((_, reject) => {
              timer = setTimeout(() => reject(new Error('Capture timed out. You can still post your comment.')), 12000)
            })])
          } finally { clearTimeout(timer) }
          const img = el('img', '', 'snapshot'); img.alt = 'Snapshot preview — check before posting'; img.src = image
          preview.replaceChildren(img, el('p', 'Check this preview for private information before posting.', 'muted'), button('Remove snapshot', () => {
            image = null; preview.replaceChildren(); attach.hidden = false; refreshAvailability()
          }))
          attach.hidden = true
        } catch (e) { image = null; snapshotError.textContent = e.message }
        finally { capturing = false; refreshAvailability() }
      })
      attach.setAttribute('aria-describedby', unavailable.id)
      refreshAvailability()
      snapshotBox.append(attach, unavailable, preview, snapshotError, el('p', 'Optional snapshot. Marked private areas and form controls are omitted. Fonts and images may differ.', 'muted'))
      if (script.dataset.screenshots !== 'false' && script.dataset.captureText !== 'false') panel.append(snapshotBox)
      messageForm('What should change?', async body => {
        if (!draft || draft.page !== pageURL()) throw new Error('The page changed. Select the element again.')
        if (capturing) throw new Error('Wait for the snapshot preview, then post your comment.')
        const savedImage = image
        const result = await api('/comments', 'POST', {...draft, body})
        threads.push(result.data); filter = 'open'; renderPins(); showThread(result.data); announce('Comment posted.')
        if (savedImage) {
          const savedId = result.data.id
          const upload = async () => {
            const uploaded = await api(`/comments/${savedId}/snapshot`, 'POST', {data_url: savedImage})
            threads = threads.map(t => t.id === savedId ? uploaded.data : t)
            if (selected === savedId && panelMode === 'thread') showThread(uploaded.data)
          }
          try { await upload() }
          catch {
            if (selected === savedId && panelMode === 'thread') {
              const warning = errorBox(); warning.textContent = 'Comment saved, but the snapshot upload failed.'
              const retry = button('Retry snapshot upload', async () => {
                retry.disabled = true
                try { await upload() } catch { retry.disabled = false; warning.textContent = 'Upload failed again. Your comment is saved.' }
              })
              panel.append(warning, retry)
            }
          }
        }
      })
    }
    function closeContext(restore = false) {
      const wasOpen = !menu.hidden
      menu.hidden = true; menuSnapshot = null
      if (restore && wasOpen && menuFocus?.isConnected) menuFocus.focus({preventScroll: true})
    }
    function contextMenu(event) {
      closeContext()
      if (!commenting || busy || event.shiftKey || event.composedPath().includes(host)) return
      let anchor
      try { anchor = capture(event.target, event.clientX, event.clientY, {captureText: script.dataset.captureText !== 'false'}) }
      catch { return } // Preserve native menus on excluded and editable content.
      event.preventDefault(); event.stopImmediatePropagation()
      setArmed(false)
      menuSnapshot = {anchor, context: context(), page: pageURL(), element: event.target}
      menuFocus = shadow.activeElement || document.activeElement
      menu.hidden = false
      const rect = event.target.getBoundingClientRect()
      const x = event.clientX || rect.left, y = event.clientY || rect.bottom
      menu.style.left = `${Math.max(8, Math.min(x, innerWidth - menu.offsetWidth - 8))}px`
      menu.style.top = `${Math.max(8, Math.min(y, innerHeight - menu.offsetHeight - 8))}px`
      menuAdd.focus({preventScroll: true})
    }
    function dismissContext(event) { if (!event.composedPath().includes(menu)) closeContext() }
    function layoutChanged() { closeContext(); if (!selectedAnchor) outline.hidden = true; schedule() }
    function blur() { closeContext() }
    function blockHost(event) { if (armed && !event.composedPath().includes(host)) { event.stopImmediatePropagation(); event.preventDefault() } }
    function hover(event) {
      if (!armed || event.composedPath().includes(host)) return
      outlineElement(event.target)
    }
    function outlineElement(element) {
      const rect = element.getBoundingClientRect()
      const origin = host.getBoundingClientRect()
      const {position} = placement(element, origin)
      const left = rect.left - (position === 'absolute' ? origin.left : 0)
      const top = rect.top - (position === 'absolute' ? origin.top : 0)
      outline.hidden = false; outline.style.cssText = `position:${position};left:${left}px;top:${top}px;width:${rect.width}px;height:${rect.height}px`
    }
    function restoreOutline() {
      const result = selectedAnchor && commenting ? resolve(selectedAnchor) : null
      if (result?.state === 'resolved') outlineElement(result.element)
      else outline.hidden = true
    }
    function keydown(event) {
      if (event.key !== 'Escape' || !commenting) return
      event.preventDefault()
      if (!menu.hidden) { closeContext(true); return }
      if (armed || !panel.hidden) { setArmed(false); closePanel(); addButton.focus(); return }
      setCommenting(false); toggle.focus()
    }
    window.addEventListener('fluently:identity-changed', hostIdentityChanged)
    window.addEventListener('click', choose, true)
    window.addEventListener('contextmenu', contextMenu, true)
    window.addEventListener('pointerdown', dismissContext, true)
    for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup']) window.addEventListener(type, blockHost, true)
    window.addEventListener('pointermove', hover, true)
    window.addEventListener('keydown', keydown)
    window.addEventListener('scroll', layoutChanged, true)
    window.addEventListener('resize', layoutChanged)
    window.addEventListener('blur', blur)
    const observer = new MutationObserver(() => {
      if (!demo && currentHostKey() !== hostKey) endReview()
      else schedule()
    })
    observer.observe(document.documentElement, {subtree: true, childList: true, attributes: true})
    const resize = new ResizeObserver(schedule); resize.observe(document.body)
    let ticks = 0
    const timer = setInterval(() => {
      if (document.hidden) return
      const next = pageURL()
      if (next !== page) { page = next; threads = []; closePanel(); setArmed(false); renderPins(); refresh(true) }
      else if (++ticks % 15 === 0) refresh()
      schedule()
    }, 1000)
    function cleanup() {
      window.removeEventListener('fluently:identity-changed', hostIdentityChanged)
      destroyed = true; clearInterval(timer); observer.disconnect(); resize.disconnect(); if (frame) cancelAnimationFrame(frame)
      window.removeEventListener('click', choose, true); window.removeEventListener('contextmenu', contextMenu, true)
      window.removeEventListener('pointerdown', dismissContext, true)
      for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup']) window.removeEventListener(type, blockHost, true)
      window.removeEventListener('pointermove', hover, true); window.removeEventListener('keydown', keydown)
      window.removeEventListener('scroll', layoutChanged, true); window.removeEventListener('resize', layoutChanged); window.removeEventListener('blur', blur); host.remove()
    }
    if (reference.state === 'invalid') { nameForm(); return }
    if (connectionState) {
      let pending
      try { pending = consumeConnection({storage: sessionStorage, key: connectKey, state: connectionState, hostKey}) } catch {}
      if (!pending) { nameForm('This connection expired or belongs to another browser session. Try again.'); return }
      invitation = pending.invitation
      if (pending.returnTo && new URL(pending.returnTo).origin === location.origin) history.replaceState(history.state, '', pending.returnTo)
      if (connectionCode) {
        try {
          const result = await api('/account-sessions', 'POST', {code: connectionCode, verifier: pending.verifier})
          saveToken(result.token); updateReviewIdentity(result.reviewer); invitation = null
          bar.hidden = false; closePanel(); await refresh(true)
        } catch (error) { nameForm(error.message) }
      } else if (connectionResult === 'guest') {
        if (token) await refresh(true)
        else nameForm('Your Fluently identity was not shared. Continue with a guest invitation.')
      } else nameForm('This connection is incomplete. Try again.')
    } else if (invitation || (accountEntry && !token)) nameForm()
    else await refresh(true)
  }
}

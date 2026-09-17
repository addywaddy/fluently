import {capture, resolve, context, pageURL} from './anchor.mjs'

const script = document.currentScript
const project = script?.dataset.project
if (project && !document.querySelector('fluently-feedback')) {
  const service = new URL(script.src).origin
  const storageKey = `fluently:${service}:${project}`
  let invitation = new URLSearchParams(location.hash.slice(1)).get('fluently')
  if (invitation) {
    const fragment = new URLSearchParams(location.hash.slice(1))
    fragment.delete('fluently')
    history.replaceState(history.state, '', location.pathname + location.search + (fragment.size ? '#' + fragment : ''))
  }
  let token = null
  try { token = sessionStorage.getItem(storageKey) } catch { /* memory-only session */ }
  if (invitation || token) initialize().catch(() => console.warn('Fluently could not initialize.'))

  async function initialize() {
    if (!document.body) await new Promise(resolve => document.addEventListener('DOMContentLoaded', resolve, {once: true}))
    const host = document.createElement('fluently-feedback')
    host.dataset.feedbackExclude = ''
    host.style.cssText = 'all:initial!important;position:fixed!important;inset:0!important;pointer-events:none!important;z-index:2147483646!important;display:block!important;'
    const shadow = host.attachShadow({mode: 'open'})
    const style = document.createElement('style')
    if (script.dataset.styleNonce) style.nonce = script.dataset.styleNonce
    style.textContent = `
      :host{all:initial;color-scheme:light}*{box-sizing:border-box}button,input,textarea,select{font:inherit}button{cursor:pointer}button:disabled{opacity:.5;cursor:wait}button:focus-visible,input:focus-visible,textarea:focus-visible,select:focus-visible{outline:3px solid #1689d5;outline-offset:3px}
      .bar,.panel,.hint,.pin{font:13px/1.5 system-ui,sans-serif;color:#273140;pointer-events:auto}.bar{position:fixed;bottom:16px;left:16px;display:flex;align-items:center;gap:8px;padding:8px;background:white;border:1px solid #ccd6e4;border-radius:10px;box-shadow:0 5px 22px #14243a25;max-width:calc(100vw - 32px);flex-wrap:wrap}
      button{background:#f4f8fc;border:1px solid #ccd6e4;border-radius:6px;padding:8px 12px;color:#1c597c}.primary{background:#167dbd;color:white;border-color:#167dbd}.panel{position:fixed;right:16px;top:16px;bottom:90px;width:350px;max-width:calc(100vw - 32px);overflow:auto;padding:20px;background:white;border:1px solid #ccd6e4;border-radius:12px;box-shadow:0 10px 40px #14243a30}.panel h2{font-size:19px;margin:0 0 15px}.panel p{margin:10px 0;overflow-wrap:anywhere}.panel label{display:block;margin:12px 0}.panel input,.panel textarea,.panel select{display:block;width:100%;padding:10px;border:1px solid #bccbdb;border-radius:6px;margin-top:6px;background:white;color:#273140}.panel textarea{min-height:100px;resize:vertical}.row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.row h2{flex:1;margin:0}.muted{font-size:11px;color:#657387}.error{color:#a3313e;font-size:12px}.thread{display:block;width:100%;text-align:left;margin-top:10px;overflow-wrap:anywhere}.message{padding:12px 0;border-bottom:1px solid #e5ebf1;white-space:pre-wrap;overflow-wrap:anywhere}.message strong{font-size:12px}.message time{display:block;font-size:10px;color:#657387}.pin{position:fixed;transform:translate(-50%,-50%);border:2px solid white;box-shadow:0 0 0 1px #167dbd;width:28px;height:28px;padding:0;background:#167dbd;color:white;border-radius:50% 50% 3px 50%;font-size:11px}.hint{position:fixed;top:16px;left:16px;padding:10px 14px;background:#243447;color:white;border-radius:8px;max-width:calc(100vw - 32px);pointer-events:none}.outline{position:fixed;border:2px solid #1689d5;background:#1689d510;pointer-events:none}.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0)}[hidden]{display:none!important}
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
    const pins = el('div')
    const hint = el('div', 'Click or right-click an element · Esc to cancel', 'hint'); hint.hidden = true
    const outline = el('div', '', 'outline'); outline.hidden = true
    const live = el('div', '', 'sr'); live.setAttribute('role', 'status'); live.setAttribute('aria-live', 'polite')
    shadow.append(pins, outline, hint, bar, panel, live)
    document.body.append(host)
    let armed = false, threads = [], page = pageURL(), draft = null, selected = null, filter = 'open', frame = null, loading = false
    let panelMode = '', lastFocus = null, busy = false, countLabel = '', destroyed = false
    const announce = text => { live.textContent = text }
    const errorBox = () => { const node = el('p', '', 'error'); node.setAttribute('role', 'alert'); return node }
    const toggle = button('Add comment', () => setArmed(!armed), 'primary')
    const listButton = button('Threads', () => showList())
    const exit = button('Exit', () => { try { sessionStorage.removeItem(storageKey) } catch {} ; token = null; cleanup() })
    bar.append(el('strong', 'Fluently'), toggle, listButton, exit)
    const setArmed = value => {
      armed = value; hint.hidden = !value; outline.hidden = true
      hint.textContent = 'Click or right-click an element · Esc to cancel';
      toggle.textContent = value ? 'Cancel' : 'Add comment'; toggle.setAttribute('aria-pressed', String(value))
      if (value) { closePanel(); announce('Choose an element. Press Escape to cancel.') }
    }
    function openPanel(title, mode) {
      lastFocus = shadow.activeElement || document.activeElement
      panelMode = mode; panel.hidden = false; panel.replaceChildren()
      const heading = el('div', '', 'row')
      const h = el('h2', title); h.tabIndex = -1
      heading.append(h, button('Close', () => mode === 'join' ? cleanup() : closePanel())); panel.append(heading)
      h.focus()
    }
    function closePanel() { panel.hidden = true; panelMode = ''; draft = null; selected = null; if (lastFocus?.isConnected) lastFocus.focus({preventScroll:true}) }
    async function api(path, method = 'GET', data) {
      const response = await fetch(`${service}/api/projects/${encodeURIComponent(project)}${path}`, {
        method, mode: 'cors', credentials: 'omit', referrerPolicy: 'no-referrer',
        headers: {'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {})},
        body: data ? JSON.stringify(data) : undefined,
        signal: AbortSignal.timeout(15000)
      })
      const result = await response.json()
      if (!response.ok) { const error = new Error(result.error?.message || 'Request failed'); error.status = response.status; throw error }
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
    function nameForm() {
      bar.hidden = true
      openPanel('Join the review', 'join')
      panel.append(el('p', 'Choose a display name. Everyone with this project’s review link can see its feedback.'))
      const form = el('form'), label = el('label', 'Your display name'), input = el('input')
      input.required = true; input.maxLength = 80; input.autocomplete = 'nickname'; label.append(input)
      const send = el('button', 'Start reviewing', 'primary'); send.type = 'submit'
      const error = errorBox(); form.append(label, send, error); panel.append(form)
      form.addEventListener('submit', event => {
        event.preventDefault()
        submit(form, async () => {
          const result = await api('/sessions', 'POST', {token: invitation, name: input.value.trim()})
          token = result.token; invitation = null
          try { sessionStorage.setItem(storageKey, token) } catch { announce('Session storage unavailable. Reopen the invitation after reloading.') }
          bar.hidden = false; closePanel(); await refresh(true)
        }, error)
      })
      input.focus()
    }
    function position() {
      let hidden = 0
      const matching = threads.filter(t => t.status === filter)
      for (const [i, thread] of matching.entries()) {
        const pin = pins.children[i]
        if (!pin) continue
        const result = resolve(thread.anchor)
        pin.hidden = result.state !== 'resolved'
        if (pin.hidden) { hidden++; continue }
        const r = result.element.getBoundingClientRect()
        const x = r.left + r.width * thread.anchor.point.x, y = r.top + r.height * thread.anchor.point.y
        pin.hidden = x < 0 || x > innerWidth || y < 0 || y > innerHeight
        if (pin.hidden) hidden++
        pin.style.left = `${x}px`; pin.style.top = `${y}px`
      }
      const label = `${matching.length} ${filter} · ${hidden} hidden in this view`
      if (countLabel !== label) { listButton.textContent = label; countLabel = label }
    }
    function schedule() { if (!frame && !destroyed) frame = requestAnimationFrame(() => {frame = null; position()}) }
    function renderPins() {
      pins.replaceChildren()
      threads.filter(t => t.status === filter).forEach((thread, i) => {
        const pin = button(String(i + 1), () => showThread(thread), 'pin')
        pin.setAttribute('aria-label', `Open comment ${i + 1}: ${thread.messages[0]?.body.slice(0, 60) || ''}`)
        pins.append(pin)
      })
      position()
    }
    async function refresh(report = false) {
      if (!token || loading || destroyed) return
      loading = true
      const requestedPage = page
      try {
        let offset = 0, result, all = []
        do {
          result = await api(`/comments?page=${encodeURIComponent(requestedPage)}&offset=${offset}`)
          all.push(...result.data); offset = result.next_offset
        } while (offset !== null && all.length < 1000)
        if (requestedPage !== page || destroyed) return
        const previous = selected && threads.find(t => t.id === selected)
        threads = all; renderPins()
        const current = selected && threads.find(t => t.id === selected)
        if (panelMode === 'thread' && current && !panel.querySelector('textarea')?.value && JSON.stringify(previous) !== JSON.stringify(current)) showThread(current)
        if (panelMode === 'list') showList(false)
        if (report) announce('Feedback loaded.')
      } catch (e) {
        if (e.status === 401 || e.status === 403 || e.status === 404) { token = null; threads = []; renderPins(); setArmed(false); toggle.disabled = true; try { sessionStorage.removeItem(storageKey) } catch {} ; report = true }
        if (report) { openPanel('Feedback unavailable', 'error'); panel.append(el('p', e.message, 'error'), el('p', 'If the session expired or was revoked, reopen a current review link.')); }
      } finally { loading = false }
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
      for (const message of thread.messages) {
        const item = el('article', '', 'message')
        const time = el('time', new Date(message.created_at).toLocaleString()); time.dateTime = message.created_at
        item.append(el('strong', message.author.name), time, el('p', message.body)); panel.append(item)
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
        const snapshot = {anchor, context: context(), page: pageURL()}
        setArmed(false); openPanel('New comment', 'draft'); draft = snapshot
        panel.append(el('p', `Attached to ${anchor.target.feedback_id || anchor.target.id || anchor.target.tag}`, 'muted'))
        if (anchor.target.text) panel.append(el('p', `Target text included: “${anchor.target.text}”`, 'muted'))
        messageForm('What should change?', async body => {
          if (!draft || draft.page !== pageURL()) throw new Error('The page changed. Select the element again.')
          const result = await api('/comments', 'POST', {...draft, body})
          threads.push(result.data); filter = 'open'; renderPins(); showThread(result.data); announce('Comment posted.')
        })
      } catch (e) { announce(e.message); hint.textContent = e.message + ' · Esc to cancel' }
    }
    function blockHost(event) { if (armed && !event.composedPath().includes(host)) { event.stopImmediatePropagation(); event.preventDefault() } }
    function hover(event) {
      if (!armed || event.composedPath().includes(host)) return
      const rect = event.target.getBoundingClientRect()
      outline.hidden = false; outline.style.cssText = `left:${rect.left}px;top:${rect.top}px;width:${rect.width}px;height:${rect.height}px`
    }
    function keydown(event) { if (event.key === 'Escape') { setArmed(false); closePanel(); toggle.focus() } }
    window.addEventListener('click', choose, true)
    window.addEventListener('contextmenu', choose, true)
    for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup']) window.addEventListener(type, blockHost, true)
    window.addEventListener('pointermove', hover, true)
    window.addEventListener('keydown', keydown)
    window.addEventListener('scroll', schedule, true)
    window.addEventListener('resize', schedule)
    const observer = new MutationObserver(schedule)
    observer.observe(document.body, {subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'style', 'hidden', 'open', 'aria-expanded', 'data-feedback-id', 'data-feedback-exclude']})
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
      destroyed = true; clearInterval(timer); observer.disconnect(); resize.disconnect(); if (frame) cancelAnimationFrame(frame)
      window.removeEventListener('click', choose, true); window.removeEventListener('contextmenu', choose, true)
      for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup']) window.removeEventListener(type, blockHost, true)
      window.removeEventListener('pointermove', hover, true); window.removeEventListener('keydown', keydown)
      window.removeEventListener('scroll', schedule, true); window.removeEventListener('resize', schedule); host.remove()
    }
    if (invitation) nameForm()
    else await refresh(true)
  }
}

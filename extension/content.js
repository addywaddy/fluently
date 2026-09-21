import {startEmbed} from '../assets/embed/widget.js'
import {configuration, detect} from './config.mjs'

const key = `fluently-extension:${location.origin}`
let starting = false
let previous = ''

function state() {
  const configs = detect(document)
  const running = !!document.querySelector('fluently-feedback')
  return {configs, running, installed: running || !!document.querySelector('script[data-demo="true"][src*="embed"]') || configs.length > 0}
}

async function report() {
  const status = state()
  const signature = JSON.stringify(status)
  if (signature === previous) return
  previous = signature
  try { await chrome.runtime.sendMessage({type: 'detected', installed: status.installed}) } catch { /* extension reloaded */ }
}

async function launch(config, explicit) {
  const existing = document.querySelector('fluently-feedback')
  if (existing) {
    // Reuse even older website widgets instead of mounting a second instance.
    const button = existing.shadowRoot?.querySelector('.launcher')
    if (explicit && button && !button.disabled && button.getAttribute('aria-pressed') !== 'true') button.click()
    return
  }
  if (starting) return
  starting = true
  try {
    const installedScript = Array.from(document.querySelectorAll('script[src][data-project]')).find(script => {
      try { return script.dataset.project === config.project && new URL(script.src).origin === config.service } catch { return false }
    })
    // Keep the live dataset when installed, preserving host-session change detection.
    const script = installedScript || {src: config.service + '/embed.js', dataset: {...config.attributes, project: config.project}}
    await startEmbed(script, {activate: explicit})
  } finally { starting = false; report() }
}

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id) return
  if (message.type === 'status') { respond(state()); return }
  if (message.type !== 'start') return
  const config = configuration(message.config?.service, message.config?.project, message.config?.attributes)
  if (!config && !document.querySelector('fluently-feedback')) { respond({error: 'Choose a valid Fluently service origin and project ID.'}); return }
  ;(async () => {
    if (config) await chrome.storage.local.set({[key]: config})
    await launch(config, true)
    respond({ok: true})
  })().catch(() => respond({error: 'Unable to start Fluently. Reload the page and try again.'}))
  return true
})

window.addEventListener('fluently:exit', () => chrome.storage.local.remove(key))
let queued = false
new MutationObserver(() => {
  if (queued) return
  queued = true
  setTimeout(() => { queued = false; report() }, 150)
}).observe(document.documentElement, {childList: true, subtree: true, attributes: true, attributeFilter: ['src', 'data-project', 'data-demo']})
report()

// Only previously activated sites resume. No background requests to Fluently on other sites.
chrome.storage.local.get(key).then(async saved => {
  const value = saved[key]
  const config = value && configuration(value.service, value.project, value.attributes)
  if (!config) return
  const installed = detect(document)
  // Prefer current host configuration so host identity changes still reset the widget.
  const current = installed.find(item => item.service === config.service && item.project === config.project)
  await launch(current || config, new URLSearchParams(location.hash.slice(1)).has('fluently_state'))
}).catch(() => {})

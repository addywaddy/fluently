import {configuration} from './config.mjs'
const extensionAPI = globalThis.browser || globalThis.chrome
const $ = id => document.getElementById(id)
let tab, configs = [], running = false
const fill = config => { $('service').value = config.service; $('project').value = config.project }
try {
  ;[tab] = await extensionAPI.tabs.query({active: true, currentWindow: true})
  const status = await extensionAPI.tabs.sendMessage(tab.id, {type: 'status'})
  configs = status.configs
  running = status.running
  $('status').textContent = status.installed ? 'Fluently is available on this page.' : 'No snippet detected. You can start Fluently here with a project configured for this website.'
  if (running) {
    $('configuration').hidden = true
    $('project').required = false
    $('service').required = false
  }
  if (configs.length) {
    fill(configs[0])
    for (const config of configs) {
      const option = document.createElement('option')
      option.value = String(configs.indexOf(config)); option.textContent = `${config.service} · ${config.project}`
      $('projects').append(option)
    }
    $('projects-label').hidden = configs.length < 2
  } else {
    const key = `fluently-extension:${new URL(tab.url).origin}`
    const saved = (await extensionAPI.storage.local.get(key))[key]
    if (saved) fill(saved)
    $('configuration').open = !saved
  }
  $('start-form').hidden = false
} catch {
  $('status').textContent = 'This page is unavailable. Allow this extension to access the site, then reload it. Browser internal pages and protected extension-store pages cannot be reviewed.'
}
$('projects').addEventListener('change', () => fill(configs[Number($('projects').value)]))
$('start-form').addEventListener('submit', async event => {
  event.preventDefault()
  $('error').textContent = ''
  const matching = configs.find(config => config.service === $('service').value && config.project === $('project').value)
  const config = configuration($('service').value.trim(), $('project').value.trim(), matching?.attributes)
  if (!config && !running) { $('configuration').open = true; $('error').textContent = 'Enter an HTTPS service origin (HTTP allowed on localhost) and a valid project UUID.'; return }
  $('start').disabled = true
  try {
    const result = await extensionAPI.tabs.sendMessage(tab.id, {type: 'start', config})
    if (result.error) throw new Error(result.error)
    window.close()
  } catch (error) { $('error').textContent = error.message }
  finally { $('start').disabled = false }
})

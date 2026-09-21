const extensionAPI = globalThis.browser || globalThis.chrome
extensionAPI.runtime.onMessage.addListener((message, sender) => {
  if (sender.id !== extensionAPI.runtime.id || sender.frameId !== 0 || !sender.tab || message.type !== 'detected') return
  const color = message.installed === true ? 'blue' : 'gray'
  extensionAPI.action.setIcon({tabId: sender.tab.id, path: {16: `icons/${color}-16.png`, 32: `icons/${color}-32.png`}}).catch(() => {})
  extensionAPI.action.setTitle({tabId: sender.tab.id, title: color === 'blue' ? 'Fluently — available on this page' : 'Fluently — not detected'}).catch(() => {})
})

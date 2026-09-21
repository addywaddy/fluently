chrome.runtime.onMessage.addListener((message, sender) => {
  if (sender.id !== chrome.runtime.id || sender.frameId !== 0 || !sender.tab || message.type !== 'detected') return
  const color = message.installed === true ? 'blue' : 'gray'
  chrome.action.setIcon({tabId: sender.tab.id, path: {16: `icons/${color}-16.png`, 32: `icons/${color}-32.png`}}).catch(() => {})
  chrome.action.setTitle({tabId: sender.tab.id, title: color === 'blue' ? 'Fluently — available on this page' : 'Fluently — not detected'}).catch(() => {})
})

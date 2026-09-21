const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const options = ['captureText', 'screenshots', 'styleNonce', 'sessionKey', 'userSelector', 'userAttribute']

export function configuration(service, project, dataset = {}) {
  try {
    const url = new URL(service)
    const local = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)
    if (!(url.protocol === 'https:' || (url.protocol === 'http:' && local)) ||
        url.username || url.password || url.search || url.hash || url.pathname !== '/' || !uuid.test(project)) return null
    const attributes = Object.fromEntries(options.filter(key => typeof dataset[key] === 'string').map(key => [key, dataset[key].slice(0, 256)]))
    return {service: url.origin, project, attributes}
  } catch { return null }
}

export function detect(root) {
  const found = []
  for (const script of root.querySelectorAll('script[src][data-project]')) {
    try {
      const url = new URL(script.src)
      if (!/\/embed(?:-[a-f0-9]+)?\.js$/.test(url.pathname)) continue
      const config = configuration(url.origin, script.dataset.project, script.dataset)
      if (config && !found.some(item => item.service === config.service && item.project === config.project)) found.push(config)
    } catch { /* malformed page markup */ }
  }
  return found
}

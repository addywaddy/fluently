const nonce = () => {
  const bytes = crypto.getRandomValues(new Uint8Array(32))
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')
}

export async function startConnection({service, project, returnTo, storage, key, invitation, hostKey}) {
  const state = nonce(), verifier = nonce()
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))
  const challenge = btoa(String.fromCharCode(...new Uint8Array(digest))).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')
  storage.setItem(key, JSON.stringify({state, verifier, invitation, hostKey, returnTo, created: Date.now()}))
  const url = new URL('/review/connect', service)
  url.search = new URLSearchParams({project, return_to: returnTo, state, challenge})
  return url.href
}

export function consumeConnection({storage, key, state, hostKey, now = Date.now()}) {
  const raw = storage.getItem(key)
  storage.removeItem(key)
  try {
    const pending = JSON.parse(raw)
    if (!pending || !state || pending.state !== state || pending.hostKey !== hostKey ||
        now - pending.created < 0 || now - pending.created > 600000) return null
    return pending
  } catch { return null }
}

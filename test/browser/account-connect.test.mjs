import {test} from 'node:test'
import assert from 'node:assert/strict'
import {createServer} from 'node:http'
import {readFile} from 'node:fs/promises'
import {createHash} from 'node:crypto'
import {webkit} from 'playwright'

test('WebKit account connection keeps credentials out of URLs and revokes on host-user change', async () => {
  const bundle = await readFile(new URL('../../priv/static/embed.js', import.meta.url))
  let serviceOrigin, hostOrigin, challenge, exchange, revoked, thread
  const token = 'account-review-token'
  const service = createServer(async (req, res) => {
    const url = new URL(req.url, serviceOrigin)
    if (url.pathname === '/embed.js') return res.writeHead(200, {'Content-Type': 'text/javascript'}).end(bundle)
    if (url.pathname === '/review/connect') {
      challenge = url.searchParams.get('challenge')
      const back = new URL(url.searchParams.get('return_to'))
      back.hash = new URLSearchParams({fluently_code: 'one-use-code', fluently_state: url.searchParams.get('state')})
      return res.writeHead(200, {'Content-Type': 'text/html', 'Set-Cookie': 'account=first-party-login; Path=/; SameSite=Lax'})
        .end(`<a href="${back.href.replaceAll('&', '&amp;')}">Continue as Owner</a>`)
    }
    res.setHeader('Access-Control-Allow-Origin', hostOrigin)
    res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type')
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
    if (req.method === 'OPTIONS') return res.writeHead(204).end()
    res.setHeader('Content-Type', 'application/json')
    let body = ''
    for await (const chunk of req) body += chunk
    if (url.pathname.endsWith('/account-sessions')) {
      exchange = {body: JSON.parse(body), cookie: req.headers.cookie, origin: req.headers.origin, referer: req.headers.referer}
      return res.end(JSON.stringify({token, reviewer: {name: 'Owner', kind: 'account'}}))
    }
    if (url.pathname.endsWith('/session')) {
      revoked = req.headers.authorization
      return res.writeHead(204).end()
    }
    if (req.method === 'POST') {
      thread = {...JSON.parse(body), id: 'thread', status: 'open', snapshot: null,
        messages: [{id: 'message', body: 'Account feedback', author: {name: 'Owner'}, created_at: new Date().toISOString(), can_delete: true}]}
      return res.writeHead(201).end(JSON.stringify({data: thread}))
    }
    res.end(JSON.stringify({identity: {name: 'Owner', kind: 'account'}, data: thread ? [thread] : [], next_offset: null}))
  })
  const host = createServer((req, res) => res.writeHead(200, {'Content-Type': 'text/html'})
    .end(`<h1 data-feedback-id="title">Customer checkout</h1><script defer src="${serviceOrigin}/embed.js" data-project="project-1" data-session-key="host-user-A"></script>`))
  let browser
  try {
    await new Promise(resolve => service.listen(0, '127.0.0.1', resolve))
    serviceOrigin = `http://127.0.0.1:${service.address().port}`
    await new Promise(resolve => host.listen(0, '127.0.0.1', resolve))
    hostOrigin = `http://localhost:${host.address().port}`
    browser = await webkit.launch()
    const page = await browser.newPage()
    page.setDefaultTimeout(15000)
    await page.goto(hostOrigin + '/checkout#fluently_account=1')
    await page.getByRole('button', {name: 'Continue with Fluently', exact: true}).click()
    await page.getByRole('link', {name: 'Continue as Owner'}).click()
    await page.getByText('Feedback loaded.', {exact: true}).waitFor()
    assert.equal(exchange.origin, hostOrigin)
    assert.equal(exchange.cookie, undefined, 'API must not use Fluently cookies')
    assert.equal(exchange.referer, undefined)
    assert.equal(createHash('sha256').update(exchange.body.verifier).digest('base64url'), challenge)
    assert.equal(new URL(page.url()).hash, '')
    assert.ok(!page.url().includes(token))
    await page.reload()
    await page.getByText('Feedback loaded.', {exact: true}).waitFor()
    await page.getByRole('button', {name: 'Commenting: off'}).click()
    await page.getByRole('button', {name: 'Add comment', exact: true}).click()
    await page.locator('h1').click()
    await page.locator('fluently-feedback').locator('.panel').getByText('Commenting as Owner', {exact: true}).waitFor()
    await page.getByLabel('What should change?').fill('Account feedback')
    await page.getByRole('button', {name: 'Post comment', exact: true}).click()
    await page.getByText('Comment posted.', {exact: true}).waitFor()
    const ended = page.waitForResponse(r => r.request().method() === 'DELETE')
    await page.evaluate(() => { document.querySelector('script[data-project]').dataset.sessionKey = 'host-user-B' })
    await ended
    assert.equal(revoked, `Bearer ${token}`)
    assert.equal(await page.locator('fluently-feedback').count(), 0)
    assert.equal(await page.evaluate(key => sessionStorage.getItem(key), `fluently:${serviceOrigin}:project-1`), null)
  } finally {
    await browser?.close()
    await Promise.all([new Promise(resolve => service.close(resolve)), new Promise(resolve => host.close(resolve))])
  }
})

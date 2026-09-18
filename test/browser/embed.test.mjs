import {test} from 'node:test'
import assert from 'node:assert/strict'
import {createServer} from 'node:http'
import {readFile} from 'node:fs/promises'
import {webkit} from 'playwright'

test('WebKit posts landing feedback with a real origin, CSRF token, and session cookie', async () => {
  const bundle = await readFile(new URL('../../priv/static/embed.js', import.meta.url))
  let origin, received, thread
  const server = createServer(async (req, res) => {
    if (req.url === '/embed.js') {
      res.writeHead(200, {'Content-Type': 'text/javascript'}).end(bundle)
    } else if (req.url.startsWith('/demo/comments')) {
      res.setHeader('Content-Type', 'application/json')
      if (req.method === 'POST') {
        let body = ''
        for await (const chunk of req) body += chunk
        received = {origin: req.headers.origin, referer: req.headers.referer,
          csrf: req.headers['x-csrf-token'], cookie: req.headers.cookie}
        if (received.origin !== origin) {
          res.writeHead(403).end(JSON.stringify({error: {message: 'Origin not allowed'}}))
          return
        }
        const attrs = JSON.parse(body)
        thread = {...attrs, id: 'thread-1', status: 'open', snapshot: null,
          messages: [{id: 'message-1', body: attrs.body, can_delete: true,
            author: {name: 'Visitor'}, created_at: new Date().toISOString()}]}
        res.writeHead(201).end(JSON.stringify({data: thread}))
      } else {
        res.end(JSON.stringify({data: thread ? [thread] : [], registered: false, next_offset: null}))
      }
    } else {
      res.writeHead(200, {'Content-Type': 'text/html', 'Referrer-Policy': 'no-referrer',
        'Set-Cookie': 'session=browser-test; HttpOnly; SameSite=Lax; Path=/'}).end(`
        <!doctype html><meta name="csrf-token" content="browser-csrf">
        <h1 data-feedback-id="hero">Feedback target</h1>
        <script defer src="/embed.js" data-demo="true" data-screenshots="false"></script>`)
    }
  })
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
  origin = `http://127.0.0.1:${server.address().port}`
  let browser
  try {
    browser = await webkit.launch()
    const page = await browser.newPage()
    page.setDefaultTimeout(15000)
    await page.goto(origin + '/private-path?secret=not-for-headers')
    await page.getByRole('button', {name: 'Commenting: off'}).click()
    await page.getByRole('button', {name: 'Add comment', exact: true}).click()
    await page.locator('h1').click()
    await page.getByLabel('What should change?').fill('Safari feedback')
    const response = page.waitForResponse(r => r.request().method() === 'POST' && r.url().endsWith('/demo/comments'))
    await page.getByRole('button', {name: 'Post comment', exact: true}).click()
    const result = await response
    assert.equal(received.origin, origin, `Browser sent Origin: ${received.origin}`)
    assert.equal(received.referer, origin + '/', 'Do not send page paths or query strings')
    assert.equal(received.csrf, 'browser-csrf')
    assert.match(received.cookie, /session=browser-test/)
    assert.equal(result.status(), 201)
    await page.getByText('Comment posted.', {exact: true}).waitFor()
  } finally {
    await browser?.close()
    await new Promise(resolve => server.close(resolve))
  }
})

test('WebKit snapshots embed used webfonts without credentials or host stylesheet mutations', async () => {
  const bundle = await readFile(new URL('../../priv/static/embed.js', import.meta.url))
  const font = await readFile(new URL('../../priv/static/fonts/afacad-latin.woff2', import.meta.url))
  let origin, assetOrigin, capturing = false
  const requests = []
  const assets = createServer((req, res) => {
    if (capturing) requests.push({path: req.url, cookie: req.headers.cookie, referer: req.headers.referer})
    res.setHeader('Access-Control-Allow-Origin', '*')
    res.setHeader('Cache-Control', 'no-store')
    if (req.url === '/fonts.css' || req.url === '/nested.css') {
      res.writeHead(200, {'Content-Type': 'text/css'}).end(req.url === '/fonts.css' ? '@import url("/nested.css");' : `
        @font-face {font-family: CaptureFont; src: url('/used.woff2') format('woff2')}
        @font-face {font-family: PrivateFont; src: url('/private.woff2') format('woff2')}
        h1 {font-family: CaptureFont; font-size: 40px}
        .private {font-family: PrivateFont}`)
    } else {
      res.writeHead(200, {'Content-Type': 'font/woff2'}).end(font)
    }
  })
  const server = createServer((req, res) => {
    if (req.url === '/embed.js') res.writeHead(200, {'Content-Type': 'text/javascript'}).end(bundle)
    else if (req.url.startsWith('/demo/comments')) res.writeHead(200, {'Content-Type': 'application/json'}).end('{"data":[],"registered":false,"next_offset":null}')
    else res.writeHead(200, {'Content-Type': 'text/html', 'Set-Cookie': 'private_session=do-not-send; Path=/; HttpOnly'}).end(`
      <!doctype html><meta name="csrf-token" content="test"><link rel="stylesheet" href="${assetOrigin}/fonts.css">
      <style>body {margin: 40px}</style>
      <h1 data-feedback-id="hero">Capture this font</h1><span class="private" data-feedback-exclude>Private</span>
      <script defer src="/embed.js" data-demo="true"></script>`)
  })
  await new Promise(resolve => assets.listen(0, '127.0.0.1', resolve))
  assetOrigin = `http://127.0.0.1:${assets.address().port}`
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
  origin = `http://127.0.0.1:${server.address().port}`
  let browser
  try {
    browser = await webkit.launch()
    const page = await browser.newPage()
    page.setDefaultTimeout(15000)
    await page.goto(origin + '/private-path?secret=hidden')
    await page.evaluate(() => document.fonts.ready)
    const styles = () => page.evaluate(() => Array.from(document.styleSheets, s => {
      try {return Array.from(s.cssRules, r => r.cssText)} catch {return s.href}
    }))
    const before = await styles()
    await page.getByRole('button', {name: 'Commenting: off'}).click()
    await page.getByRole('button', {name: 'Add comment', exact: true}).click()
    await page.locator('h1').click({position: {x: 10, y: 10}})
    capturing = true
    await page.getByRole('button', {name: 'Attach element snapshot'}).click()
    await page.getByRole('button', {name: 'Remove snapshot'}).waitFor()
    assert.deepEqual(await styles(), before)
    assert.ok(requests.some(r => r.path === '/fonts.css'), 'Scan inaccessible stylesheet via CORS')
    assert.ok(requests.some(r => r.path === '/used.woff2'), 'Embed the selected font')
    assert.ok(!requests.some(r => r.path === '/private.woff2'), 'Do not embed excluded content fonts')
    for (const request of requests) {
      assert.equal(request.cookie, undefined)
      assert.equal(request.referer, undefined)
    }
  } finally {
    await browser?.close()
    await Promise.all([server, assets].map(s => new Promise(resolve => s.close(resolve))))
  }
})

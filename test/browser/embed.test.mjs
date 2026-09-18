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

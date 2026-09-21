import {test} from 'node:test'
import assert from 'node:assert/strict'
import {createServer} from 'node:http'
import {readFile, mkdtemp, rm} from 'node:fs/promises'
import {tmpdir} from 'node:os'
import {join, resolve} from 'node:path'
import {chromium} from 'playwright'

test('packaged extension detects, activates, reconnects and reuses the widget on installed and uninstalled sites', {timeout: 90000}, async () => {
  const project = '0ffa2549-1dfd-4d5c-8e0a-52c2357f4de5'
  const bundle = await readFile(new URL('../../priv/static/embed.js', import.meta.url))
  let origin, serviceOrigin, requests = 0
  const service = createServer(async (req, res) => {
    const url = new URL(req.url, serviceOrigin)
    if (url.pathname === '/embed.js') return res.writeHead(200, {'Content-Type':'text/javascript'}).end(bundle)
    requests++
    if (url.pathname === '/review/connect') {
      const back = new URL(url.searchParams.get('return_to'))
      back.hash = new URLSearchParams({fluently_code:'one-use-code', fluently_state:url.searchParams.get('state')})
      return res.writeHead(200, {'Content-Type':'text/html'}).end(`<a href="${back.href.replaceAll('&', '&amp;')}">Continue as Owner</a>`)
    }
    res.setHeader('Access-Control-Allow-Origin', origin)
    res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type')
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
    if (req.method === 'OPTIONS') return res.writeHead(204).end()
    res.setHeader('Content-Type','application/json')
    if (url.pathname.endsWith('/account-sessions')) return res.end(JSON.stringify({token:'review-token', reviewer:{name:'Owner', kind:'account'}}))
    res.end(JSON.stringify({data:[], next_offset:null, identity:{name:'Owner', kind:'account'}}))
  })
  const host = createServer((req, res) => res.writeHead(200, {'Content-Type':'text/html'}).end(
    `<h1 data-feedback-id="title">Checkout</h1>${req.url.startsWith('/installed') ? `<script defer src="${serviceOrigin}/embed.js" data-project="${project}"></script>` : ''}`))
  const directory = await mkdtemp(join(tmpdir(), 'fluently-extension-'))
  let browser
  try {
    await new Promise(done => service.listen(0, '127.0.0.1', done))
    serviceOrigin = `http://127.0.0.1:${service.address().port}`
    await new Promise(done => host.listen(0, '127.0.0.1', done))
    origin = `http://localhost:${host.address().port}`
    const extension = resolve('extension/dist')
    browser = await chromium.launchPersistentContext(directory, {channel:'chromium', headless:true,
      args:[`--disable-extensions-except=${extension}`, `--load-extension=${extension}`]})
    const worker = browser.serviceWorkers()[0] || await browser.waitForEvent('serviceworker')
    const page = await browser.newPage()
    page.setDefaultTimeout(15000)
    let reviewTabId
    async function command(message) {
      const response = await worker.evaluate(async ({reviewTabId, message}) => {
        const deadline = Date.now() + 10000
        while (Date.now() < deadline) {
          const tabs = reviewTabId ? [{id:reviewTabId}] : await chrome.tabs.query({})
          for (const tab of tabs) {
            try {
              await chrome.tabs.sendMessage(tab.id, {type:'status'})
              return {tabId:tab.id, result:await chrome.tabs.sendMessage(tab.id, message)}
            } catch {}
          }
          await new Promise(done => setTimeout(done, 100))
        }
        throw new Error('Content script unavailable')
      }, {reviewTabId, message})
      reviewTabId = response.tabId
      return response.result
    }
    await page.goto(origin + '/installed')
    assert.equal((await command({type:'status'})).installed, true)
    assert.equal(requests, 0, 'Detection does not contact the backend')
    assert.equal((await command({type:'start', config:{service:serviceOrigin, project}})).ok, true)
    await page.getByRole('button', {name:'Continue with Fluently', exact:true}).click()
    await page.getByRole('link', {name:'Continue as Owner'}).click()
    await page.getByText('Feedback loaded.', {exact:true}).waitFor()
    assert.equal(await page.locator('fluently-feedback').count(), 1)
    await command({type:'start', config:{service:serviceOrigin, project}})
    await page.getByRole('button', {name:'Commenting: on', exact:true}).waitFor()
    await page.getByRole('button', {name:'Add comment', exact:true}).click()
    await page.locator('h1').click()
    await page.getByLabel('What should change?').waitFor()
    await page.reload()
    await page.getByText('Feedback loaded.', {exact:true}).waitFor()
    assert.equal(await page.locator('fluently-feedback').count(), 1)

    // End the saved session, then exercise the bundled widget without a website script.
    await command({type:'start', config:{service:serviceOrigin, project}})
    await page.getByRole('button', {name:'Exit', exact:true}).click()
    await page.goto(origin + '/plain')
    assert.equal((await command({type:'status'})).installed, false)
    await command({type:'start', config:{service:serviceOrigin, project}})
    await page.getByRole('button', {name:'Continue with Fluently', exact:true}).click()
    await page.getByRole('link', {name:'Continue as Owner'}).click()
    await page.getByText('Feedback loaded.', {exact:true}).waitFor()
    await page.getByRole('button', {name:'Commenting: on', exact:true}).waitFor()
    assert.equal(await page.locator('fluently-feedback').count(), 1)
    await page.reload()
    await page.getByText('Feedback loaded.', {exact:true}).waitFor()
    assert.equal(await page.locator('script[data-project]').count(), 0)
    assert.equal(await page.locator('fluently-feedback').count(), 1)
  } finally {
    await browser?.close()
    await Promise.all([new Promise(done => service.close(done)), new Promise(done => host.close(done))])
    await rm(directory, {recursive:true, force:true})
  }
})

import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import vm from 'node:vm'

const code = await readFile(new URL('../../extension/dist/content.js', import.meta.url), 'utf8')
const project = '0ffa2549-1dfd-4d5c-8e0a-52c2357f4de5'
function harness({installed = false, running = false, apiName = 'chrome'} = {}) {
  let listener, pressed = false, clicks = 0
  const sent = [], stored = {}, events = {}
  const button = {disabled:false, getAttribute: () => String(pressed), click: () => { pressed = true; clicks++ }}
  const host = {shadowRoot: {querySelector: () => button}}
  const scripts = installed ? [{src:'http://localhost:4000/embed.js', dataset:{project}}] : []
  vm.runInNewContext(code, {
    URL, URLSearchParams, console, setTimeout,
    location:{origin:'http://localhost:8000', hash:''},
    document:{documentElement:{}, querySelectorAll: () => scripts, querySelector: selector => selector === 'fluently-feedback' && running ? host : null},
    window:{addEventListener: (name, callback) => events[name] = callback},
    MutationObserver: class { observe() {} },
    [apiName]:{runtime:{id:'test-extension', onMessage:{addListener: fn => listener = fn}, sendMessage: async message => sent.push(message)},
      storage:{local:{get: async () => ({}), set: async values => Object.assign(stored, values), remove: async key => delete stored[key]}}}
  })
  return {sent, stored, events, clicks: () => clicks, message: (message, id = 'test-extension') => new Promise(resolve => {
    const result = listener(message, {id}, resolve)
    if (result !== true) resolve(undefined)
  })}
}

test('inactive pages only report detection and do not store configuration', async () => {
  const plain = harness()
  assert.equal(plain.sent[0].installed, false)
  assert.deepEqual(plain.stored, {})
  const installed = harness({installed:true})
  assert.equal(installed.sent[0].installed, true)
  const status = await installed.message({type:'status'})
  assert.equal(status.configs[0].project, project)
  assert.equal(status.running, false)
})

test('activation reuses an existing widget and Exit forgets configuration', async () => {
  const page = harness({installed:true, running:true})
  const config = {service:'http://localhost:4000', project}
  assert.equal((await page.message({type:'start', config})).ok, true)
  assert.equal(page.clicks(), 1)
  assert.equal((await page.message({type:'start', config})).ok, true)
  assert.equal(page.clicks(), 1)
  assert.equal(page.stored['fluently-extension:http://localhost:8000'].project, project)
  await page.events['fluently:exit']()
  assert.deepEqual(page.stored, {})
})

test('invalid configurations fail without activation and other extension messages are ignored', async () => {
  const page = harness()
  assert.match((await page.message({type:'start', config:{service:'http://evil.test', project}})).error, /valid/)
  assert.equal(await page.message({type:'status'}, 'other-extension'), undefined)
  assert.deepEqual(page.stored, {})
})

test('Firefox/Safari browser namespace supports detection, activation and cleanup without chrome', async () => {
  const page = harness({apiName:'browser', installed:true, running:true})
  assert.equal(page.sent[0].installed, true)
  assert.equal((await page.message({type:'status'})).configs[0].project, project)
  assert.equal((await page.message({type:'start', config:{service:'https://fluently.now', project}})).ok, true)
  assert.equal(page.clicks(), 1)
  await page.events['fluently:exit']()
  assert.deepEqual(page.stored, {})
})

test('background icon updates are scoped to the top-level sending tab', async () => {
  let listener
  const icons = [], titles = []
  vm.runInNewContext(await readFile(new URL('../../extension/background.js', import.meta.url), 'utf8'), {
    chrome:{runtime:{id:'test', onMessage:{addListener: fn => listener = fn}},
      action:{setIcon: async value => icons.push(value), setTitle: async value => titles.push(value)}}
  })
  listener({type:'detected', installed:true}, {id:'test', frameId:0, tab:{id:7}})
  assert.equal(icons[0].tabId, 7)
  assert.equal(icons[0].path[16], 'icons/blue-16.png')
  listener({type:'detected', installed:false}, {id:'test', frameId:0, tab:{id:7}})
  assert.equal(icons[1].path[16], 'icons/gray-16.png')
  listener({type:'detected', installed:true}, {id:'test', frameId:2, tab:{id:7}})
  assert.equal(icons.length, 2)
  assert.equal(titles.length, 2)
})

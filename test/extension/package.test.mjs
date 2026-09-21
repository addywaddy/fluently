import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
const root = new URL('../../extension/dist/', import.meta.url)

test('Chrome package contains bundled widget/snapshot code and local icons without remote script loading', async () => {
  const manifest = JSON.parse(await readFile(new URL('manifest.json', root)))
  assert.equal(manifest.manifest_version, 3)
  assert.deepEqual(manifest.permissions, ['storage', 'activeTab'])
  assert.equal(manifest.content_scripts[0].all_frames, false)
  assert.equal(manifest.web_accessible_resources, undefined)
  const widget = await readFile(new URL('content.js', root), 'utf8')
  assert.match(widget, /Continue with Fluently/)
  assert.match(widget, /Attach element snapshot/)
  assert.doesNotMatch(widget, /\bimport\s*\(/)
  for (const color of ['gray','blue']) for (const size of [16,32,48,128]) {
    const png = await readFile(new URL(`icons/${color}-${size}.png`, root))
    assert.equal(png.readUInt32BE(16), size)
    assert.equal(png.readUInt32BE(20), size)
  }
  const popup = await readFile(new URL('popup.html', root), 'utf8')
  assert.doesNotMatch(popup, /<script[^>]+src=["']https?:/)
})

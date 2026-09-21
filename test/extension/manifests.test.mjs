import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import {manifestFor} from '../../extension/manifests.mjs'
const base = JSON.parse(await readFile(new URL('../../extension/manifest.json', import.meta.url)))

test('browser manifests use their supported background execution model without changing shared permissions', () => {
  const firefox = manifestFor(base, 'firefox')
  assert.equal(firefox.background.service_worker, undefined)
  assert.deepEqual(firefox.background.scripts, ['background.js'])
  assert.equal(firefox.browser_specific_settings.gecko.id, 'fluently@fluently.now')
  assert.deepEqual(manifestFor(base, 'safari').background, {scripts:['background.js']})
  assert.deepEqual(manifestFor(base, 'edge'), base)
  for (const browser of ['chrome','edge','firefox','safari']) {
    const manifest = manifestFor(base, browser)
    assert.deepEqual(manifest.permissions, base.permissions)
    assert.deepEqual(manifest.content_scripts, base.content_scripts)
    assert.deepEqual(manifest.content_security_policy, base.content_security_policy)
  }
  assert.equal(base.browser_specific_settings, undefined)
  assert.throws(() => manifestFor(base, 'explorer'), /Unsupported/)
})

test('all generated browser packages include identical shared widget and popup code', async () => {
  const root = new URL('../../extension/', import.meta.url)
  for (const browser of ['edge','firefox','safari']) {
    const destination = new URL(`builds/${browser}/`, root)
    const manifest = JSON.parse(await readFile(new URL('manifest.json', destination)))
    assert.deepEqual(manifest, manifestFor(base, browser))
    for (const file of ['content.js','background.js','popup.js','popup.html','config.mjs','icons/blue-32.png','icons/gray-32.png']) {
      assert.deepEqual(await readFile(new URL(file, destination)), await readFile(new URL(`dist/${file}`, root)))
    }
  }
})

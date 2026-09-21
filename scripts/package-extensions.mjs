import {mkdir, readFile, writeFile, copyFile, cp} from 'node:fs/promises'
import {manifestFor} from '../extension/manifests.mjs'

const root = new URL('../extension/', import.meta.url)
const base = JSON.parse(await readFile(new URL('manifest.json', root)))
const source = new URL('dist/', root)
const files = ['content.js', 'background.js', 'popup.html', 'popup.css', 'popup.js', 'config.mjs']
for (const browser of ['edge', 'firefox', 'safari']) {
  const destination = new URL(`builds/${browser}/`, root)
  await mkdir(destination, {recursive: true})
  for (const file of files) await copyFile(new URL(file, source), new URL(file, destination))
  await cp(new URL('icons/', source), new URL('icons/', destination), {recursive: true})
  await writeFile(new URL('manifest.json', destination), JSON.stringify(manifestFor(base, browser), null, 2) + '\n')
  console.log(`Built ${browser}: extension/builds/${browser}`)
}

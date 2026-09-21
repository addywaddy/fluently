import {mkdir, copyFile, writeFile} from 'node:fs/promises'
import {deflateSync} from 'node:zlib'
import {fileURLToPath} from 'node:url'

const root = new URL('../extension/', import.meta.url)
const dest = new URL('dist/', root)
await mkdir(new URL('icons/', dest), {recursive: true})
for (const file of ['manifest.json', 'background.js', 'popup.html', 'popup.css', 'popup.js', 'config.mjs']) {
  await copyFile(new URL(file, root), new URL(file, dest))
}

// Rasterize a small circle/wave rendition of the existing Fluently mark without
// adding a runtime dependency or relying on OS-specific SVG conversion tools.
function crc32(bytes) {
  let crc = 0xffffffff
  for (const byte of bytes) {
    crc ^= byte
    for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0)
  }
  return (crc ^ 0xffffffff) >>> 0
}
function chunk(type, bytes) {
  const name = Buffer.from(type), size = Buffer.alloc(4), crc = Buffer.alloc(4)
  size.writeUInt32BE(bytes.length); crc.writeUInt32BE(crc32(Buffer.concat([name, bytes])))
  return Buffer.concat([size, name, bytes, crc])
}
function icon(size, gray) {
  const raw = Buffer.alloc(size * (size * 4 + 1))
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const channels = [0, 0, 0, 0]
    for (let sy = 0; sy < 4; sy++) for (let sx = 0; sx < 4; sx++) {
      const u = (x + (sx + .5) / 4) / size, v = (y + (sy + .5) / 4) / size
      if (Math.hypot(u - .5, v - .5) > .48) continue
      const wave = .49 + .12 * Math.sin((u - .12) * Math.PI * 4)
      const rgb = Math.abs(v - wave) < .045 ? [255, 255, 255] :
        Math.abs(v - wave - .10) < .06 ? (gray ? [192, 198, 207] : [147, 212, 255]) :
        (gray ? [103, 116, 137] : [32, 147, 223])
      rgb.forEach((value, i) => channels[i] += value)
      channels[3]++
    }
    const at = y * (size * 4 + 1) + 1 + x * 4
    for (let i = 0; i < 3; i++) raw[at + i] = channels[3] ? Math.round(channels[i] / channels[3]) : 0
    raw[at + 3] = Math.round(channels[3] * 255 / 16)
  }
  const header = Buffer.alloc(13)
  header.writeUInt32BE(size); header.writeUInt32BE(size, 4); header[8] = 8; header[9] = 6
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), chunk('IHDR', header), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0))])
}
for (const color of ['gray', 'blue']) for (const size of [16, 32, 48, 128]) {
  await writeFile(new URL(`icons/${color}-${size}.png`, dest), icon(size, color === 'gray'))
}
console.log(`Extension files prepared in ${fileURLToPath(dest)}`)

import {spawnSync} from 'node:child_process'
import {fileURLToPath} from 'node:url'
import {access, readFile, writeFile} from 'node:fs/promises'

if (process.platform !== 'darwin') throw new Error('Safari packaging requires macOS and Xcode.')
const root = new URL('../extension/', import.meta.url)
const destination = fileURLToPath(new URL('safari/', root))
const project = fileURLToPath(new URL('safari/Fluently/Fluently.xcodeproj', root))
let exists = false
try { await access(project); exists = true } catch {}
if (exists) {
  console.log(`Using existing Safari wrapper: ${project}`)
  console.log('Its resources reference extension/builds/safari; rebuilding the extension updates them.')
  process.exit(0)
}
const find = name => spawnSync('xcrun', ['--find', name], {encoding: 'utf8'}).status === 0
const tool = find('safari-web-extension-packager') ? 'safari-web-extension-packager' : 'safari-web-extension-converter'
const result = spawnSync('xcrun', [tool, fileURLToPath(new URL('builds/safari/', root)),
  '--project-location', destination, '--app-name', 'Fluently', '--bundle-identifier', 'now.fluently.safari',
  '--swift', '--macos-only', '--no-open', '--no-prompt'], {stdio: 'inherit'})
if (result.error) throw result.error
if (result.status !== 0) process.exit(result.status || 1)
// Keep the generated host app and embedded extension identifiers consistent and
// avoid inheriting the installed Xcode SDK's macOS version as a minimum OS.
const pbx = project + '/project.pbxproj'
const source = await readFile(pbx, 'utf8')
await writeFile(pbx, source
  .replace(/PRODUCT_BUNDLE_IDENTIFIER = now\.fluently\.Fluently;/g, 'PRODUCT_BUNDLE_IDENTIFIER = now.fluently.safari;')
  .replace(/MACOSX_DEPLOYMENT_TARGET = [0-9.]+;/g, 'MACOSX_DEPLOYMENT_TARGET = 14.0;'))
console.log(`Safari Xcode project generated under ${destination}`)

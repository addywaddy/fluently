import {test} from 'node:test'
import assert from 'node:assert/strict'
import {configuration, detect} from '../../extension/config.mjs'

const project = '0ffa2549-1dfd-4d5c-8e0a-52c2357f4de5'
test('configuration accepts HTTPS and loopback HTTP, never credentials or arbitrary service paths', () => {
  assert.equal(configuration('https://fluently.now', project).service, 'https://fluently.now')
  assert.equal(configuration('http://localhost:4000', project).service, 'http://localhost:4000')
  for (const service of ['http://example.com', 'javascript:alert(1)', 'https://user:pass@example.com', 'https://example.com/path', 'https://example.com/?token=x', 'https://example.com/#x', 'file:///tmp/service']) assert.equal(configuration(service, project), null)
  assert.equal(configuration('https://fluently.now', '../other-project'), null)
  assert.equal(configuration(undefined, project), null)
})

test('only supported bounded capture options are copied from a page', () => {
  const result = configuration('https://fluently.now', project, {screenshots:'false', captureText:'false', secret:'no', styleNonce:'x'.repeat(500)})
  assert.deepEqual(result.attributes, {captureText:'false', screenshots:'false', styleNonce:'x'.repeat(256)})
})

test('detection validates script URLs and project IDs and deduplicates installations', () => {
  const script = {src:'https://fluently.now/embed.js', dataset:{project, screenshots:'false'}}
  const root = {querySelectorAll: () => [script, script,
    {src:'https://fluently.now/other.js', dataset:{project}},
    {src:'https://fluently.now/embed.js', dataset:{project:'invalid'}},
    {src:'https://staging.example.com/embed-abc123.js', dataset:{project}}
  ]}
  const configs = detect(root)
  assert.equal(configs.length, 2)
  assert.equal(configs[0].attributes.screenshots, 'false')
  assert.equal(configs[1].service, 'https://staging.example.com')
})

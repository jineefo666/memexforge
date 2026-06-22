import { describe, expect, test } from 'bun:test'
import {
  parseWorkbenchAcceptanceArgs,
  runWorkbenchAcceptance,
} from './acceptance-app-workbench.js'

const passingSmokeResult = {
  bundleDir: '/bundle',
  ok: true,
  checks: [{ label: 'manifest.json', ok: true }],
}

describe('acceptance-app-workbench', () => {
  test('passes when bundle smoke, Web, and bridge checks pass', async () => {
    const fetchedUrls: string[] = []

    const result = await runWorkbenchAcceptance(
      {
        bundleDir: '/bundle',
        webUrl: 'http://127.0.0.1:58439/app',
        bridgeUrl: 'ws://127.0.0.1:58432',
      },
      {
        smokeBundle: async options => {
          expect(options.bundleDir).toBe('/bundle')
          return passingSmokeResult
        },
        fetchText: async url => {
          fetchedUrls.push(url)
          return { status: 200, text: 'ok' }
        },
        connectWebSocket: async url => {
          expect(url).toBe('ws://127.0.0.1:58432')
          return '{"type":"hello","protocolVersion":1}'
        },
      },
    )

    expect(result.ok).toBe(true)
    expect(result.checks).toContainEqual({
      label: 'bundle smoke',
      status: 'pass',
      detail: '1 checks',
    })
    expect(result.checks).toContainEqual({
      label: 'Web index',
      status: 'pass',
      detail: 'HTTP 200',
    })
    expect(result.checks).toContainEqual({
      label: 'app-bridge WebSocket hello',
      status: 'pass',
      detail: 'protocolVersion 1',
    })
    expect(fetchedUrls).toEqual([
      'http://127.0.0.1:58439/app/',
      'http://127.0.0.1:58439/app/flutter_bootstrap.js',
      'http://127.0.0.1:58432/',
    ])
  })

  test('fails when the bridge hello message is not protocol version 1', async () => {
    const result = await runWorkbenchAcceptance(
      {
        bundleDir: '/bundle',
        bridgeUrl: 'ws://127.0.0.1:58432',
      },
      {
        smokeBundle: async () => passingSmokeResult,
        fetchText: async () => ({ status: 200, text: 'OpenClaude app bridge' }),
        connectWebSocket: async () => '{"type":"hello","protocolVersion":99}',
      },
    )

    expect(result.ok).toBe(false)
    expect(result.checks).toContainEqual({
      label: 'app-bridge WebSocket hello',
      status: 'fail',
      detail: 'unexpected hello message',
    })
  })

  test('skips live checks when URLs are omitted', async () => {
    const result = await runWorkbenchAcceptance(
      { bundleDir: '/bundle' },
      {
        smokeBundle: async () => passingSmokeResult,
        fetchText: async () => {
          throw new Error('should not fetch')
        },
        connectWebSocket: async () => {
          throw new Error('should not connect')
        },
      },
    )

    expect(result.ok).toBe(true)
    expect(result.checks).toContainEqual({
      label: 'Web live check',
      status: 'skip',
      detail: 'pass --web-url to enable',
    })
    expect(result.checks).toContainEqual({
      label: 'app-bridge live check',
      status: 'skip',
      detail: 'pass --bridge-url to enable',
    })
  })

  test('parses CLI arguments', () => {
    expect(
      parseWorkbenchAcceptanceArgs([
        '--bundle-dir',
        'dist/openclaude-app',
        '--web-url',
        'http://127.0.0.1:58439',
        '--bridge-url',
        'ws://127.0.0.1:58432',
      ]),
    ).toEqual({
      bundleDir: 'dist/openclaude-app',
      webUrl: 'http://127.0.0.1:58439',
      bridgeUrl: 'ws://127.0.0.1:58432',
    })
  })
})

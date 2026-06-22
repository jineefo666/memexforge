import { chmod, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, test } from 'bun:test'
import { smokeAppBundle } from './smoke-app-bundle.js'

const tempDirs: string[] = []

afterEach(async () => {
  await Promise.all(tempDirs.map(dir => rm(dir, { recursive: true, force: true })))
  tempDirs.length = 0
})

async function createSmokeBundleFixture(): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), 'openclaude-smoke-'))
  tempDirs.push(root)

  await mkdir(join(root, 'bin'), { recursive: true })
  await mkdir(join(root, 'app-bridge'), { recursive: true })
  await mkdir(join(root, 'dist'), { recursive: true })
  await mkdir(join(root, 'runtime'), { recursive: true })
  await mkdir(join(root, 'flutter', 'web'), { recursive: true })
  await mkdir(join(root, 'flutter', 'macos', 'MemexForge.app'), {
    recursive: true,
  })
  await mkdir(
    join(root, 'flutter', 'macos', 'MemexForge.app', 'Contents', 'Resources', 'openclaude-app', 'bin'),
    { recursive: true },
  )
  await mkdir(
    join(root, 'flutter', 'macos', 'MemexForge.app', 'Contents', 'Resources', 'openclaude-app', 'runtime'),
    { recursive: true },
  )
  await mkdir(
    join(root, 'flutter', 'macos', 'MemexForge.app', 'Contents', 'Resources', 'openclaude-app', 'app-bridge'),
    { recursive: true },
  )

  await writeFile(join(root, 'bin', 'openclaude'), '#!/usr/bin/env node\n')
  await writeFile(join(root, 'bin', 'app-bridge'), '#!/usr/bin/env sh\n')
  await writeFile(join(root, 'runtime', 'bun'), '#!/usr/bin/env bun\n')
  await writeFile(join(root, 'app-bridge', 'app-bridge.mjs'), 'console.log("bridge")\n')
  await writeFile(
    join(root, 'flutter', 'macos', 'MemexForge.app', 'Contents', 'Resources', 'openclaude-app', 'bin', 'app-bridge'),
    '#!/usr/bin/env sh\n',
  )
  await writeFile(
    join(root, 'flutter', 'macos', 'MemexForge.app', 'Contents', 'Resources', 'openclaude-app', 'runtime', 'bun'),
    '#!/usr/bin/env bun\n',
  )
  await writeFile(
    join(root, 'flutter', 'macos', 'MemexForge.app', 'Contents', 'Resources', 'openclaude-app', 'app-bridge', 'app-bridge.mjs'),
    'console.log("bridge")\n',
  )
  await writeFile(join(root, 'dist', 'cli.mjs'), 'console.log("cli")\n')
  await writeFile(join(root, 'dist', 'sdk.mjs'), 'export {}\n')
  await writeFile(join(root, 'flutter', 'web', 'index.html'), '<html></html>')
  await writeFile(
    join(root, 'flutter', 'web', 'main.dart.js'),
    [
      'Setup assistant',
      'Copy report',
      'Start bridge',
      'workspace-memory',
      'Release smoke checklist',
      'Marketplace actions',
    ].join('\n'),
  )
  await writeFile(
    join(root, 'README.md'),
    [
      '# MemexForge App Bundle',
      'Setup assistant',
      'Setup checklist',
      'Diagnostics',
      'Copy report',
      'Start bridge',
      'Reconnect bridge',
      'Extensions Marketplace',
      'Marketplace actions',
      'Release smoke checklist',
    ].join('\n'),
  )
  await writeFile(
    join(root, 'manifest.json'),
    JSON.stringify(
      {
        name: 'openclaude-app',
        version: '0.19.0',
        createdAt: new Date().toISOString(),
        targets: ['web', 'macos'],
        paths: {
          cli: 'bin/openclaude',
          appBridge: 'bin/app-bridge',
          flutter: {
            web: 'flutter/web',
            macos: 'flutter/macos/MemexForge.app',
          },
        },
        requirements: {
          node: '>=22.0.0',
          bun: 'bundled for app-bridge',
        },
      },
      null,
      2,
    ),
  )

  await chmod(join(root, 'bin', 'openclaude'), 0o755)
  await chmod(join(root, 'bin', 'app-bridge'), 0o755)
  await chmod(join(root, 'runtime', 'bun'), 0o755)
  await chmod(
    join(root, 'flutter', 'macos', 'MemexForge.app', 'Contents', 'Resources', 'openclaude-app', 'bin', 'app-bridge'),
    0o755,
  )
  return root
}

describe('smoke-app-bundle', () => {
  test('passes a complete web and macOS bundle', async () => {
    const bundleDir = await createSmokeBundleFixture()

    const result = await smokeAppBundle({ bundleDir })

    expect(result.ok).toBe(true)
    expect(result.checks.every(check => check.ok)).toBe(true)
  })

  test('fails when the manifest is missing', async () => {
    const bundleDir = await createSmokeBundleFixture()
    await rm(join(bundleDir, 'manifest.json'))

    const result = await smokeAppBundle({ bundleDir })

    expect(result.ok).toBe(false)
    expect(result.checks).toContainEqual(
      expect.objectContaining({
        label: 'manifest.json',
        ok: false,
      }),
    )
  })
})

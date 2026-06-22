import { constants } from 'node:fs'
import { access, mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { afterEach, describe, expect, test } from 'bun:test'
import {
  createAppPackage,
  flutterBuildCommandForTarget,
  parsePackageAppArgs,
  planAppPackage,
} from './package-app.js'

const tempDirs: string[] = []

afterEach(async () => {
  await Promise.all(tempDirs.map(dir => rm(dir, { recursive: true, force: true })))
  tempDirs.length = 0
})

async function createFixtureRoot(): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), 'openclaude-package-app-'))
  tempDirs.push(root)
  await mkdir(join(root, 'bin'), { recursive: true })
  await mkdir(join(root, 'dist'), { recursive: true })
  await mkdir(join(root, 'app', 'flutter_openclaude', 'build', 'web'), {
    recursive: true,
  })
  await mkdir(
    join(
      root,
      'app',
      'flutter_openclaude',
      'build',
      'macos',
      'Build',
      'Products',
      'Release',
      'MemexForge.app',
      'Contents',
      'MacOS',
    ),
    { recursive: true },
  )
  await writeFile(
    join(root, 'package.json'),
    JSON.stringify({ name: '@gitlawb/openclaude', version: '0.19.0' }),
  )
  await writeFile(join(root, 'bin', 'openclaude'), '#!/usr/bin/env node\n')
  await writeFile(join(root, 'fake-bun'), '#!/usr/bin/env bun\n')
  await writeFile(join(root, 'dist', 'cli.mjs'), 'console.log("cli")\n')
  await writeFile(join(root, 'dist', 'sdk.mjs'), 'export {}\n')
  await writeFile(
    join(root, 'dist', 'app-bridge.mjs'),
    'console.log("bridge")\n',
  )
  await writeFile(
    join(root, 'app', 'flutter_openclaude', 'build', 'web', 'index.html'),
    '<html></html>',
  )
  await writeFile(
    join(
      root,
      'app',
      'flutter_openclaude',
      'build',
      'macos',
      'Build',
      'Products',
      'Release',
      'MemexForge.app',
      'Contents',
      'MacOS',
      'MemexForge',
    ),
    'mac app',
  )
  return root
}

describe('package-app', () => {
  test('macOS app entitlements allow launching the packaged app bridge', async () => {
    for (const entitlementFile of [
      'app/flutter_openclaude/macos/Runner/DebugProfile.entitlements',
      'app/flutter_openclaude/macos/Runner/Release.entitlements',
    ]) {
      const content = await readFile(resolve(entitlementFile), 'utf8')

      expect(content).not.toContain(
        '<key>com.apple.security.app-sandbox</key>',
      )
    }
  })

  test('parses package options with web and desktop targets', () => {
    expect(
      parsePackageAppArgs([
        '--target',
        'web',
        '--target',
        'macos',
        '--skip-build',
        '--out-dir',
        'dist/release',
      ]),
    ).toEqual({
      targets: ['web', 'macos'],
      skipBuild: true,
      outDir: 'dist/release',
    })
  })

  test('builds web packages without a service worker cache', () => {
    expect(flutterBuildCommandForTarget('web')).toEqual([
      'flutter',
      'build',
      'web',
      '--pwa-strategy',
      'none',
    ])
    expect(flutterBuildCommandForTarget('macos')).toEqual([
      'flutter',
      'build',
      'macos',
    ])
  })

  test('plans an app package with CLI, app bridge, and Flutter outputs', async () => {
    const root = await createFixtureRoot()
    const plan = await planAppPackage({
      rootDir: root,
      targets: ['web', 'macos'],
      skipBuild: true,
      outDir: join(root, 'release'),
      bunRuntimePath: join(root, 'fake-bun'),
    })

    expect(plan.manifest).toMatchObject({
      name: 'openclaude-app',
      version: '0.19.0',
      targets: ['web', 'macos'],
      paths: {
        flutter: {
          web: 'flutter/web',
          macos: 'flutter/macos/MemexForge.app',
        },
      },
      requirements: {
        node: '>=22.0.0',
        bun: 'bundled for app-bridge',
      },
    })
    expect(plan.assets.map(asset => asset.label)).toEqual([
      'cli bundle',
      'sdk bundle',
      'cli launcher',
      'bun runtime',
      'app bridge bundle',
      'flutter web',
      'flutter macos',
    ])
    expect(plan.assets.at(-1)?.destination).toEndWith(
      'flutter/macos/MemexForge.app',
    )
  })

  test('creates a runnable release directory with manifest and launchers', async () => {
    const root = await createFixtureRoot()
    const outDir = join(root, 'release')
    const plan = await planAppPackage({
      rootDir: root,
      targets: ['web'],
      skipBuild: true,
      outDir,
      bunRuntimePath: join(root, 'fake-bun'),
    })

    await createAppPackage(plan)

    const manifest = JSON.parse(
      await readFile(join(outDir, 'manifest.json'), 'utf8'),
    )
    expect(manifest.targets).toEqual(['web'])
    await expect(readFile(join(outDir, 'bin', 'openclaude'), 'utf8')).resolves.toContain(
      '#!/usr/bin/env node',
    )
    const appBridgeLauncher = await readFile(
      join(outDir, 'bin', 'app-bridge'),
      'utf8',
    )
    expect(appBridgeLauncher).toContain('../runtime/bun')
    expect(appBridgeLauncher).toContain('/opt/homebrew/bin')
    expect(appBridgeLauncher).toContain('/usr/local/bin')
    await expect(readFile(join(outDir, 'runtime', 'bun'), 'utf8')).resolves.toContain(
      '#!/usr/bin/env bun',
    )
    await expect(
      readFile(join(outDir, 'flutter', 'web', 'index.html'), 'utf8'),
    ).resolves.toContain('<html>')
    await expect(readFile(join(outDir, 'README.md'), 'utf8')).resolves.toContain(
      'MemexForge App Bundle',
    )
    await expect(readFile(join(outDir, 'README.md'), 'utf8')).resolves.toContain(
      'Skills and MCP inventory',
    )
    await expect(readFile(join(outDir, 'README.md'), 'utf8')).resolves.toContain(
      'Setup checklist',
    )
    await expect(readFile(join(outDir, 'README.md'), 'utf8')).resolves.toContain(
      'Diagnostics',
    )
    await expect(readFile(join(outDir, 'README.md'), 'utf8')).resolves.toContain(
      'Reconnect bridge',
    )
    await expect(readFile(join(outDir, 'README.md'), 'utf8')).resolves.toContain(
      'Start bridge',
    )
    await expect(readFile(join(outDir, 'README.md'), 'utf8')).resolves.toContain(
      'Desktop builds can launch',
    )
    await expect(readFile(join(outDir, 'README.md'), 'utf8')).resolves.toContain(
      'Web builds still use the manual bridge command',
    )
    await expect(readFile(join(outDir, 'README.md'), 'utf8')).resolves.toContain(
      'Extensions Marketplace',
    )
    await expect(readFile(join(outDir, 'README.md'), 'utf8')).resolves.toContain(
      'Setup assistant',
    )
    await expect(readFile(join(outDir, 'README.md'), 'utf8')).resolves.toContain(
      'Copy report',
    )
    await expect(readFile(join(outDir, 'README.md'), 'utf8')).resolves.toContain(
      'Release smoke checklist',
    )
    await expect(readFile(join(outDir, 'README.md'), 'utf8')).resolves.toContain(
      'smoke:app',
    )
    await expect(readFile(join(outDir, 'README.md'), 'utf8')).resolves.toContain(
      'acceptance:app',
    )
    await expect(readFile(join(outDir, 'README.md'), 'utf8')).resolves.toContain(
      'Marketplace actions',
    )
  })

  test('embeds the app bridge runtime in macOS app bundles', async () => {
    const root = await createFixtureRoot()
    const outDir = join(root, 'release')
    const plan = await planAppPackage({
      rootDir: root,
      targets: ['macos'],
      skipBuild: true,
      outDir,
      bunRuntimePath: join(root, 'fake-bun'),
    })

    await createAppPackage(plan)

    const resourceRoot = join(
      outDir,
      'flutter',
      'macos',
      'MemexForge.app',
      'Contents',
      'Resources',
      'openclaude-app',
    )
    await expect(
      readFile(join(resourceRoot, 'bin', 'app-bridge'), 'utf8'),
    ).resolves.toContain('../runtime/bun')
    await expect(
      readFile(join(resourceRoot, 'runtime', 'bun'), 'utf8'),
    ).resolves.toContain('#!/usr/bin/env bun')
    await expect(
      readFile(join(resourceRoot, 'app-bridge', 'app-bridge.mjs'), 'utf8'),
    ).resolves.toContain('bridge')
    await expect(
      access(join(resourceRoot, 'bin', 'app-bridge'), constants.X_OK),
    ).resolves.toBeNull()
  })
})

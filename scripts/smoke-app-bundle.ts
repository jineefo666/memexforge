import { constants } from 'node:fs'
import { access, readFile, stat } from 'node:fs/promises'
import { join, resolve } from 'node:path'

export type SmokeCheck = {
  label: string
  ok: boolean
  detail?: string
}

export type SmokeResult = {
  bundleDir: string
  ok: boolean
  checks: SmokeCheck[]
}

type AppBundleManifest = {
  name?: string
  targets?: string[]
  paths?: {
    cli?: string
    appBridge?: string
    flutter?: Record<string, string>
  }
}

const REQUIRED_README_SNIPPETS = [
  'MemexForge App Bundle',
  'Setup assistant',
  'Setup checklist',
  'Diagnostics',
  'Copy report',
  'Start bridge',
  'Reconnect bridge',
  'Extensions Marketplace',
  'Marketplace actions',
  'Release smoke checklist',
]

const REQUIRED_WEB_SNIPPETS = [
  'Setup assistant',
  'Copy report',
  'Start bridge',
  'workspace-memory',
]

export async function smokeAppBundle(options: {
  bundleDir?: string
} = {}): Promise<SmokeResult> {
  const bundleDir = resolve(options.bundleDir ?? 'dist/openclaude-app')
  const checks: SmokeCheck[] = []
  const manifest = await readManifest(bundleDir, checks)

  if (manifest) {
    pushCheck(checks, 'manifest name', manifest.name === 'openclaude-app')
    pushCheck(
      checks,
      'manifest targets',
      Array.isArray(manifest.targets) && manifest.targets.length > 0,
      manifest.targets?.join(', ') ?? 'missing',
    )
    pushCheck(
      checks,
      'manifest cli path',
      manifest.paths?.cli === 'bin/openclaude',
      manifest.paths?.cli ?? 'missing',
    )
    pushCheck(
      checks,
      'manifest app bridge path',
      manifest.paths?.appBridge === 'bin/app-bridge',
      manifest.paths?.appBridge ?? 'missing',
    )
  }

  for (const file of [
    'README.md',
    'bin/openclaude',
    'bin/app-bridge',
    'app-bridge/app-bridge.mjs',
    'dist/cli.mjs',
    'dist/sdk.mjs',
    'runtime/bun',
  ]) {
    checks.push(await checkPath(bundleDir, file))
  }

  for (const file of ['bin/openclaude', 'bin/app-bridge', 'runtime/bun']) {
    checks.push(await checkExecutable(bundleDir, file))
  }

  await checkFileSnippets(bundleDir, 'README.md', REQUIRED_README_SNIPPETS, checks)

  if (manifest?.targets?.includes('web')) {
    checks.push(await checkPath(bundleDir, 'flutter/web/index.html'))
    checks.push(await checkPath(bundleDir, 'flutter/web/main.dart.js'))
    await checkFileSnippets(
      bundleDir,
      'flutter/web/main.dart.js',
      REQUIRED_WEB_SNIPPETS,
      checks,
    )
  }

  if (manifest?.targets?.includes('macos')) {
    checks.push(
      await checkPath(bundleDir, 'flutter/macos/MemexForge.app'),
    )
    for (const file of [
      'flutter/macos/MemexForge.app/Contents/Resources/openclaude-app/bin/app-bridge',
      'flutter/macos/MemexForge.app/Contents/Resources/openclaude-app/runtime/bun',
      'flutter/macos/MemexForge.app/Contents/Resources/openclaude-app/app-bridge/app-bridge.mjs',
    ]) {
      checks.push(await checkPath(bundleDir, file))
    }
    checks.push(
      await checkExecutable(
        bundleDir,
        'flutter/macos/MemexForge.app/Contents/Resources/openclaude-app/bin/app-bridge',
      ),
    )
  }

  return {
    bundleDir,
    checks,
    ok: checks.every(check => check.ok),
  }
}

async function readManifest(
  bundleDir: string,
  checks: SmokeCheck[],
): Promise<AppBundleManifest | null> {
  try {
    const raw = await readFile(join(bundleDir, 'manifest.json'), 'utf8')
    checks.push({ label: 'manifest.json', ok: true })
    return JSON.parse(raw) as AppBundleManifest
  } catch (error) {
    checks.push({
      label: 'manifest.json',
      ok: false,
      detail: error instanceof Error ? error.message : String(error),
    })
    return null
  }
}

async function checkPath(bundleDir: string, relativePath: string): Promise<SmokeCheck> {
  try {
    await stat(join(bundleDir, relativePath))
    return { label: relativePath, ok: true }
  } catch (error) {
    return {
      label: relativePath,
      ok: false,
      detail: error instanceof Error ? error.message : String(error),
    }
  }
}

async function checkExecutable(
  bundleDir: string,
  relativePath: string,
): Promise<SmokeCheck> {
  if (process.platform === 'win32') {
    return { label: `${relativePath} executable`, ok: true, detail: 'skipped' }
  }
  try {
    await access(join(bundleDir, relativePath), constants.X_OK)
    return { label: `${relativePath} executable`, ok: true }
  } catch (error) {
    return {
      label: `${relativePath} executable`,
      ok: false,
      detail: error instanceof Error ? error.message : String(error),
    }
  }
}

async function checkFileSnippets(
  bundleDir: string,
  relativePath: string,
  snippets: readonly string[],
  checks: SmokeCheck[],
): Promise<void> {
  let content = ''
  try {
    content = await readFile(join(bundleDir, relativePath), 'utf8')
  } catch (error) {
    checks.push({
      label: `${relativePath} content`,
      ok: false,
      detail: error instanceof Error ? error.message : String(error),
    })
    return
  }

  for (const snippet of snippets) {
    pushCheck(
      checks,
      `${relativePath} contains "${snippet}"`,
      content.includes(snippet),
    )
  }
}

function pushCheck(
  checks: SmokeCheck[],
  label: string,
  ok: boolean,
  detail?: string,
): void {
  checks.push({ label, ok, ...(detail ? { detail } : {}) })
}

function printSmokeResult(result: SmokeResult): void {
  console.log(`MemexForge app bundle smoke: ${result.bundleDir}`)
  for (const check of result.checks) {
    const icon = check.ok ? 'PASS' : 'FAIL'
    const detail = check.detail ? ` (${check.detail})` : ''
    console.log(`${icon} ${check.label}${detail}`)
  }
}

if (import.meta.main) {
  const result = await smokeAppBundle({ bundleDir: process.argv[2] })
  printSmokeResult(result)
  if (!result.ok) process.exitCode = 1
}

import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import {
  chmod,
  cp,
  mkdir,
  readFile,
  rm,
  writeFile,
} from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { CLI_EXTERNALS } from './externals.js'
import { noTelemetryPlugin } from './no-telemetry-plugin'

export type AppPackageTarget = 'web' | 'macos' | 'windows' | 'linux'

export type PackageAppArgs = {
  targets: AppPackageTarget[]
  skipBuild: boolean
  outDir: string
  flutterDir?: string
}

export type PackageAsset = {
  label: string
  source: string
  destination: string
}

export type AppPackageManifest = {
  name: 'openclaude-app'
  version: string
  createdAt: string
  targets: AppPackageTarget[]
  paths: {
    cli: string
    appBridge: string
    flutter: Partial<Record<AppPackageTarget, string>>
  }
  requirements: {
    node: '>=22.0.0'
    bun: 'bundled for app-bridge'
  }
}

export type AppPackagePlan = {
  rootDir: string
  outDir: string
  flutterDir: string
  skipBuild: boolean
  appBridgeBundleSource: string
  targets: AppPackageTarget[]
  assets: PackageAsset[]
  manifest: AppPackageManifest
}

const VALID_TARGETS = new Set<AppPackageTarget>([
  'web',
  'macos',
  'windows',
  'linux',
])

async function main(): Promise<void> {
  const args = parsePackageAppArgs(process.argv.slice(2))
  if (process.argv.includes('--help') || process.argv.includes('-h')) {
    console.log(HELP.trimEnd())
    return
  }

  const plan = await planAppPackage({
    rootDir: process.cwd(),
    ...args,
  })
  await runBuildSteps(plan)
  await createAppPackage(plan)
  console.log(`MemexForge app bundle written to ${plan.outDir}`)
}

export function parsePackageAppArgs(argv: readonly string[]): PackageAppArgs {
  const targets: AppPackageTarget[] = []
  let skipBuild = false
  let outDir = 'dist/openclaude-app'
  let flutterDir: string | undefined

  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index]
    if (arg === '--skip-build') {
      skipBuild = true
      continue
    }
    if (arg === '--target') {
      const value = argv[++index]
      if (!isPackageTarget(value)) {
        throw new Error(`Invalid --target: ${value ?? ''}`)
      }
      targets.push(value)
      continue
    }
    if (arg === '--out-dir') {
      outDir = requireValue(argv, ++index, '--out-dir')
      continue
    }
    if (arg === '--flutter-dir') {
      flutterDir = requireValue(argv, ++index, '--flutter-dir')
      continue
    }
    if (arg === '--help' || arg === '-h') continue
    throw new Error(`Unknown package-app option: ${arg}`)
  }

  return {
    targets: targets.length > 0 ? uniqueTargets(targets) : defaultTargets(),
    skipBuild,
    outDir,
    ...(flutterDir ? { flutterDir } : {}),
  }
}

export async function planAppPackage(options: {
  rootDir: string
  targets?: readonly AppPackageTarget[]
  skipBuild?: boolean
  outDir?: string
  flutterDir?: string
  bunRuntimePath?: string
}): Promise<AppPackagePlan> {
  const rootDir = resolve(options.rootDir)
  const outDir = resolve(rootDir, options.outDir ?? 'dist/openclaude-app')
  const flutterDir = resolve(
    rootDir,
    options.flutterDir ?? 'app/flutter_openclaude',
  )
  const targets = uniqueTargets(
    options.targets && options.targets.length > 0
      ? [...options.targets]
      : defaultTargets(),
  )
  const pkg = JSON.parse(await readFile(join(rootDir, 'package.json'), 'utf8'))
  const appBridgeBundleSource = join(rootDir, 'dist', 'app-bridge.mjs')
  const flutterPaths = Object.fromEntries(
    targets.map(target => [target, packagedFlutterPath(target)]),
  ) as Partial<Record<AppPackageTarget, string>>
  const manifest: AppPackageManifest = {
    name: 'openclaude-app',
    version: String(pkg.version ?? '0.0.0'),
    createdAt: new Date().toISOString(),
    targets,
    paths: {
      cli: 'bin/openclaude',
      appBridge: 'bin/app-bridge',
      flutter: flutterPaths,
    },
    requirements: {
      node: '>=22.0.0',
      bun: 'bundled for app-bridge',
    },
  }

  return {
    rootDir,
    outDir,
    flutterDir,
    skipBuild: options.skipBuild ?? false,
    appBridgeBundleSource,
    targets,
    assets: [
      {
        label: 'cli bundle',
        source: join(rootDir, 'dist', 'cli.mjs'),
        destination: join(outDir, 'dist', 'cli.mjs'),
      },
      {
        label: 'sdk bundle',
        source: join(rootDir, 'dist', 'sdk.mjs'),
        destination: join(outDir, 'dist', 'sdk.mjs'),
      },
      {
        label: 'cli launcher',
        source: join(rootDir, 'bin', 'openclaude'),
        destination: join(outDir, 'bin', 'openclaude'),
      },
      {
        label: 'bun runtime',
        source: resolve(options.bunRuntimePath ?? process.execPath),
        destination: join(outDir, 'runtime', packagedBunRuntimeName()),
      },
      {
        label: 'app bridge bundle',
        source: appBridgeBundleSource,
        destination: join(outDir, 'app-bridge', 'app-bridge.mjs'),
      },
      ...targets.map(target => ({
        label: `flutter ${target}`,
        source: flutterBuildOutput(flutterDir, target),
        destination: join(outDir, packagedFlutterPath(target)),
      })),
    ],
    manifest,
  }
}

export async function runBuildSteps(plan: AppPackagePlan): Promise<void> {
  if (plan.skipBuild) return

  runCommand(['bun', 'run', 'build'], plan.rootDir)
  await buildAppBridgeBundle(plan.rootDir, plan.appBridgeBundleSource)
  for (const target of plan.targets) {
    runCommand(flutterBuildCommandForTarget(target), plan.flutterDir)
  }
}

export function flutterBuildCommandForTarget(
  target: AppPackageTarget,
): string[] {
  if (target === 'web') {
    return ['flutter', 'build', 'web', '--pwa-strategy', 'none']
  }
  return ['flutter', 'build', target]
}

export async function createAppPackage(plan: AppPackagePlan): Promise<void> {
  if (plan.outDir === plan.rootDir) {
    throw new Error('Refusing to package into the repository root.')
  }

  await rm(plan.outDir, { recursive: true, force: true })
  for (const asset of plan.assets) {
    await mkdir(dirname(asset.destination), { recursive: true })
    await cp(asset.source, asset.destination, { recursive: true })
  }

  await writeFile(
    join(plan.outDir, 'manifest.json'),
    JSON.stringify(plan.manifest, null, 2) + '\n',
    'utf8',
  )
  await writeFile(join(plan.outDir, 'README.md'), packageReadme(plan), 'utf8')
  await writeAppBridgeLaunchers(plan.outDir)
  await chmod(join(plan.outDir, 'bin', 'openclaude'), 0o755).catch(() => {})
  await chmod(
    join(plan.outDir, 'runtime', packagedBunRuntimeName()),
    0o755,
  ).catch(() => {})
  await embedMacosAppBridgeRuntime(plan)
}

async function buildAppBridgeBundle(
  rootDir: string,
  outfile: string,
): Promise<void> {
  await mkdir(dirname(outfile), { recursive: true })
  const result = await Bun.build({
    entrypoints: [join(rootDir, 'scripts', 'start-app-bridge.ts')],
    outdir: dirname(outfile),
    naming: 'app-bridge.mjs',
    target: 'bun',
    format: 'esm',
    splitting: false,
    sourcemap: 'external',
    external: CLI_EXTERNALS,
    define: appBridgeDefines(rootDir),
    plugins: [
      noTelemetryPlugin,
      appBridgeFeatureFlagPlugin,
      appBridgeMissingModuleStubPlugin,
    ],
  })
  if (!result.success) {
    throw new Error(
      `Failed to bundle app bridge:\n${result.logs.map(log => log.message).join('\n')}`,
    )
  }
}

function appBridgeDefines(rootDir: string): Record<string, string> {
  const pkg = JSON.parse(readFileSync(join(rootDir, 'package.json'), 'utf8'))
  const version = String(pkg.version ?? '0.0.0')
  return {
    'MACRO.VERSION': JSON.stringify('99.0.0'),
    'MACRO.DISPLAY_VERSION': JSON.stringify(version),
    'MACRO.BUILD_TIME': JSON.stringify(new Date().toISOString()),
    'MACRO.ISSUES_EXPLAINER': JSON.stringify(
      'report the issue at https://github.com/Gitlawb/openclaude/issues',
    ),
    'MACRO.FEEDBACK_CHANNEL': JSON.stringify(
      'https://github.com/Gitlawb/openclaude/issues',
    ),
    'MACRO.PACKAGE_URL': JSON.stringify('@gitlawb/openclaude'),
    'MACRO.NATIVE_PACKAGE_URL': 'undefined',
    'MACRO.VERSION_CHANGELOG': 'undefined',
  }
}

const featureCallRe = /\bfeature\(\s*['"](\w+)['"][,\s]*\)/gs
const featureImportRe =
  /import\s*\{[^}]*\bfeature\b[^}]*\}\s*from\s*['"]bun:bundle['"];?\s*\n?/g

const appBridgeFeatureFlagPlugin = {
  name: 'app-bridge-feature-flag-preprocess',
  setup(build: Bun.PluginBuilder) {
    build.onLoad({ filter: /\.[cm]?tsx?$/ }, args => {
      const normalizedPath = args.path.replace(/\\/g, '/')
      if (!normalizedPath.includes('/src/')) return null

      const raw = readFileSync(args.path, 'utf-8')
      if (!raw.includes('feature(')) return null

      const contents = raw
        .replace(featureImportRe, '')
        .replace(featureCallRe, 'false')
      if (contents === raw) return null

      return {
        contents,
        loader:
          args.path.endsWith('.tsx') || args.path.endsWith('.jsx')
            ? 'tsx'
            : 'ts',
      }
    })
  },
}

const appBridgeMissingModuleStubPlugin = {
  name: 'app-bridge-missing-module-stub',
  setup(build: Bun.PluginBuilder) {
    for (const mod of [
      '@anthropic-ai/mcpb',
      '@ant/claude-for-chrome-mcp',
      '@ant/computer-use-mcp',
      '@ant/computer-use-mcp/sentinelApps',
      '@ant/computer-use-mcp/types',
      '@ant/computer-use-swift',
      '@ant/computer-use-input',
      'audio-capture-napi',
      'audio-capture.node',
      'image-processor-napi',
      'modifiers-napi',
      'url-handler-napi',
      'color-diff-napi',
      'asciichart',
      'plist',
      'cacache',
      'fuse',
    ]) {
      build.onResolve({ filter: exactModuleFilter(mod) }, () => ({
        path: mod,
        namespace: 'app-bridge-stub',
      }))
    }

    build.onResolve({ filter: /\.(md|txt)$/ }, args => ({
      path: args.path,
      namespace: 'app-bridge-text-stub',
    }))
    build.onLoad(
      { filter: /.*/, namespace: 'app-bridge-text-stub' },
      () => ({
        contents: `export default '';`,
        loader: 'js',
      }),
    )
    build.onLoad({ filter: /.*/, namespace: 'app-bridge-stub' }, () => ({
      contents: `
const noop = () => null;
const handler = {
  get(_, prop) {
    if (prop === '__esModule') return true;
    if (prop === 'default') return new Proxy(noop, handler);
    if (prop === 'SandboxRuntimeConfigSchema') return { parse: () => ({}) };
    return noop;
  }
};
const stub = new Proxy(noop, handler);
export default stub;
export const __stub = true;
export const BROWSER_TOOLS = [];
export const ColorDiff = null;
export const ColorFile = null;
export const SandboxRuntimeConfigSchema = { parse: () => ({}) };
export const SandboxViolationStore = null;
export const SandboxManager = new Proxy({}, { get: () => noop });
export const createClaudeForChromeMcpServer = noop;
export const getMcpConfigForManifest = noop;
export const getSyntaxTheme = noop;
export const plot = noop;
`,
      loader: 'js',
    }))
  },
}

function exactModuleFilter(moduleName: string): RegExp {
  return new RegExp(`^${moduleName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`)
}

function runCommand(command: readonly string[], cwd: string): void {
  const result = spawnSync(command[0]!, command.slice(1), {
    cwd,
    stdio: 'inherit',
    env: process.env,
  })
  if (result.status !== 0) {
    throw new Error(`Command failed: ${command.join(' ')}`)
  }
}

async function writeAppBridgeLaunchers(outDir: string): Promise<void> {
  const binDir = join(outDir, 'bin')
  await mkdir(binDir, { recursive: true })
  const shPath = join(binDir, 'app-bridge')
  await writeFile(
    shPath,
    [
      '#!/usr/bin/env sh',
      'set -e',
      'DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)',
      'BUNDLED_BUN="$DIR/../runtime/bun"',
      'if [ -x "$BUNDLED_BUN" ]; then',
      '  exec "$BUNDLED_BUN" "$DIR/../app-bridge/app-bridge.mjs" "$@"',
      'fi',
      'if command -v bun >/dev/null 2>&1; then',
      '  exec bun "$DIR/../app-bridge/app-bridge.mjs" "$@"',
      'fi',
      'if command -v npx >/dev/null 2>&1; then',
      '  exec npx --yes bun@latest "$DIR/../app-bridge/app-bridge.mjs" "$@"',
      'fi',
      'echo "OpenClaude app bridge requires Bun. Install Bun or make npx available." >&2',
      'exit 127',
      '',
    ].join('\n'),
    'utf8',
  )
  await chmod(shPath, 0o755).catch(() => {})
  await writeFile(
    join(binDir, 'app-bridge.cmd'),
    [
      '@echo off',
      'set SCRIPT_DIR=%~dp0',
      'set BUNDLED_BUN=%SCRIPT_DIR%..\\runtime\\bun.exe',
      'if exist "%BUNDLED_BUN%" (',
      '  "%BUNDLED_BUN%" "%SCRIPT_DIR%..\\app-bridge\\app-bridge.mjs" %*',
      '  exit /b %ERRORLEVEL%',
      ')',
      'where bun >nul 2>nul',
      'if %ERRORLEVEL%==0 (',
      '  bun "%SCRIPT_DIR%..\\app-bridge\\app-bridge.mjs" %*',
      '  exit /b %ERRORLEVEL%',
      ')',
      'where npx >nul 2>nul',
      'if %ERRORLEVEL%==0 (',
      '  npx --yes bun@latest "%SCRIPT_DIR%..\\app-bridge\\app-bridge.mjs" %*',
      '  exit /b %ERRORLEVEL%',
      ')',
      'echo OpenClaude app bridge requires Bun. Install Bun or make npx available. 1>&2',
      'exit /b 127',
      '',
    ].join('\r\n'),
    'utf8',
  )
}

async function embedMacosAppBridgeRuntime(
  plan: AppPackagePlan,
): Promise<void> {
  if (!plan.targets.includes('macos')) return

  const resourceRoot = join(
    plan.outDir,
    packagedFlutterPath('macos'),
    'Contents',
    'Resources',
    'openclaude-app',
  )
  const bundledRuntime = packagedBunRuntimeName()
  const files = [
    ['bin', 'app-bridge'],
    ['bin', 'app-bridge.cmd'],
    ['runtime', bundledRuntime],
    ['app-bridge', 'app-bridge.mjs'],
  ]

  await rm(resourceRoot, { recursive: true, force: true })
  for (const parts of files) {
    const source = join(plan.outDir, ...parts)
    const destination = join(resourceRoot, ...parts)
    await mkdir(dirname(destination), { recursive: true })
    await cp(source, destination, { recursive: true })
  }
  await chmod(join(resourceRoot, 'bin', 'app-bridge'), 0o755).catch(() => {})
  await chmod(join(resourceRoot, 'runtime', bundledRuntime), 0o755).catch(
    () => {},
  )
}

function packagedFlutterPath(target: AppPackageTarget): string {
  if (target === 'macos') return 'flutter/macos/MemexForge.app'
  return `flutter/${target}`
}

function packagedBunRuntimeName(): string {
  return process.platform === 'win32' ? 'bun.exe' : 'bun'
}

function packageReadme(plan: AppPackagePlan): string {
  return [
    '# MemexForge App Bundle',
    '',
    `Version: ${plan.manifest.version}`,
    '',
    '## Overview',
    '',
    'MemexForge packages the OpenClaude CLI, SDK, app-bridge, and Flutter UI into one local application directory.',
    '',
    'The Flutter Web/Desktop UI provides chat sessions, streaming output, tool permission review, provider/model/API key settings, long-context retrieval, Diagnostics, Skills management, MCP server management, and an Extensions Marketplace. The UI talks to the local app-bridge over WebSocket, while the actual agent execution continues to use the existing OpenClaude SDK flow.',
    '',
    '## Highlights',
    '',
    '- Flutter Web and desktop UI in the same release directory.',
    '- Local app-bridge for SDK messages, permission requests, session control, Skills, MCP, and context retrieval.',
    '- Provider/model settings with model-bound Base URL defaults.',
    '- Setup assistant for first-run bridge and API key readiness.',
    '- Setup checklist and Diagnostics panel for bridge health, API key status, workspace scope, and event logs.',
    '- Copy report action for redacted Diagnostics troubleshooting.',
    '- Start bridge action for desktop builds that can launch the packaged `bin/app-bridge` process.',
    '- Reconnect bridge action for recovering from local WebSocket connection errors.',
    '- Skills and MCP inventory with enable/disable, CRUD, connection testing, and capability preview.',
    '- Extensions Marketplace for searchable local/curated Skills and MCP entries.',
    '- Marketplace actions for local skill import and MCP template creation.',
    '- Hybrid long-context retrieval for documents, memory, usage habits, transcript search, and graph facts.',
    '- Secret redaction for API keys, tokens, env values, and MCP headers in UI and bridge events.',
    '',
    '## Run',
    '',
    '- CLI: `bin/openclaude`',
    '- App bridge: `bin/app-bridge` (defaults to `ws://127.0.0.1:58432`)',
    '- Web UI: serve `flutter/web` with any static file server, then open the served local URL.',
    '- Desktop UI: open the app under `flutter/<target>` when a desktop target was packaged.',
    '- Desktop builds can launch the local bridge from Diagnostics with `Start bridge` when the packaged `bin/app-bridge` launcher is available.',
    '- Web builds still use the manual bridge command before opening the local URL.',
    '',
    'Example Web run:',
    '',
    '```bash',
    'bin/app-bridge',
    'python3 -m http.server 58435 --bind 127.0.0.1 --directory flutter/web',
    '```',
    '',
    'Then open `http://127.0.0.1:58435`.',
    '',
    'Use a custom bridge port when needed:',
    '',
    '```bash',
    'APP_BRIDGE_PORT=58438 bin/app-bridge',
    '```',
    '',
    '## Basic Workflow',
    '',
    '1. Start `bin/app-bridge`.',
    '2. Open the Web UI or desktop app.',
    '3. Open Diagnostics and review the Setup checklist.',
    '4. Use Start bridge in desktop builds, or start `bin/app-bridge` manually for Web builds.',
    '5. Use Reconnect bridge when the app bridge is disconnected or the port changes.',
    '6. Configure Provider, model, and API key in Settings.',
    '7. Use Chat for sessions, streaming output, tool cards, and permissions.',
    '8. Use Context for retrieval, memory, document structure, and evaluation.',
    '9. Use Extensions to manage Skills, MCP servers, and the Extensions Marketplace.',
    '',
    '## Release smoke checklist',
    '',
    'From the source checkout after packaging, run:',
    '',
    '```bash',
    'npx --yes bun@latest run smoke:app -- dist/openclaude-app',
    '```',
    '',
    'With the Web UI and app bridge running, run the live acceptance check:',
    '',
    '```bash',
    'npx --yes bun@latest run acceptance:app -- --bundle-dir dist/openclaude-app --web-url http://127.0.0.1:58439 --bridge-url ws://127.0.0.1:58432',
    '```',
    '',
    '1. Start the desktop app or serve the Web UI.',
    '2. Confirm the Setup assistant appears when bridge or API key setup is incomplete.',
    '3. Use Diagnostics to Start bridge or Reconnect bridge.',
    '4. Use Copy report if bridge/provider setup fails; the report is redacted.',
    '5. Configure Provider, model, and API key.',
    '6. Open Chat and send a short test prompt.',
    '7. Open Extensions Marketplace and verify Marketplace actions for local skills and MCP templates.',
    '8. Verify Context indexing, Memory, Evaluation, and tool permission flows with a user-owned API key.',
    '',
    '## Core Advantages',
    '',
    '- Zero-disruption integration: UI and interaction are handled in Flutter, while execution remains on OpenClaude SDK and existing flows.',
    '- Cross-platform delivery: one package can contain Web and desktop builds.',
    '- Productized extension management: Skills and MCP servers are visible, testable, and controllable from the UI.',
    '- Safer defaults: secrets are redacted from user-visible state and bridge errors.',
    '- Rollback-friendly architecture: context retrieval and runtime extensions remain configurable.',
    '',
    '## Requirements',
    '',
    '- Node.js >=22.0.0 for the CLI.',
    '- Bun for the local app bridge.',
    '',
    '## More Documentation',
    '',
    'See `docs/agent-workbench.md` in the source repository for the full GitHub documentation.',
    '',
  ].join('\n')
}

function flutterBuildOutput(
  flutterDir: string,
  target: AppPackageTarget,
): string {
  if (target === 'web') return join(flutterDir, 'build', 'web')
  if (target === 'macos') {
    return join(
      flutterDir,
      'build',
      'macos',
      'Build',
      'Products',
      'Release',
      'MemexForge.app',
    )
  }
  if (target === 'windows') {
    return join(flutterDir, 'build', 'windows', 'x64', 'runner', 'Release')
  }
  return join(flutterDir, 'build', 'linux', 'x64', 'release', 'bundle')
}

function defaultTargets(): AppPackageTarget[] {
  const desktop = currentDesktopTarget()
  return desktop ? ['web', desktop] : ['web']
}

function currentDesktopTarget(): AppPackageTarget | null {
  if (process.platform === 'darwin') return 'macos'
  if (process.platform === 'win32') return 'windows'
  if (process.platform === 'linux') return 'linux'
  return null
}

function uniqueTargets(targets: readonly AppPackageTarget[]): AppPackageTarget[] {
  return [...new Set(targets)]
}

function isPackageTarget(value: string | undefined): value is AppPackageTarget {
  return !!value && VALID_TARGETS.has(value as AppPackageTarget)
}

function requireValue(
  argv: readonly string[],
  index: number,
  option: string,
): string {
  const value = argv[index]
  if (!value) throw new Error(`Missing value for ${option}`)
  return value
}

const HELP = `Usage: bun run package:app [options]

Builds an OpenClaude app release directory containing the CLI, app bridge,
and Flutter web/desktop artifacts.

Options:
  --target <web|macos|windows|linux>  Build/package a target. Repeatable.
  --out-dir <path>                    Output directory. Default: dist/openclaude-app
  --flutter-dir <path>                Flutter project. Default: app/flutter_openclaude
  --skip-build                        Package existing build outputs only.
`

if (import.meta.main) {
  await main()
}

import { smokeAppBundle, type SmokeResult } from './smoke-app-bundle.js'

export type WorkbenchAcceptanceOptions = {
  bundleDir?: string
  webUrl?: string
  bridgeUrl?: string
}

export type WorkbenchAcceptanceCheck = {
  label: string
  status: 'pass' | 'fail' | 'skip'
  detail?: string
}

export type WorkbenchAcceptanceResult = {
  ok: boolean
  checks: WorkbenchAcceptanceCheck[]
}

type FetchTextResult = {
  status: number
  text: string
}

export type WorkbenchAcceptanceDependencies = {
  smokeBundle: (options: { bundleDir?: string }) => Promise<SmokeResult>
  fetchText: (url: string) => Promise<FetchTextResult>
  connectWebSocket: (url: string) => Promise<string>
}

const HELP = `Usage: bun run acceptance:app [options]

Runs Agent Workbench release acceptance checks against a packaged bundle and,
when URLs are provided, live Web/app-bridge endpoints.

Options:
  --bundle-dir <path>   Packaged app directory. Default: dist/openclaude-app
  --web-url <url>       Served Flutter Web URL, for example http://127.0.0.1:58439
  --bridge-url <url>    app-bridge WebSocket URL, for example ws://127.0.0.1:58432
`

export function parseWorkbenchAcceptanceArgs(
  argv: readonly string[],
): WorkbenchAcceptanceOptions {
  const options: WorkbenchAcceptanceOptions = {}

  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index]
    if (arg === '--bundle-dir') {
      options.bundleDir = requireValue(argv, ++index, '--bundle-dir')
      continue
    }
    if (arg === '--web-url') {
      options.webUrl = requireValue(argv, ++index, '--web-url')
      continue
    }
    if (arg === '--bridge-url') {
      options.bridgeUrl = requireValue(argv, ++index, '--bridge-url')
      continue
    }
    if (arg === '--help' || arg === '-h') continue
    throw new Error(`Unknown acceptance option: ${arg}`)
  }

  return options
}

export async function runWorkbenchAcceptance(
  options: WorkbenchAcceptanceOptions = {},
  deps: WorkbenchAcceptanceDependencies = defaultDependencies,
): Promise<WorkbenchAcceptanceResult> {
  const checks: WorkbenchAcceptanceCheck[] = []

  await checkBundleSmoke(options.bundleDir, deps, checks)
  if (options.webUrl) {
    await checkWeb(options.webUrl, deps, checks)
  } else {
    checks.push({
      label: 'Web live check',
      status: 'skip',
      detail: 'pass --web-url to enable',
    })
  }

  if (options.bridgeUrl) {
    await checkBridge(options.bridgeUrl, deps, checks)
  } else {
    checks.push({
      label: 'app-bridge live check',
      status: 'skip',
      detail: 'pass --bridge-url to enable',
    })
  }

  checks.push({
    label: 'Provider/API key chat',
    status: 'skip',
    detail: 'manual: configure a user-owned API key in the UI and send a prompt',
  })
  checks.push({
    label: 'Tool permission flow',
    status: 'skip',
    detail: 'manual: trigger a tool call and approve or reject it in the UI',
  })

  return {
    checks,
    ok: checks.every(check => check.status !== 'fail'),
  }
}

async function checkBundleSmoke(
  bundleDir: string | undefined,
  deps: WorkbenchAcceptanceDependencies,
  checks: WorkbenchAcceptanceCheck[],
): Promise<void> {
  try {
    const result = await deps.smokeBundle({ bundleDir })
    checks.push({
      label: 'bundle smoke',
      status: result.ok ? 'pass' : 'fail',
      detail: result.ok
        ? `${result.checks.length} checks`
        : `${result.checks.filter(check => !check.ok).length} failed`,
    })
  } catch (error) {
    checks.push({
      label: 'bundle smoke',
      status: 'fail',
      detail: errorMessage(error),
    })
  }
}

async function checkWeb(
  webUrl: string,
  deps: WorkbenchAcceptanceDependencies,
  checks: WorkbenchAcceptanceCheck[],
): Promise<void> {
  await checkHttpStatus(
    'Web index',
    joinUrl(webUrl, '/'),
    deps.fetchText,
    checks,
  )
  await checkHttpStatus(
    'Web bootstrap',
    joinUrl(webUrl, 'flutter_bootstrap.js'),
    deps.fetchText,
    checks,
  )
}

async function checkBridge(
  bridgeUrl: string,
  deps: WorkbenchAcceptanceDependencies,
  checks: WorkbenchAcceptanceCheck[],
): Promise<void> {
  await checkHttpStatus(
    'app-bridge HTTP health',
    bridgeHttpUrl(bridgeUrl),
    deps.fetchText,
    checks,
  )

  try {
    const raw = await deps.connectWebSocket(bridgeUrl)
    const hello = JSON.parse(raw) as { type?: string; protocolVersion?: number }
    const ok = hello.type === 'hello' && hello.protocolVersion === 1
    checks.push({
      label: 'app-bridge WebSocket hello',
      status: ok ? 'pass' : 'fail',
      detail: ok ? 'protocolVersion 1' : 'unexpected hello message',
    })
  } catch (error) {
    checks.push({
      label: 'app-bridge WebSocket hello',
      status: 'fail',
      detail: errorMessage(error),
    })
  }
}

async function checkHttpStatus(
  label: string,
  url: string,
  fetchText: WorkbenchAcceptanceDependencies['fetchText'],
  checks: WorkbenchAcceptanceCheck[],
): Promise<void> {
  try {
    const response = await fetchText(url)
    checks.push({
      label,
      status: response.status >= 200 && response.status < 300 ? 'pass' : 'fail',
      detail: `HTTP ${response.status}`,
    })
  } catch (error) {
    checks.push({
      label,
      status: 'fail',
      detail: errorMessage(error),
    })
  }
}

const defaultDependencies: WorkbenchAcceptanceDependencies = {
  smokeBundle: smokeAppBundle,
  async fetchText(url) {
    const response = await fetch(url)
    return {
      status: response.status,
      text: await response.text(),
    }
  },
  connectWebSocket: connectWebSocketHello,
}

async function connectWebSocketHello(url: string): Promise<string> {
  return await new Promise((resolve, reject) => {
    const socket = new WebSocket(url)
    const timer = setTimeout(() => {
      socket.close()
      reject(new Error('WebSocket hello timed out'))
    }, 3000)

    const cleanup = () => clearTimeout(timer)
    socket.addEventListener('message', event => {
      cleanup()
      socket.close()
      resolve(String(event.data))
    })
    socket.addEventListener('error', () => {
      cleanup()
      reject(new Error('WebSocket connection error'))
    })
  })
}

function joinUrl(baseUrl: string, path: string): string {
  const normalizedBase = baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`
  return new URL(path.replace(/^\//, ''), normalizedBase).toString()
}

function bridgeHttpUrl(bridgeUrl: string): string {
  const url = new URL(bridgeUrl)
  if (url.protocol === 'ws:') url.protocol = 'http:'
  if (url.protocol === 'wss:') url.protocol = 'https:'
  url.pathname = '/'
  url.search = ''
  url.hash = ''
  return url.toString()
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

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}

function printAcceptanceResult(result: WorkbenchAcceptanceResult): void {
  console.log('OpenClaude Agent Workbench acceptance')
  for (const check of result.checks) {
    const detail = check.detail ? ` (${check.detail})` : ''
    console.log(`${check.status.toUpperCase()} ${check.label}${detail}`)
  }
}

if (import.meta.main) {
  if (process.argv.includes('--help') || process.argv.includes('-h')) {
    console.log(HELP.trimEnd())
  } else {
    const result = await runWorkbenchAcceptance(
      parseWorkbenchAcceptanceArgs(process.argv.slice(2)),
    )
    printAcceptanceResult(result)
    if (!result.ok) process.exitCode = 1
  }
}

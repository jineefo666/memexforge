import { ensureAppBridgeMacroPolyfill } from '../src/appBridge/macroPolyfill.js'

const HELP = `Usage: bun run app-bridge

Starts the OpenClaude app bridge WebSocket server.

Environment:
  APP_BRIDGE_HOST  Bind host. Default: 127.0.0.1
  APP_BRIDGE_PORT  Bind port. Default: 58432
  OPENCLAUDE_AGENT_EVAL_TRACE      Set 1/true/on to record P12 trace JSONL.
  OPENCLAUDE_AGENT_EVAL_TRACE_DIR  Trace directory. Default: reports/agent-eval/traces

Options:
  --trace     Enable P12 app-bridge trace recording for this process.
  --no-trace  Disable P12 app-bridge trace recording for this process.
`

if (process.argv.includes('--help') || process.argv.includes('-h')) {
  console.log(HELP.trimEnd())
  process.exit(0)
}

await main()

async function main(): Promise<void> {
  ensureAppBridgeMacroPolyfill()
  const { enableConfigs } = await import('../src/utils/config.js')
  enableConfigs()
  const { startAppBridgeServer } = await import('../src/appBridge/server.js')
  const host = process.env.APP_BRIDGE_HOST || '127.0.0.1'
  const port = parsePort(process.env.APP_BRIDGE_PORT)
  const traceOverride = traceOverrideFromArgs(process.argv.slice(2))
  const server = startAppBridgeServer({
    host,
    port,
    ...(traceOverride === undefined
      ? {}
      : { agentEvalTrace: { enabled: traceOverride } }),
  })

  console.log(`OpenClaude app bridge listening on ${server.url}`)
  if (traceOverride === true || process.env.OPENCLAUDE_AGENT_EVAL_TRACE) {
    console.log(
      `Agent eval trace ${traceOverride === false ? 'disabled' : 'configured'}; output directory: ${
        process.env.OPENCLAUDE_AGENT_EVAL_TRACE_DIR ||
        'reports/agent-eval/traces'
      }`,
    )
  }

  for (const signal of ['SIGINT', 'SIGTERM'] as const) {
    process.on(signal, () => {
      server.stop()
      process.exit(0)
    })
  }
}

function traceOverrideFromArgs(argv: readonly string[]): boolean | undefined {
  if (argv.includes('--trace')) return true
  if (argv.includes('--no-trace')) return false
  return undefined
}

function parsePort(value: string | undefined): number {
  if (!value) return 58432
  const parsed = Number(value)
  if (!Number.isInteger(parsed) || parsed <= 0 || parsed > 65_535) {
    throw new Error(`Invalid APP_BRIDGE_PORT: ${value}`)
  }
  return parsed
}

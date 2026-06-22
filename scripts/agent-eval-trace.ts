import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import type { AgentEvalTraceRecord } from '../src/appBridge/agentEvalTrace.js'
import {
  scoreAgentEvalCases,
  writeAgentEvalReports,
  type AgentEvalCase,
  type AgentEvalReport,
} from './agent-eval.js'

export type AgentEvalTraceRunOptions = {
  tracePath: string
  outDir: string
}

export type AgentEvalTraceRunResult = {
  caseCount: number
  casesPath: string
  jsonPath: string
  markdownPath: string
  report: AgentEvalReport
}

const DEFAULT_TRACE_PATH = 'reports/agent-eval/traces/turns.jsonl'
const DEFAULT_OUT_DIR = 'reports/agent-eval/trace-runs/latest'

export function parseAgentEvalTraceArgs(
  argv: readonly string[],
): AgentEvalTraceRunOptions {
  const options: AgentEvalTraceRunOptions = {
    tracePath: DEFAULT_TRACE_PATH,
    outDir: DEFAULT_OUT_DIR,
  }

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === '--trace') {
      options.tracePath = requireValue(argv, ++index, '--trace')
      continue
    }
    if (arg === '--out') {
      options.outDir = requireValue(argv, ++index, '--out')
      continue
    }
    if (arg === '--help' || arg === '-h') continue
    throw new Error(`Unknown agent eval trace option: ${arg}`)
  }

  return options
}

export async function loadAgentEvalTraceRecords(
  tracePath: string,
): Promise<AgentEvalTraceRecord[]> {
  const content = await readFile(tracePath, 'utf8')
  const records: AgentEvalTraceRecord[] = []
  for (const [lineIndex, line] of content.split(/\r?\n/).entries()) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    try {
      records.push(JSON.parse(trimmed) as AgentEvalTraceRecord)
    } catch (error) {
      throw new Error(
        `Failed to parse agent eval trace JSONL at ${tracePath}:${lineIndex + 1}: ${errorMessage(error)}`,
      )
    }
  }
  return records
}

export function traceRecordsToEvalCases(
  records: readonly AgentEvalTraceRecord[],
): AgentEvalCase[] {
  return records.map(record => {
    const intent = inferIntent(record.prompt)
    const tools = unique(record.toolCalls.map(call => call.name))
    return {
      id: `trace-${safeId(record.requestId)}`,
      name: traceCaseName(record),
      category: 'trace',
      prompt: record.prompt,
      tags: [
        'real-trace',
        ...(record.model ? [`model:${record.model}`] : []),
        `cwd:${record.cwd}`,
      ],
      expected: {
        success: true,
        intent,
        tools,
        permissionDecisions: record.permissionDecisions,
        contextIds: record.retrievedContextIds,
      },
      observed: {
        success: record.success,
        intent,
        toolCalls: record.toolCalls,
        permissionDecisions: record.permissionDecisions,
        retrievedContextIds: record.retrievedContextIds,
        timings: record.timings,
        usage: record.usage,
        streaming: record.streaming,
      },
    }
  })
}

export async function writeTraceEvalRun(
  options: AgentEvalTraceRunOptions,
): Promise<AgentEvalTraceRunResult> {
  const records = await loadAgentEvalTraceRecords(options.tracePath)
  const cases = traceRecordsToEvalCases(records)
  const report = scoreAgentEvalCases(cases)
  await mkdir(options.outDir, { recursive: true })
  const casesPath = join(options.outDir, 'cases.jsonl')
  await writeFile(
    casesPath,
    `${cases.map(testCase => JSON.stringify(testCase)).join('\n')}\n`,
  )
  const paths = await writeAgentEvalReports(report, { outDir: options.outDir })
  return {
    caseCount: cases.length,
    casesPath,
    jsonPath: paths.jsonPath,
    markdownPath: paths.markdownPath,
    report,
  }
}

function inferIntent(prompt: string): string {
  const normalized = prompt.toLowerCase()
  if (
    /创建|新增|生成|写入|create|add|write/.test(normalized) &&
    /文件|file|\.txt|\.md|\.ts|\.dart|\.html/.test(normalized)
  ) {
    return 'create_file'
  }
  if (/当前目录|工作目录|cwd|current directory|project/.test(normalized)) {
    return 'inspect_project'
  }
  if (/继续|上一轮|之前|last turn|previous/.test(normalized)) {
    return 'continue_previous_task'
  }
  if (/权限|允许|批准|permission|approve|allow/.test(normalized)) {
    return 'permission_flow'
  }
  return 'general_request'
}

function traceCaseName(record: AgentEvalTraceRecord): string {
  const prompt = record.prompt.replace(/\s+/g, ' ').trim()
  return prompt.length > 48 ? `${prompt.slice(0, 45)}...` : prompt
}

function unique(values: readonly string[]): string[] {
  return [...new Set(values)]
}

function safeId(value: string): string {
  return value.replace(/[^A-Za-z0-9._-]+/g, '-')
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

function percent(value: number): string {
  return `${(value * 100).toFixed(1)}%`
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}

if (import.meta.main) {
  try {
    const result = await writeTraceEvalRun(
      parseAgentEvalTraceArgs(Bun.argv.slice(2)),
    )
    console.log(
      `OpenClaude Agent Trace Eval: ${percent(result.report.summary.overallScore)} overall`,
    )
    console.log(`Cases: ${result.caseCount}`)
    console.log(`Cases JSONL: ${result.casesPath}`)
    console.log(`JSON: ${result.jsonPath}`)
    console.log(`Markdown: ${result.markdownPath}`)
  } catch (error) {
    console.error(errorMessage(error))
    process.exit(1)
  }
}

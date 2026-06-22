import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

export type AgentEvalToolCall = {
  name: string
  status: 'success' | 'error'
  durationMs?: number
}

export type AgentEvalUsage = {
  inputTokens: number
  outputTokens: number
  cacheReadInputTokens?: number
  cacheCreationInputTokens?: number
  costUsd?: number
}

export type AgentEvalStreaming = {
  streamEvents: number
  textDeltas: number
  thinkingDeltas: number
}

export type AgentEvalExpected = {
  success: boolean
  intent: string
  tools?: readonly string[]
  permissionDecisions?: readonly string[]
  contextIds?: readonly string[]
}

export type AgentEvalObserved = {
  success: boolean
  intent: string
  toolCalls?: readonly AgentEvalToolCall[]
  permissionDecisions?: readonly string[]
  retrievedContextIds?: readonly string[]
  timings?: {
    firstTokenMs?: number
    totalMs?: number
  }
  usage?: AgentEvalUsage
  streaming?: AgentEvalStreaming
}

export type AgentEvalCase = {
  id: string
  name: string
  category: string
  prompt: string
  tags?: readonly string[]
  expected: AgentEvalExpected
  observed: AgentEvalObserved
}

export type AgentEvalCaseReport = {
  id: string
  name: string
  category: string
  status: 'pass' | 'fail'
  taskSuccess: boolean
  intentMatch: boolean
  toolAccuracy: number
  permissionMatch: boolean
  contextRecallAtK: number
  firstTokenMs: number
  totalMs: number
  inputTokens: number
  outputTokens: number
  streamEvents: number
  textDeltas: number
  thinkingDeltas: number
  costUsd: number
  toolFailureRate: number
}

export type AgentEvalSummary = {
  caseCount: number
  overallScore: number
  taskSuccessRate: number
  intentAccuracy: number
  toolAccuracy: number
  permissionAccuracy: number
  contextRecallAtK: number
  avgFirstTokenMs: number
  avgTotalMs: number
  totalInputTokens: number
  totalOutputTokens: number
  totalCacheReadInputTokens: number
  totalCacheCreationInputTokens: number
  totalStreamEvents: number
  totalTextDeltas: number
  totalThinkingDeltas: number
  textDeltaTurnRate: number
  totalCostUsd: number
  toolFailureRate: number
}

export type AgentEvalReport = {
  generatedAt: string
  summary: AgentEvalSummary
  cases: AgentEvalCaseReport[]
}

export type AgentEvalRunOptions = {
  casesPath: string
  outDir: string
}

const DEFAULT_CASES_PATH = 'eval/cases/p12-smoke.jsonl'
const DEFAULT_OUT_DIR = 'reports/agent-eval'

export function parseAgentEvalArgs(
  argv: readonly string[],
): AgentEvalRunOptions {
  const options: AgentEvalRunOptions = {
    casesPath: DEFAULT_CASES_PATH,
    outDir: DEFAULT_OUT_DIR,
  }

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === '--cases') {
      options.casesPath = requireValue(argv, ++index, '--cases')
      continue
    }
    if (arg === '--out') {
      options.outDir = requireValue(argv, ++index, '--out')
      continue
    }
    if (arg === '--help' || arg === '-h') continue
    throw new Error(`Unknown agent eval option: ${arg}`)
  }

  return options
}

export async function runAgentEval(
  options: AgentEvalRunOptions,
): Promise<AgentEvalReport> {
  const cases = await loadAgentEvalCases(options.casesPath)
  const report = scoreAgentEvalCases(cases)
  await writeAgentEvalReports(report, { outDir: options.outDir })
  return report
}

export async function loadAgentEvalCases(
  filePath: string,
): Promise<AgentEvalCase[]> {
  const content = await readFile(filePath, 'utf8')
  const cases: AgentEvalCase[] = []
  for (const [lineIndex, line] of content.split(/\r?\n/).entries()) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    try {
      cases.push(JSON.parse(trimmed) as AgentEvalCase)
    } catch (error) {
      throw new Error(
        `Failed to parse agent eval JSONL at ${filePath}:${lineIndex + 1}: ${errorMessage(error)}`,
      )
    }
  }
  return cases
}

export function scoreAgentEvalCases(
  cases: readonly AgentEvalCase[],
): AgentEvalReport {
  const caseReports = cases.map(scoreAgentEvalCase)
  const summary: AgentEvalSummary = {
    caseCount: caseReports.length,
    overallScore: weightedOverallScore(caseReports),
    taskSuccessRate: averageBooleans(
      caseReports.map(report => report.taskSuccess),
    ),
    intentAccuracy: averageBooleans(
      caseReports.map(report => report.intentMatch),
    ),
    toolAccuracy: average(caseReports.map(report => report.toolAccuracy)),
    permissionAccuracy: averageBooleans(
      caseReports.map(report => report.permissionMatch),
    ),
    contextRecallAtK: average(
      caseReports.map(report => report.contextRecallAtK),
    ),
    avgFirstTokenMs: average(caseReports.map(report => report.firstTokenMs)),
    avgTotalMs: average(caseReports.map(report => report.totalMs)),
    totalInputTokens: sum(caseReports.map(report => report.inputTokens)),
    totalOutputTokens: sum(caseReports.map(report => report.outputTokens)),
    totalCacheReadInputTokens: sum(
      cases.map(testCase => testCase.observed.usage?.cacheReadInputTokens ?? 0),
    ),
    totalCacheCreationInputTokens: sum(
      cases.map(
        testCase => testCase.observed.usage?.cacheCreationInputTokens ?? 0,
      ),
    ),
    totalStreamEvents: sum(caseReports.map(report => report.streamEvents)),
    totalTextDeltas: sum(caseReports.map(report => report.textDeltas)),
    totalThinkingDeltas: sum(caseReports.map(report => report.thinkingDeltas)),
    textDeltaTurnRate: averageBooleans(
      caseReports.map(report => report.textDeltas > 0),
    ),
    totalCostUsd: roundCurrency(sum(caseReports.map(report => report.costUsd))),
    toolFailureRate: weightedToolFailureRate(cases),
  }
  return {
    generatedAt: new Date().toISOString(),
    summary,
    cases: caseReports,
  }
}

function scoreAgentEvalCase(testCase: AgentEvalCase): AgentEvalCaseReport {
  const taskSuccess = testCase.observed.success === testCase.expected.success
  const intentMatch = testCase.observed.intent === testCase.expected.intent
  const toolAccuracy = expectedToolAccuracy(
    testCase.expected.tools ?? [],
    testCase.observed.toolCalls ?? [],
  )
  const permissionMatch = stringListEqual(
    testCase.expected.permissionDecisions ?? [],
    testCase.observed.permissionDecisions ?? [],
  )
  const contextRecallAtK = recall(
    testCase.expected.contextIds ?? [],
    testCase.observed.retrievedContextIds ?? [],
  )
  const firstTokenMs = testCase.observed.timings?.firstTokenMs ?? 0
  const totalMs = testCase.observed.timings?.totalMs ?? 0
  const inputTokens = testCase.observed.usage?.inputTokens ?? 0
  const outputTokens = testCase.observed.usage?.outputTokens ?? 0
  const streamEvents = testCase.observed.streaming?.streamEvents ?? 0
  const textDeltas = testCase.observed.streaming?.textDeltas ?? 0
  const thinkingDeltas = testCase.observed.streaming?.thinkingDeltas ?? 0
  const costUsd = testCase.observed.usage?.costUsd ?? 0
  const toolFailureRate = toolFailureRateForCalls(
    testCase.observed.toolCalls ?? [],
  )
  const status =
    taskSuccess &&
    intentMatch &&
    toolAccuracy === 1 &&
    permissionMatch &&
    contextRecallAtK === 1
      ? 'pass'
      : 'fail'

  return {
    id: testCase.id,
    name: testCase.name,
    category: testCase.category,
    status,
    taskSuccess,
    intentMatch,
    toolAccuracy,
    permissionMatch,
    contextRecallAtK,
    firstTokenMs,
    totalMs,
    inputTokens,
    outputTokens,
    streamEvents,
    textDeltas,
    thinkingDeltas,
    costUsd,
    toolFailureRate,
  }
}

export async function writeAgentEvalReports(
  report: AgentEvalReport,
  options: { outDir: string },
): Promise<{ jsonPath: string; markdownPath: string }> {
  await mkdir(options.outDir, { recursive: true })
  const jsonPath = join(options.outDir, 'latest.json')
  const markdownPath = join(options.outDir, 'latest.md')
  await writeFile(jsonPath, `${JSON.stringify(report, null, 2)}\n`)
  await writeFile(markdownPath, renderMarkdownReport(report))
  return { jsonPath, markdownPath }
}

function renderMarkdownReport(report: AgentEvalReport): string {
  const rows = [
    ['Overall score', percent(report.summary.overallScore)],
    ['Task success', percent(report.summary.taskSuccessRate)],
    ['Intent accuracy', percent(report.summary.intentAccuracy)],
    ['Tool accuracy', percent(report.summary.toolAccuracy)],
    ['Permission accuracy', percent(report.summary.permissionAccuracy)],
    ['Context recall@k', percent(report.summary.contextRecallAtK)],
    ['Avg first token', seconds(report.summary.avgFirstTokenMs)],
    ['Avg total latency', seconds(report.summary.avgTotalMs)],
    ['Input tokens', String(report.summary.totalInputTokens)],
    ['Output tokens', String(report.summary.totalOutputTokens)],
    ['Stream events', String(report.summary.totalStreamEvents)],
    ['Text deltas', String(report.summary.totalTextDeltas)],
    ['Thinking deltas', String(report.summary.totalThinkingDeltas)],
    ['Text delta turns', percent(report.summary.textDeltaTurnRate)],
    ['Tool failure rate', percent(report.summary.toolFailureRate)],
    ['Estimated cost', `$${report.summary.totalCostUsd.toFixed(4)}`],
  ]
  return [
    '# OpenClaude Agent Evaluation Report',
    '',
    `Generated: ${report.generatedAt}`,
    '',
    '| Metric | Value |',
    '| --- | ---: |',
    ...rows.map(([label, value]) => `| ${label} | ${value} |`),
    '',
    '## Cases',
    '',
    '| Case | Category | Status | Intent | Tools | Context | Text deltas | Total |',
    '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |',
    ...report.cases.map(
      testCase =>
        `| ${[
          escapeMarkdown(testCase.name),
          testCase.category,
          testCase.status,
          percent(testCase.intentMatch ? 1 : 0),
          percent(testCase.toolAccuracy),
          percent(testCase.contextRecallAtK),
          String(testCase.textDeltas),
          seconds(testCase.totalMs),
        ].join(' | ')} |`,
    ),
    '',
  ].join('\n')
}

function expectedToolAccuracy(
  expectedTools: readonly string[],
  observedToolCalls: readonly AgentEvalToolCall[],
): number {
  if (expectedTools.length === 0) return 1
  const observedNames = observedToolCalls.map(call => call.name)
  const correct = expectedTools.filter(toolName =>
    observedNames.includes(toolName),
  ).length
  return correct / expectedTools.length
}

function recall(
  expectedIds: readonly string[],
  observedIds: readonly string[],
): number {
  if (expectedIds.length === 0) return 1
  const observed = new Set(observedIds)
  return expectedIds.filter(id => observed.has(id)).length / expectedIds.length
}

function stringListEqual(
  left: readonly string[],
  right: readonly string[],
): boolean {
  return left.length === right.length && left.every((value, index) => value === right[index])
}

function weightedOverallScore(caseReports: readonly AgentEvalCaseReport[]): number {
  if (caseReports.length === 0) return 0
  return average(
    caseReports.map(
      report =>
        (Number(report.taskSuccess) * 0.4 +
          Number(report.intentMatch) * 0.2 +
          report.toolAccuracy * 0.15 +
          Number(report.permissionMatch) * 0.1 +
          report.contextRecallAtK * 0.15),
    ),
  )
}

function weightedToolFailureRate(cases: readonly AgentEvalCase[]): number {
  const calls = cases.flatMap(testCase => [...(testCase.observed.toolCalls ?? [])])
  return toolFailureRateForCalls(calls)
}

function toolFailureRateForCalls(calls: readonly AgentEvalToolCall[]): number {
  if (calls.length === 0) return 0
  return calls.filter(call => call.status === 'error').length / calls.length
}

function averageBooleans(values: readonly boolean[]): number {
  return average(values.map(value => Number(value)))
}

function average(values: readonly number[]): number {
  if (values.length === 0) return 0
  return sum(values) / values.length
}

function sum(values: readonly number[]): number {
  return values.reduce((total, value) => total + value, 0)
}

function roundCurrency(value: number): number {
  return Math.round(value * 1_000_000) / 1_000_000
}

function percent(value: number): string {
  return `${(value * 100).toFixed(1)}%`
}

function seconds(ms: number): string {
  return `${(ms / 1000).toFixed(2)}s`
}

function escapeMarkdown(value: string): string {
  return value.replaceAll('|', '\\|')
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

if (import.meta.main) {
  try {
    const options = parseAgentEvalArgs(Bun.argv.slice(2))
    const report = await runAgentEval(options)
    const paths = await writeAgentEvalReports(report, { outDir: options.outDir })
    console.log(`OpenClaude Agent Eval: ${percent(report.summary.overallScore)} overall`)
    console.log(`Cases: ${report.summary.caseCount}`)
    console.log(`JSON: ${paths.jsonPath}`)
    console.log(`Markdown: ${paths.markdownPath}`)
  } catch (error) {
    console.error(errorMessage(error))
    process.exit(1)
  }
}

import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, test } from 'bun:test'
import {
  loadAgentEvalCases,
  parseAgentEvalArgs,
  scoreAgentEvalCases,
  writeAgentEvalReports,
  type AgentEvalCase,
} from './agent-eval.js'

const tempDirs: string[] = []

afterEach(async () => {
  await Promise.all(
    tempDirs.map(dir => rm(dir, { recursive: true, force: true })),
  )
  tempDirs.length = 0
})

function fixtureCases(): AgentEvalCase[] {
  return [
    {
      id: 'case-pass',
      name: 'Create requested file',
      category: 'coding',
      prompt: 'Create test.txt in the active project.',
      expected: {
        success: true,
        intent: 'create_file',
        tools: ['Read', 'Write'],
        permissionDecisions: ['allow:Write'],
        contextIds: ['doc-active-project'],
      },
      observed: {
        success: true,
        intent: 'create_file',
        toolCalls: [
          { name: 'Read', status: 'success', durationMs: 400 },
          { name: 'Write', status: 'success', durationMs: 600 },
        ],
        permissionDecisions: ['allow:Write'],
        retrievedContextIds: ['doc-active-project'],
        timings: { firstTokenMs: 1000, totalMs: 4000 },
        usage: { inputTokens: 100, outputTokens: 50, costUsd: 0.0015 },
      },
    },
    {
      id: 'case-fail',
      name: 'Remember previous direction',
      category: 'memory',
      prompt: 'Continue with the direction from last turn.',
      expected: {
        success: true,
        intent: 'continue_previous_task',
        tools: ['Bash', 'Write'],
        permissionDecisions: ['allow:Bash'],
        contextIds: ['memory-russia-blocks'],
      },
      observed: {
        success: false,
        intent: 'ask_clarifying_question',
        toolCalls: [
          { name: 'Bash', status: 'success', durationMs: 1200 },
          { name: 'Glob', status: 'error', durationMs: 800 },
        ],
        permissionDecisions: ['deny:Bash'],
        retrievedContextIds: [],
        timings: { firstTokenMs: 2000, totalMs: 6000 },
        usage: { inputTokens: 200, outputTokens: 25, costUsd: 0.0025 },
      },
    },
  ]
}

describe('agent-eval', () => {
  test('scores success recognition speed token and tool metrics', () => {
    const report = scoreAgentEvalCases(fixtureCases())

    expect(report.summary.caseCount).toBe(2)
    expect(report.summary.taskSuccessRate).toBe(0.5)
    expect(report.summary.intentAccuracy).toBe(0.5)
    expect(report.summary.toolAccuracy).toBe(0.75)
    expect(report.summary.permissionAccuracy).toBe(0.5)
    expect(report.summary.contextRecallAtK).toBe(0.5)
    expect(report.summary.avgFirstTokenMs).toBe(1500)
    expect(report.summary.avgTotalMs).toBe(5000)
    expect(report.summary.totalInputTokens).toBe(300)
    expect(report.summary.totalOutputTokens).toBe(75)
    expect(report.summary.totalCostUsd).toBe(0.004)
    expect(report.summary.toolFailureRate).toBe(0.25)
    expect(report.cases.map(testCase => testCase.status)).toEqual([
      'pass',
      'fail',
    ])
  })

  test('loads JSONL cases and writes JSON plus Markdown reports', async () => {
    const root = await mkdtemp(join(tmpdir(), 'openclaude-agent-eval-'))
    tempDirs.push(root)
    const casesPath = join(root, 'cases.jsonl')
    const outDir = join(root, 'reports')
    await mkdir(outDir, { recursive: true })
    await writeFile(
      casesPath,
      [
        '# OpenClaude P12 smoke cases',
        ...fixtureCases().map(testCase => JSON.stringify(testCase)),
        '',
      ].join('\n'),
    )

    const cases = await loadAgentEvalCases(casesPath)
    const report = scoreAgentEvalCases(cases)
    const paths = await writeAgentEvalReports(report, { outDir })

    const json = await readFile(paths.jsonPath, 'utf8')
    const markdown = await readFile(paths.markdownPath, 'utf8')

    expect(cases).toHaveLength(2)
    expect(json).toContain('"taskSuccessRate": 0.5')
    expect(markdown).toContain('# OpenClaude Agent Evaluation Report')
    expect(markdown).toContain('| Task success | 50.0% |')
    expect(markdown).toContain('| Avg total latency | 5.00s |')
  })

  test('parses CLI arguments', () => {
    expect(
      parseAgentEvalArgs([
        '--cases',
        'eval/cases/p12-smoke.jsonl',
        '--out',
        'reports/agent-eval',
      ]),
    ).toEqual({
      casesPath: 'eval/cases/p12-smoke.jsonl',
      outDir: 'reports/agent-eval',
    })
  })
})

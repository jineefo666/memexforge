import { afterEach, describe, expect, test } from 'bun:test'
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  loadAgentEvalTraceRecords,
  parseAgentEvalTraceArgs,
  traceRecordsToEvalCases,
  writeTraceEvalRun,
} from './agent-eval-trace.js'

const tempDirs: string[] = []

afterEach(async () => {
  await Promise.all(
    tempDirs.map(dir => rm(dir, { recursive: true, force: true })),
  )
  tempDirs.length = 0
})

describe('agent-eval-trace', () => {
  test('converts app bridge trace records into P12 cases', async () => {
    const root = await mkdtemp(join(tmpdir(), 'openclaude-trace-cases-'))
    tempDirs.push(root)
    const tracePath = join(root, 'turns.jsonl')
    await writeFile(
      tracePath,
      [
        JSON.stringify({
          requestId: 'turn-1',
          sessionId: 'session-1',
          cwd: '/tmp/project',
          prompt: '创建一个 test.txt 文件',
          model: 'deepseek-v4-pro',
          success: true,
          retrievedContextIds: ['project:/tmp/project'],
          toolCalls: [{ name: 'Bash', status: 'success', durationMs: 700 }],
          permissionDecisions: ['allow:Bash'],
          timings: { firstTokenMs: 900, totalMs: 4300 },
          streaming: {
            streamEvents: 8,
            textDeltas: 5,
            thinkingDeltas: 3,
          },
          usage: {
            inputTokens: 1800,
            outputTokens: 220,
            cacheReadInputTokens: 80,
            cacheCreationInputTokens: 0,
            costUsd: 0.0022,
          },
          startedAt: '2026-06-22T00:00:00.000Z',
          completedAt: '2026-06-22T00:00:04.300Z',
        }),
        '',
      ].join('\n'),
    )

    const records = await loadAgentEvalTraceRecords(tracePath)
    const cases = traceRecordsToEvalCases(records)

    expect(cases).toHaveLength(1)
    expect(cases[0]).toMatchObject({
      id: 'trace-turn-1',
      category: 'trace',
      prompt: '创建一个 test.txt 文件',
      expected: {
        success: true,
        intent: 'create_file',
        tools: ['Bash'],
        permissionDecisions: ['allow:Bash'],
        contextIds: ['project:/tmp/project'],
      },
      observed: {
        success: true,
        intent: 'create_file',
        retrievedContextIds: ['project:/tmp/project'],
      },
    })
    expect(cases[0]?.observed.usage?.inputTokens).toBe(1800)
    expect(cases[0]?.observed.streaming?.textDeltas).toBe(5)
  })

  test('writes generated cases plus JSON and Markdown reports', async () => {
    const root = await mkdtemp(join(tmpdir(), 'openclaude-trace-run-'))
    tempDirs.push(root)
    const tracePath = join(root, 'turns.jsonl')
    const outDir = join(root, 'reports')
    await writeFile(
      tracePath,
      `${JSON.stringify({
        requestId: 'turn-2',
        cwd: '/tmp/project',
        prompt: '当前目录是什么',
        success: false,
        retrievedContextIds: [],
        toolCalls: [{ name: 'Bash', status: 'error' }],
        permissionDecisions: ['deny:Bash'],
        timings: { firstTokenMs: 1500, totalMs: 8000 },
        streaming: { streamEvents: 3, textDeltas: 0, thinkingDeltas: 3 },
        usage: { inputTokens: 900, outputTokens: 120, costUsd: 0.001 },
      })}\n`,
    )

    const result = await writeTraceEvalRun({ tracePath, outDir })

    expect(result.caseCount).toBe(1)
    expect(result.report.summary.taskSuccessRate).toBe(0)
    expect(await readFile(result.casesPath, 'utf8')).toContain('"trace-turn-2"')
    expect(await readFile(result.markdownPath, 'utf8')).toContain(
      '| Tool failure rate | 100.0% |',
    )
    expect(await readFile(result.markdownPath, 'utf8')).toContain(
      '| Text deltas | 0 |',
    )
  })

  test('parses CLI arguments and defaults', () => {
    expect(parseAgentEvalTraceArgs([])).toEqual({
      tracePath: 'reports/agent-eval/traces/turns.jsonl',
      outDir: 'reports/agent-eval/trace-runs/latest',
    })
    expect(
      parseAgentEvalTraceArgs([
        '--trace',
        'tmp/turns.jsonl',
        '--out',
        'tmp/report',
      ]),
    ).toEqual({
      tracePath: 'tmp/turns.jsonl',
      outDir: 'tmp/report',
    })
  })
})

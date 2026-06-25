import { readdirSync, statSync } from 'node:fs'
import path from 'node:path'

const ignoredDirectories = new Set([
  '.dart_tool',
  '.git',
  '.next',
  'coverage',
  'dist',
  'node_modules',
  'reports',
])

const ignoredRelativeDirectories = new Set(['app/flutter_openclaude/build'])

const testFilePattern =
  /(?:\.test|\.spec|_test_|_spec_)\.(?:cjs|cts|js|jsx|mjs|mts|ts|tsx)$/

function hasExplicitTestFilter(args: string[]): boolean {
  return args.some(arg => !arg.startsWith('-'))
}

function normalizeTestPath(filePath: string): string {
  if (path.isAbsolute(filePath) || filePath.startsWith('.')) {
    return filePath
  }

  return `./${filePath}`
}

function shouldSkipDirectory(root: string, directoryPath: string): boolean {
  const relativePath = path.relative(root, directoryPath)
  if (ignoredRelativeDirectories.has(relativePath)) {
    return true
  }

  return ignoredDirectories.has(path.basename(directoryPath))
}

function collectTestFiles(root: string, current = root): string[] {
  const entries = readdirSync(current, { withFileTypes: true })
  const files: string[] = []

  for (const entry of entries) {
    if (entry.isDirectory()) {
      const directoryPath = path.join(current, entry.name)
      if (shouldSkipDirectory(root, directoryPath)) continue
      files.push(...collectTestFiles(root, directoryPath))
      continue
    }

    if (!entry.isFile()) continue

    const absolutePath = path.join(current, entry.name)
    if (!testFilePattern.test(absolutePath)) continue

    // Avoid broken symlink-like entries or transient files that disappear while
    // a developer tool is rewriting the tree.
    try {
      statSync(absolutePath)
    } catch {
      continue
    }

    files.push(normalizeTestPath(path.relative(root, absolutePath)))
  }

  return files
}

const args = process.argv.slice(2)
const discoveredTestFiles = collectTestFiles(process.cwd()).sort()
const commandArgs = hasExplicitTestFilter(args)
  ? args.map(arg => (arg.startsWith('-') ? arg : normalizeTestPath(arg)))
  : [...args, ...discoveredTestFiles]

if (discoveredTestFiles.length === 0 && !hasExplicitTestFilter(args)) {
  console.error('No Bun test files found.')
  process.exit(1)
}

const result = Bun.spawnSync({
  cmd: [process.execPath, 'test', ...commandArgs],
  stdin: 'inherit',
  stdout: 'inherit',
  stderr: 'inherit',
})

process.exit(result.exitCode ?? 1)

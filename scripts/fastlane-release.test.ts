import { readFile } from 'node:fs/promises'
import { describe, expect, test } from 'bun:test'

describe('Fastlane macOS release configuration', () => {
  test('defines a reproducible macOS release lane', async () => {
    const fastfile = await readFile('fastlane/Fastfile', 'utf8')

    expect(fastfile).toContain('platform :mac')
    expect(fastfile).toContain('lane :release')
    expect(fastfile).toContain('MACOS_CODESIGN_IDENTITY')
    expect(fastfile).toContain('MACOS_NOTARY_KEYCHAIN_PROFILE')
    expect(fastfile).toContain('notarytool submit')
    expect(fastfile).toContain('stapler staple')
    expect(fastfile).toContain('spctl -a -vv -t install')
    expect(fastfile).toContain('hdiutil create')
    expect(fastfile).toContain('scripts/package-app.ts')
  })

  test('pins Fastlane and exposes the release command', async () => {
    await expect(readFile('Gemfile', 'utf8')).resolves.toContain(
      'gem "fastlane"',
    )

    const packageJson = JSON.parse(await readFile('package.json', 'utf8')) as {
      scripts?: Record<string, string>
    }
    expect(packageJson.scripts?.['release:macos']).toBe('fastlane mac release')
  })

  test('documents the signing and notarization environment variables', async () => {
    const docs = await readFile('docs/agent-workbench.md', 'utf8')

    expect(docs).toContain('release:macos')
    expect(docs).toContain('MACOS_CODESIGN_IDENTITY')
    expect(docs).toContain('MACOS_NOTARY_KEYCHAIN_PROFILE')
    expect(docs).toContain('dist/release/MemexForge-mac.dmg')
  })
})

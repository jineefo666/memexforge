import { mkdir } from 'node:fs/promises'
import { join } from 'node:path'
import sharp from 'sharp'

const rootDir = process.cwd()
const flutterDir = join(rootDir, 'app', 'flutter_openclaude')
const macIconDir = join(
  flutterDir,
  'macos',
  'Runner',
  'Assets.xcassets',
  'AppIcon.appiconset',
)
const webIconDir = join(flutterDir, 'web', 'icons')

async function main(): Promise<void> {
  await mkdir(macIconDir, { recursive: true })
  await mkdir(webIconDir, { recursive: true })

  await Promise.all([
    ...[16, 32, 64, 128, 256, 512, 1024].map((size) =>
      writeIcon(join(macIconDir, `app_icon_${size}.png`), size),
    ),
    writeIcon(join(flutterDir, 'web', 'favicon.png'), 32),
    writeIcon(join(webIconDir, 'Icon-192.png'), 192),
    writeIcon(join(webIconDir, 'Icon-512.png'), 512),
    writeIcon(join(webIconDir, 'Icon-maskable-192.png'), 192, {
      maskable: true,
    }),
    writeIcon(join(webIconDir, 'Icon-maskable-512.png'), 512, {
      maskable: true,
    }),
  ])

  console.log('Generated OpenClaude app icons.')
}

async function writeIcon(
  outputPath: string,
  size: number,
  options: { maskable?: boolean } = {},
): Promise<void> {
  await sharp(Buffer.from(appIconSvg(options)))
    .resize(size, size, { fit: 'contain' })
    .png()
    .toFile(outputPath)
}

function appIconSvg(options: { maskable?: boolean }): string {
  const maskable = options.maskable === true
  const outerRadius = maskable ? 0 : 220
  const frameInset = maskable ? 96 : 64
  const frameRadius = maskable ? 190 : 216

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="128" y1="64" x2="880" y2="940" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#25365F"/>
      <stop offset="0.56" stop-color="#151B2C"/>
      <stop offset="1" stop-color="#0E332E"/>
    </linearGradient>
    <linearGradient id="panel" x1="214" y1="214" x2="810" y2="764" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#E9EEF7"/>
    </linearGradient>
    <filter id="shadow" x="120" y="150" width="784" height="720" filterUnits="userSpaceOnUse">
      <feDropShadow dx="0" dy="34" stdDeviation="38" flood-color="#050812" flood-opacity="0.35"/>
    </filter>
  </defs>
  <rect width="1024" height="1024" rx="${outerRadius}" fill="transparent"/>
  <rect x="${frameInset}" y="${frameInset}" width="${1024 - frameInset * 2}" height="${1024 - frameInset * 2}" rx="${frameRadius}" fill="url(#bg)"/>
  <path d="M200 704C302 612 386 584 512 606C660 632 738 560 824 434V780C824 812 798 838 766 838H258C226 838 200 812 200 780V704Z" fill="#36D399" opacity="0.12"/>
  <g filter="url(#shadow)">
    <rect x="220" y="230" width="584" height="526" rx="88" fill="url(#panel)"/>
  </g>
  <path d="M342 474L442 386C454 376 472 385 472 401V449H612C627 449 640 462 640 477C640 492 627 505 612 505H472V553C472 569 454 578 442 568L342 480C340 478 340 476 342 474Z" fill="#4B5F9E"/>
  <rect x="650" y="451" width="96" height="56" rx="28" fill="#13B8A6"/>
  <rect x="318" y="600" width="188" height="34" rx="17" fill="#293554" opacity="0.92"/>
  <rect x="532" y="600" width="78" height="34" rx="17" fill="#F59E0B"/>
  <path d="M704 322C704 376 660 420 606 420C576 420 549 407 531 386L474 414" fill="none" stroke="#13B8A6" stroke-width="34" stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="704" cy="322" r="54" fill="#F7FAFC"/>
  <circle cx="704" cy="322" r="24" fill="#13B8A6"/>
  <circle cx="474" cy="414" r="26" fill="#F59E0B"/>
  <circle cx="606" cy="420" r="24" fill="#4B5F9E"/>
</svg>`
}

void main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

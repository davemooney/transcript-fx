import * as React from 'react'
import { CORRECTION_EFFECTS, type EffectKey } from './effects'
import seedSession from '../fixtures/seed-session.json'

interface Token {
  id: string
  text: string
  state: 'interim' | 'final'
  confidence?: number
  redacted?: boolean
}

const EFFECT_META: { key: EffectKey; label: string; blurb: string }[] = [
  { key: 'settle', label: 'Settle', blurb: 'Quiet crossfade — the calm, get-out-of-the-way default.' },
  { key: 'scramble', label: 'Scramble', blurb: 'Characters roll through glyphs then resolve. Familiar, satisfying.' },
  { key: 'blur', label: 'Blur-morph', blurb: 'Focus-pull: the old word blurs out, the corrected one snaps in.' },
  { key: 'swipe', label: 'Redaction swipe', blurb: 'A block sweeps over the swap, masking it — your offrecørd signature.' },
  { key: 'diff', label: 'Diff-morph ⭐', blurb: 'Only the letters that changed animate — "to → two" just morphs the inserted "w". The smart look.' },
  { key: 'ink', label: 'Ink-settle ⭐', blurb: 'Confidence becomes type weight: interim is light/hairline, finalising "gains ink". Very native/Apple.' },
]

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms))

type Step =
  | { op: 'add'; id: string; text: string; conf?: number; gap?: number }
  | { op: 'fix'; id: string; text: string; gap?: number }
  | { op: 'redact'; id: string; gap?: number }
  | { op: 'finalize'; gap?: number }

// The visual lab replays the SHARED reference fixture (../fixtures/seed-session.json,
// SPEC §5) — the exact same recorded session the transcript-fx parity test and
// the SwiftUI demo replay. One source of truth → this React lab and the Swift build
// are provably the *same interaction, two runtimes*. Map the runtime-agnostic source
// events (append/revise/redact/finalize) onto this lab's step shape.
type SeedEvent =
  | { op: 'append'; id: string; text: string; confidence?: number; gap?: number }
  | { op: 'revise'; id: string; text: string; gap?: number }
  | { op: 'redact'; id: string; gap?: number }
  | { op: 'finalize'; gap?: number }

const SCRIPT: Step[] = (seedSession.events as SeedEvent[]).map((e): Step => {
  switch (e.op) {
    case 'append':
      return { op: 'add', id: e.id, text: e.text, conf: e.confidence, gap: e.gap }
    case 'revise':
      return { op: 'fix', id: e.id, text: e.text, gap: e.gap }
    case 'redact':
      return { op: 'redact', id: e.id, gap: e.gap }
    case 'finalize':
      return { op: 'finalize', gap: e.gap }
  }
})

function TokenView({ token, effect }: { token: Token; effect: EffectKey }) {
  // Brief highlight the moment a word is corrected — makes every correction
  // legible across all effects (and confirms none are missed).
  const prevText = React.useRef(token.text)
  const [flash, setFlash] = React.useState(false)
  React.useEffect(() => {
    if (prevText.current !== token.text && !token.redacted) {
      prevText.current = token.text
      setFlash(true)
      const t = setTimeout(() => setFlash(false), 1100)
      return () => clearTimeout(t)
    }
    prevText.current = token.text
  }, [token.text, token.redacted])

  if (token.redacted) {
    return (
      <span className="tok final">
        <span className="fx-redact" aria-label="redacted">
          ████
        </span>
      </span>
    )
  }
  const Fx = CORRECTION_EFFECTS[effect]
  const low = token.confidence != null && token.confidence < 0.6
  const ink = effect === 'ink' ? ' ink' : ''
  return (
    <span className={`tok ${token.state}${low ? ' lowconf' : ''}${ink}${flash ? ' corrected' : ''}`}>
      <Fx text={token.text} />
    </span>
  )
}

export function App() {
  const params = new URLSearchParams(window.location.search)
  const paramEffect = params.get('effect') as EffectKey | null

  const [tokens, setTokens] = React.useState<Token[]>([])
  const [effect, setEffect] = React.useState<EffectKey>(
    paramEffect && CORRECTION_EFFECTS[paramEffect] ? paramEffect : 'swipe',
  )
  const [running, setRunning] = React.useState(false)
  const cancelled = React.useRef(false)
  const started = React.useRef(false)

  const append = (id: string, text: string, confidence?: number) =>
    setTokens((t) => [...t, { id, text, state: 'interim', confidence }])
  const revise = (id: string, text: string) =>
    setTokens((t) => t.map((x) => (x.id === id ? { ...x, text, confidence: 0.95 } : x)))
  const redact = (id: string) =>
    setTokens((t) => t.map((x) => (x.id === id ? { ...x, redacted: true } : x)))
  const finalizeAll = () =>
    setTokens((t) => t.map((x) => ({ ...x, state: 'final' as const })))

  const run = React.useCallback(async () => {
    cancelled.current = false
    setRunning(true)
    const s = async (ms: number) => {
      await sleep(ms)
      return cancelled.current
    }
    // Loop the whole transcript until cancelled.
    while (!cancelled.current) {
      setTokens([])
      if (await s(600)) break
      let broke = false
      for (const step of SCRIPT) {
        if (cancelled.current) {
          broke = true
          break
        }
        if (step.op === 'add') append(step.id, step.text, step.conf)
        else if (step.op === 'fix') revise(step.id, step.text)
        else if (step.op === 'redact') redact(step.id)
        else finalizeAll()
        if (await s(step.gap ?? 180)) {
          broke = true
          break
        }
      }
      if (broke) break
    }
    setRunning(false)
  }, [])

  React.useEffect(() => {
    const t = setTimeout(() => {
      if (!started.current) {
        started.current = true
        run()
      }
    }, 400)
    return () => clearTimeout(t)
  }, [run])

  function replay() {
    cancelled.current = true
    setRunning(false)
    setTimeout(() => run(), 80)
  }

  const allFinal = tokens.length > 0 && tokens.every((t) => t.state === 'final')

  return (
    <main className="page">
      <header>
        <h1>transcript&nbsp;fx</h1>
        <p>Live transcription that corrects itself in place — choose how a correction animates.</p>
      </header>

      <div className="effects">
        {EFFECT_META.map((e) => (
          <button
            key={e.key}
            className={`chip ${effect === e.key ? 'on' : ''}`}
            onClick={() => setEffect(e.key)}
          >
            {e.label}
          </button>
        ))}
        <button className="chip run" onClick={replay}>
          ↻ Restart
        </button>
      </div>
      <p className="blurb">{EFFECT_META.find((e) => e.key === effect)?.blurb}</p>

      <section className="surface">
        <div className="bubble">
          <div className="meta">
            <span className="name">Jon</span>
            <span className="time">0:18</span>
            {tokens.length > 0 && !allFinal && <span className="tag">PREVIEW</span>}
          </div>
          <div className="line">
            {tokens.map((t) => (
              <React.Fragment key={t.id}>
                <TokenView token={t} effect={effect} />{' '}
              </React.Fragment>
            ))}
            {running && !allFinal && <span className="caret" aria-hidden="true" />}
          </div>
        </div>
        <p className="hint">
          5 live corrections (<b>cue→Q3, to→two, their→there, tree→three, ate→eight</b>) and 2
          redactions (<b>Acme, Sarah</b>). Confidence shows as dimness; words settle when finalised.
          Loops continuously.
        </p>
      </section>

      <footer>One spec, two native runtimes — this React lab is the reference for the SwiftUI port.</footer>
    </main>
  )
}

import * as React from 'react'

const GLYPHS = '!<>-_\\/[]{}—=+*^?#abcdef0123456789'

/** Characters roll through random glyphs, resolving left→right onto the target. */
export function useScramble(text: string): string {
  const [display, setDisplay] = React.useState(text)
  const prev = React.useRef(text)
  React.useEffect(() => {
    if (prev.current === text) {
      setDisplay(text)
      return
    }
    prev.current = text
    const target = text
    let frame = 0
    const id = window.setInterval(() => {
      frame++
      const resolved = Math.floor(frame / 1.4)
      let out = ''
      for (let i = 0; i < target.length; i++) {
        out += i < resolved ? target[i] : GLYPHS[Math.floor(Math.random() * GLYPHS.length)]
      }
      setDisplay(out)
      if (resolved >= target.length) {
        window.clearInterval(id)
        setDisplay(target)
      }
    }, 28)
    return () => window.clearInterval(id)
  }, [text])
  return display
}

type FxProps = { text: string }

export function ScrambleText({ text }: FxProps) {
  return <span className="fx-scramble">{useScramble(text)}</span>
}

export function BlurText({ text }: FxProps) {
  // key remount → the blur-in keyframe replays whenever the word changes
  return (
    <span key={text} className="fx-blur">
      {text}
    </span>
  )
}

export function SettleText({ text }: FxProps) {
  return (
    <span key={text} className="fx-settle">
      {text}
    </span>
  )
}

/** A coloured block sweeps over the word, the text swaps underneath, the block sweeps off. */
export function SwipeText({ text }: FxProps) {
  const [shown, setShown] = React.useState(text)
  const [sweeping, setSweeping] = React.useState(false)
  const prev = React.useRef(text)
  React.useEffect(() => {
    if (prev.current === text) {
      setShown(text)
      return
    }
    prev.current = text
    setSweeping(true)
    const swap = window.setTimeout(() => setShown(text), 260)
    const end = window.setTimeout(() => setSweeping(false), 560)
    return () => {
      window.clearTimeout(swap)
      window.clearTimeout(end)
    }
  }, [text])
  return (
    <span className="fx-swipe">
      {shown}
      {sweeping && <span className="fx-swipe-block" aria-hidden="true" />}
    </span>
  )
}

function commonPrefixLen(a: string, b: string) {
  let i = 0
  const max = Math.min(a.length, b.length)
  while (i < max && a[i] === b[i]) i++
  return i
}
function diffParts(a: string, b: string) {
  const p = commonPrefixLen(a, b)
  let s = 0
  const maxS = Math.min(a.length - p, b.length - p)
  while (s < maxS && a[a.length - 1 - s] === b[b.length - 1 - s]) s++
  return { prefix: b.slice(0, p), middle: b.slice(p, b.length - s), suffix: b.slice(b.length - s) }
}

/** Only the characters that actually changed animate; the rest stay anchored. */
export function DiffMorphText({ text }: FxProps) {
  const prev = React.useRef(text)
  const [st, setSt] = React.useState(() => ({
    prefix: '',
    middle: text,
    suffix: '',
    key: 0,
    animate: false,
  }))
  React.useEffect(() => {
    if (prev.current === text) return
    const parts = diffParts(prev.current, text)
    prev.current = text
    setSt((s) => ({ ...parts, key: s.key + 1, animate: true }))
  }, [text])
  return (
    <span className="fx-diff">
      <span className="dm-static">{st.prefix}</span>
      <span className="dm-mid" key={st.key}>
        {Array.from(st.middle).map((ch, i) => (
          <span
            key={i}
            className={st.animate ? 'dm-char anim' : 'dm-char'}
            style={st.animate ? { animationDelay: `${i * 30}ms` } : undefined}
          >
            {ch}
          </span>
        ))}
      </span>
      <span className="dm-static">{st.suffix}</span>
    </span>
  )
}

export const CORRECTION_EFFECTS = {
  settle: SettleText,
  scramble: ScrambleText,
  blur: BlurText,
  swipe: SwipeText,
  diff: DiffMorphText,
  ink: SettleText, // ink's signature is base type-weight; corrections crossfade
} as const

export type EffectKey = keyof typeof CORRECTION_EFFECTS

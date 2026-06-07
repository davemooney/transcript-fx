/**
 * <revising-text> — framework-agnostic Web Component for live, self-revising
 * transcription text. Implements SPEC.md §3: ink-settle base, diff-morph
 * corrections, swipe redaction, correction flash. Works in React/Vue/vanilla.
 *
 *   const el = document.querySelector('revising-text')
 *   el.append('0-0', 'cue', 0.4); el.revise('0-0', 'Q3'); el.redact('0-1'); el.finalize()
 *   // or drive it from Deepgram: createDeepgramConsumer(el)
 */

import type { TranscriptSink } from './deepgram'

export interface RTToken {
  id: string
  text: string
  state?: 'volatile' | 'final'
  confidence?: number
  redacted?: boolean
}

const GLYPH_DELAY = 30

const CSS = `
:host { display: block; }
.rt-line { font: var(--rt-font, 24px/1.7 ui-sans-serif, system-ui, -apple-system, sans-serif); color: var(--rt-fg, #fafafa); }
.rt-tok { display: inline-block; transition: opacity .4s ease, font-weight .4s ease; font-weight: 600; }
.rt-tok + .rt-tok { margin-left: .28em; }
.rt-tok[data-state="volatile"] { font-weight: 300; opacity: .6; }
.rt-tok[data-state="volatile"][data-low="1"] { font-weight: 200; opacity: .4; }
.rt-tok[data-state="final"] { font-weight: 600; opacity: 1; }
.rt-tok.rt-appear { animation: rt-appear .3s ease; }
@keyframes rt-appear { from { transform: translateY(4px); filter: blur(3px); } }
.rt-dm { display: inline-block; white-space: pre; animation: rt-dm-in .4s cubic-bezier(.2,.8,.2,1) both; }
@keyframes rt-dm-in { from { opacity: 0; filter: blur(4px); transform: translateY(.22em); } to { opacity: 1; filter: blur(0); transform: none; } }
.rt-flash { animation: rt-flash 1.1s ease-out; border-radius: 4px; }
@keyframes rt-flash { 0% { background: rgba(129,140,248,.5); box-shadow: 0 0 0 3px rgba(129,140,248,.22); } 100% { background: transparent; box-shadow: 0 0 0 3px transparent; } }
.rt-redact { display: inline-block; color: transparent; border-radius: 3px; letter-spacing: -1px; user-select: none;
  background: linear-gradient(100deg, #34d399 0%, #6ee7b7 45%, #34d399 72%); background-size: 220% 100%; background-position: 0 0;
  animation: rt-redact .6s cubic-bezier(.4,0,.2,1); }
@keyframes rt-redact { from { background-position: 220% 0; opacity: .55; } to { background-position: 0 0; opacity: 1; } }
@media (prefers-reduced-motion: reduce) { .rt-dm, .rt-flash, .rt-redact { animation: none; } }
`

function diffParts(a: string, b: string) {
  let p = 0
  const maxP = Math.min(a.length, b.length)
  while (p < maxP && a[p] === b[p]) p++
  let s = 0
  const maxS = Math.min(a.length - p, b.length - p)
  while (s < maxS && a[a.length - 1 - s] === b[b.length - 1 - s]) s++
  return { prefix: b.slice(0, p), middle: b.slice(p, b.length - s), suffix: b.slice(b.length - s) }
}

interface Entry {
  el: HTMLSpanElement
  text: string
  redacted: boolean
}

export class RevisingTextElement extends HTMLElement {
  private container: HTMLDivElement
  private entries = new Map<string, Entry>()
  private _tokens: RTToken[] = []

  constructor() {
    super()
    const root = this.attachShadow({ mode: 'open' })
    const style = document.createElement('style')
    style.textContent = CSS
    this.container = document.createElement('div')
    this.container.className = 'rt-line'
    root.append(style, this.container)
  }

  set tokens(list: RTToken[]) {
    this._tokens = list.slice()
    this.reconcile()
  }
  get tokens(): RTToken[] {
    return this._tokens
  }

  // Imperative event surface. Named pushToken/removeToken to avoid clashing
  // with the built-in HTMLElement.append()/remove(). Use asSink() for Deepgram.
  pushToken(id: string, text: string, confidence?: number): void {
    this._tokens.push({ id, text, state: 'volatile', confidence })
    this.reconcile()
  }
  revise(id: string, text: string): void {
    const t = this._tokens.find((x) => x.id === id)
    if (t) {
      t.text = text
      t.confidence = 0.95
    }
    this.reconcile()
  }
  redact(id: string): void {
    const t = this._tokens.find((x) => x.id === id)
    if (t) t.redacted = true
    this.reconcile()
  }
  removeToken(id: string): void {
    this._tokens = this._tokens.filter((x) => x.id !== id)
    this.reconcile()
  }

  /** A Deepgram-compatible sink wired to this element.
   *  Use: createDeepgramConsumer(el.asSink()). */
  asSink(): TranscriptSink {
    return {
      append: (id, text, confidence) => this.pushToken(id, text, confidence),
      revise: (id, text) => this.revise(id, text),
      remove: (id) => this.removeToken(id),
      finalize: () => this.finalize(),
    }
  }
  finalize(): void {
    for (const t of this._tokens) t.state = 'final'
    this.reconcile()
  }
  clear(): void {
    this._tokens = []
    this.reconcile()
  }

  private reconcile(): void {
    const seen = new Set<string>()
    for (const tok of this._tokens) {
      seen.add(tok.id)
      let entry = this.entries.get(tok.id)
      if (!entry) {
        const el = document.createElement('span')
        el.className = 'rt-tok rt-appear'
        this.container.appendChild(el)
        entry = { el, text: '', redacted: false }
        this.entries.set(tok.id, entry)
      }
      this.renderToken(entry, tok)
    }
    for (const [id, entry] of this.entries) {
      if (!seen.has(id)) {
        entry.el.remove()
        this.entries.delete(id)
      }
    }
    // keep DOM order in sync with token order (handles refiner inserts/reorders)
    this._tokens.forEach((tok, idx) => {
      const el = this.entries.get(tok.id)!.el
      const current = this.container.children[idx]
      if (current !== el) this.container.insertBefore(el, current ?? null)
    })
  }

  private renderToken(entry: Entry, tok: RTToken): void {
    const el = entry.el
    el.dataset.state = tok.state ?? 'volatile'
    el.dataset.low = tok.confidence != null && tok.confidence < 0.6 ? '1' : ''

    if (tok.redacted) {
      if (!entry.redacted) {
        entry.redacted = true
        el.innerHTML = ''
        const block = document.createElement('span')
        block.className = 'rt-redact'
        block.textContent = '████'
        el.appendChild(block)
      }
      entry.text = tok.text
      return
    }

    const isFirst = entry.text === ''
    const changed = !isFirst && entry.text !== tok.text
    if (changed) {
      this.renderDiff(el, entry.text, tok.text)
      el.classList.remove('rt-flash')
      void el.offsetWidth // restart the flash animation
      el.classList.add('rt-flash')
    } else if (el.childNodes.length === 0 || isFirst) {
      el.textContent = tok.text
    }
    entry.text = tok.text
  }

  private renderDiff(el: HTMLSpanElement, oldText: string, newText: string): void {
    const { prefix, middle, suffix } = diffParts(oldText, newText)
    el.textContent = ''
    el.append(document.createTextNode(prefix))
    const mid = document.createElement('span')
    Array.from(middle).forEach((ch, i) => {
      const c = document.createElement('span')
      c.className = 'rt-dm'
      c.textContent = ch
      c.style.animationDelay = `${i * GLYPH_DELAY}ms`
      mid.appendChild(c)
    })
    el.appendChild(mid)
    el.append(document.createTextNode(suffix))
  }
}

if (typeof customElements !== 'undefined' && !customElements.get('revising-text')) {
  customElements.define('revising-text', RevisingTextElement)
}

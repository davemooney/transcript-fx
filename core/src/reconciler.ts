import type { ASRResult, ASRWord, SourceRole } from './asr'
import { resultWords } from './asr'
import type { RevisionEvent } from './revision-event'

/**
 * Reconciles 1+ ASR sources into a single token timeline. (SPEC §2b)
 *
 *  - `draft`  results extend/refine the active utterance by index (fast tier).
 *  - `refined` results re-align onto the active utterance — by word time-overlap
 *    when timestamps exist (surgical revise/insert/delete), else by index —
 *    reusing token ids so the UI diff-morphs corrections instead of redrawing.
 *
 * "Two tiers of one model" and "two combined models" are the same to this:
 * a draft stream + a refinement stream over one audio timeline.
 *
 * v2 contract (ported from the SwiftUI runtime for parity — SPEC top note):
 *  - every call returns explicit `RevisionEvent[]` (insert/remove/revise/
 *    replace/redact/finalize) — no snapshot diffing needed;
 *  - each token carries a `revision` counter that bumps ONLY on a real tier-2
 *    correction (a `refined` change or an explicit `revise()`), never on a
 *    volatile preview rewriting its own un-committed text (#5125). The morph/
 *    flash keys off `revision`, so already-shown preview text never flashes
 *    before a refinement actually lands.
 */

export interface ReconToken {
  id: string
  text: string
  state: 'volatile' | 'final'
  confidence?: number
  start?: number
  end?: number
  /** Masked span (SPEC §3 redaction). */
  redacted?: boolean
  /** Bumps on every tier-2 correction; views key the morph/flash off it. */
  revision: number
}

export interface ReconcilerOptions {
  onChange?: (tokens: ReconToken[]) => void
  /** Called with the explicit semantic events emitted by each call. */
  onEvents?: (events: RevisionEvent[]) => void
}

export class TranscriptReconciler {
  private toks: ReconToken[] = []
  private activeStart = 0
  private seq = 0
  private onChange?: (tokens: ReconToken[]) => void
  private onEvents?: (events: RevisionEvent[]) => void

  constructor(opts: ReconcilerOptions = {}) {
    this.onChange = opts.onChange
    this.onEvents = opts.onEvents
  }

  get tokens(): ReconToken[] {
    return this.toks
  }

  reset(): void {
    this.toks = []
    this.activeStart = 0
    this.seq = 0
    this.emit([])
  }

  ingest(result: ASRResult, role: SourceRole = 'draft'): RevisionEvent[] {
    const words = resultWords(result)
    const events =
      role === 'refined'
        ? this.ingestRefined(words, result.isFinal)
        : this.ingestDraft(words, result.isFinal)
    this.emit(events)
    return events
  }

  // ── Imperative event surface (the seed-fixture / direct-sink path) ──
  // `append` is a volatile new word; `revise` is an explicit tier-2 correction
  // (flashes); `redact` masks; `finalizeAll` settles. These mirror SPEC §1.

  /** A new volatile token (preview append). */
  append(id: string, text: string, confidence?: number): RevisionEvent[] {
    const events: RevisionEvent[] = []
    const idx = this.toks.length
    this.toks.push({ id, text, state: 'volatile', confidence, revision: 0 })
    events.push({ type: 'insert', id, index: idx })
    this.emit(events)
    return events
  }

  /** An explicit tier-2 correction: morphs in place, bumps revision, flashes. */
  revise(id: string, text: string): RevisionEvent[] {
    const events: RevisionEvent[] = []
    const t = this.toks.find((x) => x.id === id)
    if (t && t.text !== text) {
      const oldText = t.text
      t.text = text
      t.confidence = 0.95
      t.revision += 1
      events.push({ type: 'revise', id, oldText, newText: text })
    }
    this.emit(events)
    return events
  }

  /** Mask a token (swipe redaction). */
  redact(id: string): RevisionEvent[] {
    const events: RevisionEvent[] = []
    const t = this.toks.find((x) => x.id === id)
    if (t && !t.redacted) {
      t.redacted = true
      events.push({ type: 'redact', id })
    }
    this.emit(events)
    return events
  }

  /** Commit everything (ink settles). */
  finalizeAll(): RevisionEvent[] {
    const ids: string[] = []
    for (const t of this.toks) {
      if (t.state !== 'final') {
        t.state = 'final'
        ids.push(t.id)
      }
    }
    const events: RevisionEvent[] = ids.length ? [{ type: 'finalize', ids }] : []
    this.emit(events)
    return events
  }

  private emit(events: RevisionEvent[]) {
    this.onChange?.(this.toks)
    if (events.length) this.onEvents?.(events)
  }
  private newId() {
    return `t${this.seq++}`
  }
  private makeToken(w: ASRWord, isFinal: boolean): ReconToken {
    return {
      id: this.newId(),
      text: w.text,
      state: isFinal ? 'final' : 'volatile',
      confidence: w.confidence,
      start: w.start,
      end: w.end,
      revision: 0,
    }
  }

  /**
   * Fast tier: reconcile the active utterance by word index. A preview
   * rewriting its own un-committed word updates the text but does NOT bump
   * `revision` or emit `revise` — that silent settle is the #5125 contract.
   */
  private ingestDraft(words: ASRWord[], isFinal: boolean): RevisionEvent[] {
    const events: RevisionEvent[] = []
    const base = this.activeStart
    for (let i = 0; i < words.length; i++) {
      const w = words[i]
      const idx = base + i
      if (idx < this.toks.length) {
        const t = this.toks[idx]
        t.text = w.text // silent preview rewrite — no revise, no revision bump
        if (w.confidence != null) t.confidence = w.confidence
        if (w.start != null) t.start = w.start
        if (w.end != null) t.end = w.end
      } else {
        const tok = this.makeToken(w, false)
        this.toks.push(tok)
        events.push({ type: 'insert', id: tok.id, index: idx })
      }
    }
    if (base + words.length < this.toks.length) {
      for (let i = base + words.length; i < this.toks.length; i++) {
        events.push({ type: 'remove', id: this.toks[i].id })
      }
      this.toks.length = base + words.length
    }
    if (isFinal) {
      const ids: string[] = []
      for (let i = base; i < this.toks.length; i++) {
        if (this.toks[i].state !== 'final') {
          this.toks[i].state = 'final'
          ids.push(this.toks[i].id)
        }
      }
      if (ids.length) events.push({ type: 'finalize', ids })
      this.activeStart = this.toks.length
    }
    return events
  }

  /** Slow tier: re-align onto the active utterance (time-aware), reusing ids.
   *  A text change here IS a tier-2 correction → revise + revision bump. */
  private ingestRefined(words: ASRWord[], isFinal: boolean): RevisionEvent[] {
    const events: RevisionEvent[] = []
    const haveTimes = words.length > 0 && words.every((w) => w.start != null && w.end != null)
    const region = this.toks.slice(this.activeStart)
    const rebuilt: ReconToken[] = []
    let i = 0
    let j = 0
    while (i < words.length || j < region.length) {
      const w = words[i]
      const tk = region[j]
      if (w && tk) {
        const pair = haveTimes
          ? overlap(w.start!, w.end!, tk.start ?? -Infinity, tk.end ?? Infinity) > 0
          : true // no timestamps → align by index
        if (pair) {
          if (tk.text !== w.text) {
            events.push({ type: 'revise', id: tk.id, oldText: tk.text, newText: w.text })
            tk.text = w.text
            tk.revision += 1
          }
          tk.confidence = w.confidence ?? 0.95
          if (haveTimes) {
            tk.start = w.start
            tk.end = w.end
          }
          rebuilt.push(tk)
          i++
          j++
        } else if (haveTimes && w.end! <= (tk.start ?? Infinity)) {
          const tok = this.makeToken(w, isFinal) // insertion before this token
          rebuilt.push(tok)
          events.push({ type: 'insert', id: tok.id, index: this.activeStart + rebuilt.length - 1 })
          i++
        } else {
          events.push({ type: 'remove', id: tk.id }) // deletion: drop tk
          j++
        }
      } else if (w) {
        const tok = this.makeToken(w, isFinal)
        rebuilt.push(tok)
        events.push({ type: 'insert', id: tok.id, index: this.activeStart + rebuilt.length - 1 })
        i++
      } else {
        events.push({ type: 'remove', id: tk.id }) // trailing deletion
        j++
      }
    }
    this.toks.splice(this.activeStart, region.length, ...rebuilt)
    if (isFinal) {
      const ids: string[] = []
      for (const t of rebuilt) {
        if (t.state !== 'final') {
          t.state = 'final'
          ids.push(t.id)
        }
      }
      if (ids.length) events.push({ type: 'finalize', ids })
      this.activeStart = this.toks.length
    }
    return events
  }
}

function overlap(a0: number, a1: number, b0: number, b1: number): number {
  return Math.max(0, Math.min(a1, b1) - Math.max(a0, b0))
}

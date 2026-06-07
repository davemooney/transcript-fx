import type { ASRResult, ASRWord, SourceRole } from './asr'
import { resultWords } from './asr'

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
 */

export interface ReconToken {
  id: string
  text: string
  state: 'volatile' | 'final'
  confidence?: number
  start?: number
  end?: number
}

export interface ReconcilerOptions {
  onChange?: (tokens: ReconToken[]) => void
}

export class TranscriptReconciler {
  private toks: ReconToken[] = []
  private activeStart = 0
  private seq = 0
  private onChange?: (tokens: ReconToken[]) => void

  constructor(opts: ReconcilerOptions = {}) {
    this.onChange = opts.onChange
  }

  get tokens(): ReconToken[] {
    return this.toks
  }

  reset(): void {
    this.toks = []
    this.activeStart = 0
    this.seq = 0
    this.emit()
  }

  ingest(result: ASRResult, role: SourceRole = 'draft'): void {
    const words = resultWords(result)
    if (role === 'refined') this.ingestRefined(words, result.isFinal)
    else this.ingestDraft(words, result.isFinal)
    this.emit()
  }

  private emit() {
    this.onChange?.(this.toks)
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
    }
  }

  /** Fast tier: reconcile the active utterance by word index. */
  private ingestDraft(words: ASRWord[], isFinal: boolean): void {
    const base = this.activeStart
    for (let i = 0; i < words.length; i++) {
      const w = words[i]
      const idx = base + i
      if (idx < this.toks.length) {
        const t = this.toks[idx]
        t.text = w.text
        if (w.confidence != null) t.confidence = w.confidence
        if (w.start != null) t.start = w.start
        if (w.end != null) t.end = w.end
      } else {
        this.toks.push(this.makeToken(w, false))
      }
    }
    if (base + words.length < this.toks.length) this.toks.length = base + words.length
    if (isFinal) {
      for (let i = base; i < this.toks.length; i++) this.toks[i].state = 'final'
      this.activeStart = this.toks.length
    }
  }

  /** Slow tier: re-align onto the active utterance (time-aware), reusing ids. */
  private ingestRefined(words: ASRWord[], isFinal: boolean): void {
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
          tk.text = w.text
          tk.confidence = w.confidence ?? 0.95
          if (haveTimes) {
            tk.start = w.start
            tk.end = w.end
          }
          rebuilt.push(tk)
          i++
          j++
        } else if (haveTimes && w.end! <= (tk.start ?? Infinity)) {
          rebuilt.push(this.makeToken(w, isFinal)) // insertion before this token
          i++
        } else {
          j++ // deletion: drop tk
        }
      } else if (w) {
        rebuilt.push(this.makeToken(w, isFinal))
        i++
      } else {
        j++ // trailing deletion
      }
    }
    this.toks.splice(this.activeStart, region.length, ...rebuilt)
    if (isFinal) {
      for (const t of rebuilt) t.state = 'final'
      this.activeStart = this.toks.length
    }
  }
}

function overlap(a0: number, a1: number, b0: number, b1: number): number {
  return Math.max(0, Math.min(a1, b1) - Math.max(a0, b0))
}

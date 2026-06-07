/**
 * The canonical ASR result — the ONE type any provider/tier maps to. (SPEC §2)
 * Works with the dumbest model (just `transcript` + `isFinal`) and gets better
 * with richer fields: `confidence` unlocks ink-settle, `start/end` unlock clean
 * time-aligned combining of a draft + a refiner stream.
 */
export type Seconds = number

export interface ASRWord {
  text: string
  start?: Seconds
  end?: Seconds
  confidence?: number
}

export interface ASRResult {
  /** Word-level if available… */
  words?: ASRWord[]
  /** …otherwise we tokenize this. */
  transcript?: string
  /** Is this span committed (vs. an interim hypothesis)? */
  isFinal: boolean
  /** Optional segment id from the provider. */
  utteranceId?: string
}

/** A source's role in a combined setup. (Same shape whether it's two tiers of
 *  one model or two separate models.) */
export type SourceRole = 'draft' | 'refined'

/** Normalize a result to words — splitting `transcript` when no word list. */
export function resultWords(r: ASRResult): ASRWord[] {
  if (r.words && r.words.length) return r.words
  const t = (r.transcript ?? '').trim()
  return t ? t.split(/\s+/).map((text) => ({ text })) : []
}

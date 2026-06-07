/** Deepgram streaming → transcript-fx events (SPEC §2). See repo SPEC.md. */
import type { ASRResult } from './asr'

export interface DeepgramWord {
  word: string
  punctuated_word?: string
  confidence: number
  start?: number
  end?: number
}
export interface DeepgramAlternative {
  transcript: string
  confidence: number
  words: DeepgramWord[]
}
export interface DeepgramResult {
  channel?: { alternatives?: DeepgramAlternative[] }
  is_final?: boolean
}

export interface TranscriptSink {
  append(id: string, text: string, confidence?: number): void
  revise(id: string, text: string): void
  remove?(id: string): void
  finalize?(): void
}

/** Map a Deepgram result to the canonical ASRResult (feed a TranscriptReconciler). */
export function deepgramToASR(res: DeepgramResult): ASRResult {
  const alt = res.channel?.alternatives?.[0]
  const words = (alt?.words ?? []).map((w) => ({
    text: w.punctuated_word ?? w.word,
    confidence: w.confidence,
    start: w.start,
    end: w.end,
  }))
  return { words, transcript: alt?.transcript, isFinal: !!res.is_final }
}

export function createDeepgramConsumer(sink: TranscriptSink) {
  let segment = 0
  const live: { id: string; text: string }[] = []

  function reset() {
    segment = 0
    live.length = 0
  }

  function applyResult(res: DeepgramResult): void {
    const alt = res.channel?.alternatives?.[0]
    if (!alt) return
    const words = alt.words ?? []
    for (let i = 0; i < words.length; i++) {
      const text = words[i].punctuated_word ?? words[i].word
      if (i < live.length) {
        if (live[i].text !== text) {
          sink.revise(live[i].id, text)
          live[i].text = text
        }
      } else {
        const id = `${segment}-${i}`
        sink.append(id, text, words[i].confidence)
        live.push({ id, text })
      }
    }
    for (let i = words.length; i < live.length; i++) sink.remove?.(live[i].id)
    if (words.length < live.length) live.length = words.length
    if (res.is_final) {
      segment++
      live.length = 0
    }
  }

  return { applyResult, reset }
}

/**
 * Deepgram streaming → transcript-fx events (SPEC §2).
 *
 * Deepgram emits interim results that refine the current utterance, then an
 * `is_final` result commits it. This consumer reconciles each interim result
 * word-by-word against the live segment and emits append/revise/remove, then
 * starts a fresh segment on commit. Pure + framework-agnostic — drive any sink
 * (the React state, the Web Component, or a test).
 */

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
  speech_final?: boolean
}

export interface TranscriptSink {
  append(id: string, text: string, confidence?: number): void
  revise(id: string, text: string): void
  remove?(id: string): void
  finalize?(): void
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

    // interim shrank → drop trailing words
    for (let i = words.length; i < live.length; i++) sink.remove?.(live[i].id)
    if (words.length < live.length) live.length = words.length

    if (res.is_final) {
      segment++
      live.length = 0
    }
  }

  return { applyResult, reset }
}

/**
 * Thin WebSocket wrapper (untested here — needs a live key + audio).
 * Pipe mic audio in, get reconciled events out via `sink`.
 */
export function streamDeepgram(opts: {
  apiKey: string
  sink: TranscriptSink
  url?: string
  onOpen?: (ws: WebSocket) => void
}): WebSocket {
  const url =
    opts.url ??
    'wss://api.deepgram.com/v1/listen?model=nova-3&interim_results=true&punctuate=true'
  const ws = new WebSocket(url, ['token', opts.apiKey])
  const consumer = createDeepgramConsumer(opts.sink)
  ws.addEventListener('open', () => opts.onOpen?.(ws))
  ws.addEventListener('message', (e) => {
    try {
      const data = JSON.parse(typeof e.data === 'string' ? e.data : '')
      if (data?.type === 'Results') consumer.applyResult(data as DeepgramResult)
    } catch {
      /* ignore non-JSON keepalives */
    }
  })
  return ws
}

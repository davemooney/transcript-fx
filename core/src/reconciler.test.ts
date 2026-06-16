import { describe, it, expect } from 'vitest'
import { TranscriptReconciler } from './reconciler'

const snap = (r: TranscriptReconciler) => r.tokens.map((t) => `${t.text}/${t.state}`)

describe('TranscriptReconciler', () => {
  it('single source: interim → revise → commit keeps token id stable', () => {
    const r = new TranscriptReconciler()
    r.ingest({ words: [{ text: 'set' }, { text: 'a' }], isFinal: false })
    const id0 = r.tokens[0].id
    r.ingest({ words: [{ text: 'said' }, { text: 'a' }], isFinal: false })
    expect(r.tokens[0].id).toBe(id0) // id stable across silent preview rewrite
    r.ingest({ words: [{ text: 'said' }, { text: 'a' }, { text: 'timer' }], isFinal: true })
    expect(snap(r)).toEqual(['said/final', 'a/final', 'timer/final'])
  })

  it('preview rewrite of un-committed text is SILENT (no revise, no revision bump) — #5125', () => {
    const r = new TranscriptReconciler()
    r.ingest({ words: [{ text: 'set' }, { text: 'a' }], isFinal: false })
    const rev0 = r.tokens[0].revision
    const events = r.ingest({ words: [{ text: 'said' }, { text: 'a' }, { text: 'timer' }], isFinal: false })
    expect(r.tokens[0].text).toBe('said') // text still updates
    expect(r.tokens[0].revision).toBe(rev0) // but revision must NOT bump
    expect(events.some((e) => e.type === 'revise')).toBe(false) // no flashing revise
    expect(events.some((e) => e.type === 'insert')).toBe(true) // the new word inserts
  })

  it('two sources: refiner correction reuses the token id and emits revise + bumps revision', () => {
    const r = new TranscriptReconciler()
    r.ingest(
      {
        words: [
          { text: 'their', start: 0, end: 0.4 },
          { text: 'meeting', start: 0.4, end: 0.8 },
          { text: 'is', start: 0.8, end: 1.0 },
        ],
        isFinal: false,
      },
      'draft',
    )
    const id0 = r.tokens[0].id
    const events = r.ingest(
      {
        words: [
          { text: 'there', start: 0, end: 0.4, confidence: 0.98 },
          { text: 'meeting', start: 0.4, end: 0.8, confidence: 0.98 },
          { text: 'is', start: 0.8, end: 1.0, confidence: 0.98 },
        ],
        isFinal: true,
      },
      'refined',
    )
    expect(snap(r)).toEqual(['there/final', 'meeting/final', 'is/final'])
    expect(r.tokens[0].id).toBe(id0) // corrected token keeps its id → diff-morph
    expect(r.tokens[0].revision).toBe(1) // the refined correction bumped it
    expect(events).toContainEqual({ type: 'revise', id: id0, oldText: 'their', newText: 'there' })
  })

  it('refiner drops a hallucinated trailing word (deletion) and emits remove', () => {
    const r = new TranscriptReconciler()
    r.ingest(
      {
        words: [
          { text: 'the', start: 0, end: 0.3 },
          { text: 'quick', start: 0.3, end: 0.6 },
          { text: 'brownn', start: 0.6, end: 0.9 },
        ],
        isFinal: false,
      },
      'draft',
    )
    const droppedId = r.tokens[2].id
    const events = r.ingest(
      {
        words: [
          { text: 'the', start: 0, end: 0.3, confidence: 0.95 },
          { text: 'quick', start: 0.3, end: 0.6, confidence: 0.95 },
        ],
        isFinal: false,
      },
      'refined',
    )
    expect(r.tokens.map((t) => t.text)).toEqual(['the', 'quick'])
    expect(events).toContainEqual({ type: 'remove', id: droppedId })
  })

  it('no-timestamp fallback: refiner aligns by index (string transcript in)', () => {
    const r = new TranscriptReconciler()
    r.ingest({ transcript: 'lets meat at too', isFinal: false }, 'draft')
    r.ingest({ transcript: "let's meet at two", isFinal: true }, 'refined')
    expect(snap(r)).toEqual(["let's/final", 'meet/final', 'at/final', 'two/final'])
  })
})

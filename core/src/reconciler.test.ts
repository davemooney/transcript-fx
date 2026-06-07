import assert from 'node:assert'
import { TranscriptReconciler } from './reconciler'

const snap = (r: TranscriptReconciler) => r.tokens.map((t) => `${t.text}/${t.state}`)

// 1) Single source, streaming interim → revise → commit; token id stays stable.
{
  const r = new TranscriptReconciler()
  r.ingest({ words: [{ text: 'set' }, { text: 'a' }], isFinal: false })
  const id0 = r.tokens[0].id
  r.ingest({ words: [{ text: 'said' }, { text: 'a' }], isFinal: false })
  assert.strictEqual(r.tokens[0].id, id0, 'id stable across revise')
  r.ingest({ words: [{ text: 'said' }, { text: 'a' }, { text: 'timer' }], isFinal: true })
  assert.deepStrictEqual(snap(r), ['said/final', 'a/final', 'timer/final'])
}

// 2) Two sources: fast draft, then a refiner re-decodes the utterance and fixes a
//    word. Time-aligned → same token revised (animates), all committed.
{
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
  r.ingest(
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
  assert.deepStrictEqual(snap(r), ['there/final', 'meeting/final', 'is/final'])
  assert.strictEqual(r.tokens[0].id, id0, 'corrected token keeps its id → diff-morph')
}

// 3) Refiner drops a hallucinated trailing word (deletion).
{
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
  r.ingest(
    {
      words: [
        { text: 'the', start: 0, end: 0.3, confidence: 0.95 },
        { text: 'quick', start: 0.3, end: 0.6, confidence: 0.95 },
      ],
      isFinal: false,
    },
    'refined',
  )
  assert.deepStrictEqual(
    r.tokens.map((t) => t.text),
    ['the', 'quick'],
  )
}

// 4) No-timestamp fallback: refiner aligns by index (string transcript in).
{
  const r = new TranscriptReconciler()
  r.ingest({ transcript: 'lets meat at too', isFinal: false }, 'draft')
  r.ingest({ transcript: "let's meet at two", isFinal: true }, 'refined')
  assert.deepStrictEqual(snap(r), ["let's/final", 'meet/final', 'at/final', 'two/final'])
}

console.log('✓ reconciler: 4/4 cases pass (single-source, time-align, deletion, no-times fallback)')

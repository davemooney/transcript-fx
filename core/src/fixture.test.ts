import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { replaySession, type SessionFixture } from './session'
import type { RevisionEvent } from './revision-event'

/**
 * Cross-runtime parity (SPEC §5). Replays the SHARED reference fixture through
 * the web reconciler and asserts the exact RevisionEvent timeline. This frozen
 * golden IS the cross-runtime contract: the SwiftUI runtime replays the same
 * timeline and asserts the same sequence, so "web ≡ Swift" is a test, not a claim.
 *
 * The fixture's per-event `gap` is presentation-only — it never touches the
 * reconciled result, so this assertion is deterministic and timing-independent.
 */
const fixture = JSON.parse(
  readFileSync(fileURLToPath(new URL('../../fixtures/seed-session.json', import.meta.url)), 'utf8'),
) as SessionFixture

describe('seed-session fixture parity', () => {
  const { tokens, events } = replaySession(fixture)

  it('replays to the canonical 50-token transcript with Acme/Sarah masked', () => {
    expect(tokens).toHaveLength(50)
    const rendered = tokens.map((t) => (t.redacted ? '█' : t.text)).join(' ')
    expect(rendered).toBe(
      "okay so the Q3 deck is nearly ready let's loop in █ about the two deadlines there are three " +
        'open items we still need to close before Friday can you send the revenue figures to █ and ' +
        'update the margin slide we were off by about eight percent last quarter',
    )
  })

  it('emits exactly the 5 self-corrections as revise events (the morph/flash trigger)', () => {
    const revises = events.filter((e): e is Extract<RevisionEvent, { type: 'revise' }> => e.type === 'revise')
    expect(revises).toEqual([
      { type: 'revise', id: '4', oldText: 'cue', newText: 'Q3' },
      { type: 'revise', id: '15', oldText: 'to', newText: 'two' },
      { type: 'revise', id: '17', oldText: 'their', newText: 'there' },
      { type: 'revise', id: '19', oldText: 'tree', newText: 'three' },
      { type: 'revise', id: '47', oldText: 'ate', newText: 'eight' },
    ])
  })

  it('emits exactly the 2 redactions (Acme, Sarah)', () => {
    const redacts = events.filter((e) => e.type === 'redact')
    expect(redacts).toEqual([
      { type: 'redact', id: '12' },
      { type: 'redact', id: '36' },
    ])
  })

  it('every corrected token carries revision === 1; untouched tokens stay at 0', () => {
    const corrected = new Set(['4', '15', '17', '19', '47'])
    for (const t of tokens) {
      expect(t.revision).toBe(corrected.has(t.id) ? 1 : 0)
    }
  })

  it('finalizes all 50 tokens in a single commit at the end', () => {
    const finals = events.filter((e): e is Extract<RevisionEvent, { type: 'finalize' }> => e.type === 'finalize')
    expect(finals).toHaveLength(1)
    expect(finals[0].ids).toHaveLength(50)
    expect(tokens.every((t) => t.state === 'final')).toBe(true)
  })

  it('produces the frozen event-type timeline (web ≡ Swift golden)', () => {
    // Frozen golden — the cross-runtime contract. 50 inserts interleaved with
    // 5 revises (the self-corrections) and 2 redacts, closed by one finalize.
    const ins = (n: number) => Array<string>(n).fill('insert')
    expect(events.map((e) => e.type)).toEqual([
      ...ins(6), // 1..6
      'revise', // cue→Q3 (id 4)
      ...ins(10), // 7..16
      'revise', // to→two (id 15)
      ...ins(5), // 17..21
      'revise', // their→there (id 17)
      'revise', // tree→three (id 19)
      ...ins(27), // 22..48
      'revise', // ate→eight (id 47)
      ...ins(2), // 49..50
      'redact', // Acme (id 12)
      'redact', // Sarah (id 36)
      'finalize',
    ])
    // Sanity: 50 inserts, 5 revises, 2 redacts, 1 finalize = 58 events.
    expect(events).toHaveLength(58)
  })
})

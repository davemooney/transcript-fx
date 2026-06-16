/**
 * Replay a shared reference fixture (SPEC §5) through a reconciler and collect
 * the emitted RevisionEvent timeline. This is the cross-runtime parity surface:
 * the web golden produced here is asserted byte-for-byte in `fixture.test.ts`,
 * and the SwiftUI runtime replays the equivalent timeline and asserts the same
 * sequence — so web ≡ Swift is a test, not a claim.
 */
import { TranscriptReconciler } from './reconciler'
import type { ReconToken } from './reconciler'
import type { RevisionEvent } from './revision-event'

/** One source event in a reference session (SPEC §1). `gap` is presentation-only. */
export type SessionEvent =
  | { op: 'append'; id: string; text: string; confidence?: number; gap?: number }
  | { op: 'revise'; id: string; text: string; gap?: number }
  | { op: 'redact'; id: string; gap?: number }
  | { op: 'finalize'; gap?: number }

export interface SessionFixture {
  name: string
  description?: string
  config?: { confidenceThreshold?: number }
  events: SessionEvent[]
}

export interface ReplayResult {
  tokens: ReconToken[]
  events: RevisionEvent[]
}

/** Drive a reconciler through a fixture's timeline; return the final tokens and
 *  the full flat RevisionEvent stream (timing-independent, deterministic). */
export function replaySession(
  fixture: SessionFixture,
  recon: TranscriptReconciler = new TranscriptReconciler(),
): ReplayResult {
  const events: RevisionEvent[] = []
  for (const ev of fixture.events) {
    switch (ev.op) {
      case 'append':
        events.push(...recon.append(ev.id, ev.text, ev.confidence))
        break
      case 'revise':
        events.push(...recon.revise(ev.id, ev.text))
        break
      case 'redact':
        events.push(...recon.redact(ev.id))
        break
      case 'finalize':
        events.push(...recon.finalizeAll())
        break
    }
  }
  return { tokens: recon.tokens, events }
}

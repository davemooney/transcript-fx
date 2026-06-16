/**
 * Explicit, semantic description of what an event did to the transcript —
 * the web port of the Swift v2 `RevisionEvent` contract (SPEC §2b). The
 * reconciler returns these from every `ingest`/imperative call so apps can
 * drive haptics, analytics, a11y announcements, or custom rendering off them
 * without diffing snapshots themselves.
 *
 * Parity note: a volatile tier-1 preview rewriting its OWN un-committed word
 * settles silently — it keeps the token id, updates the text, but emits NO
 * `revise` and does NOT bump `revision`. `revise` (the morph/flash trigger)
 * is reserved for a real tier-2 correction. This is the #5125 contract the
 * SwiftUI runtime pins; the web core matches it so web ≡ Swift on the shared
 * fixtures.
 */
export type RevisionEvent =
  /** A new token appeared at `index` in the flat timeline. */
  | { type: 'insert'; id: string; index: number }
  /** A token was removed. */
  | { type: 'remove'; id: string }
  /** A token's text changed in place — identity kept, so it animates as a morph (flash). */
  | { type: 'revise'; id: string; oldText: string; newText: string }
  /** A token was swapped for a different one (identity could not be kept). */
  | { type: 'replace'; removedId: string; insertedId: string }
  /** A token was masked. */
  | { type: 'redact'; id: string }
  /** These tokens were committed and will never change again. */
  | { type: 'finalize'; ids: string[] }

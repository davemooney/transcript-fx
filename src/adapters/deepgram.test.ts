import assert from 'node:assert'
import { createDeepgramConsumer, type DeepgramResult } from './deepgram.ts'

type Op = [string, ...unknown[]]
const ops: Op[] = []
const sink = {
  append: (id: string, t: string) => ops.push(['append', id, t]),
  revise: (id: string, t: string) => ops.push(['revise', id, t]),
  remove: (id: string) => ops.push(['remove', id]),
}

const dg = createDeepgramConsumer(sink)

function R(words: string[], is_final = false): DeepgramResult {
  return {
    channel: {
      alternatives: [
        { transcript: words.join(' '), confidence: 0.9, words: words.map((w) => ({ word: w, confidence: 0.9 })) },
      ],
    },
    is_final,
  }
}

// interim refinement: "set a" → "said a" (revise) → "said a timer" → commit → new segment
dg.applyResult(R(['set', 'a']))
dg.applyResult(R(['said', 'a']))
dg.applyResult(R(['said', 'a', 'timer']))
dg.applyResult(R(['said', 'a', 'timer'], true))
dg.applyResult(R(['for']))

assert.deepStrictEqual(ops, [
  ['append', '0-0', 'set'],
  ['append', '0-1', 'a'],
  ['revise', '0-0', 'said'],
  ['append', '0-2', 'timer'],
  ['append', '1-0', 'for'],
])

// interim shrink → remove trailing word
const ops2: Op[] = []
const dg2 = createDeepgramConsumer({
  append: (id, t) => ops2.push(['append', id, t]),
  revise: (id, t) => ops2.push(['revise', id, t]),
  remove: (id) => ops2.push(['remove', id]),
})
dg2.applyResult(R(['the', 'quick', 'brownn']))
dg2.applyResult(R(['the', 'quick'])) // brownn dropped
assert.deepStrictEqual(ops2, [
  ['append', '0-0', 'the'],
  ['append', '0-1', 'quick'],
  ['append', '0-2', 'brownn'],
  ['remove', '0-2'],
])

console.log('✓ deepgram adapter: both cases pass (' + ops.length + ' + ' + ops2.length + ' ops)')

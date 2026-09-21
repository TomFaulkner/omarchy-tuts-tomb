const test = require("node:test")
const assert = require("node:assert/strict")
const Rules = require("../Rules.js")

const KS = Rules.KING_OF_SPADES
const ACE = 0          // ace of spades
const SIX = 5          // 6 of spades
const SEVEN = 6        // 7 of spades
const QUEEN = 11       // queen of spades
const HEART_KING = 25  // king of hearts
const HEART_ACE = 13

function game(partial) {
  const g = Rules.emptyGame()
  if (partial.pyramid) g.pyramid = partial.pyramid.slice()
  if (partial.stock) g.stock = partial.stock.slice()
  if (partial.waste) g.waste = partial.waste.slice()
  if (partial.removed) g.removed = partial.removed.slice()
  if (partial.score !== undefined) g.score = partial.score
  return g
}

function filled(cells) {
  const pyramid = new Array(28).fill(-1)
  Object.keys(cells).forEach((key) => { pyramid[Number(key)] = cells[key] })
  return pyramid
}

test("a deal is a full deck with the king of spades on the apex", () => {
  const seen = new Set()
  const a = Rules.deal(() => 0)
  const b = Rules.deal(() => 0)
  assert.equal(a.pyramid[0], KS)
  assert.equal(a.pyramid.length, 28)
  assert.equal(a.stock.length, 24)
  assert.equal(a.waste.length, 0)
  assert.equal(a.won, false)
  a.pyramid.forEach((cid) => {
    assert.ok(cid >= 0 && cid < 52)
    assert.equal(seen.has(cid), false)
    seen.add(cid)
  })
  a.stock.forEach((cid) => {
    assert.equal(seen.has(cid), false)
    seen.add(cid)
  })
  assert.equal(seen.size, 52)
  assert.deepEqual(a.pyramid, b.pyramid)
  assert.deepEqual(a.stock, b.stock)
  assert.equal(Rules.acceptSaved(a), true)
})

function rectsOverlap(a, b, w) {
  return a < b + w && b < a + w
}

test("a lower card overlaps only the two cards it was dealt onto", () => {
  for (let cw = 36; cw <= 168; cw++) {
    for (let row = 0; row <= 5; row++) {
      for (let col = 0; col <= row; col++) {
        const parent = Rules.pyramidX(row, col, cw)
        const left = Rules.pyramidX(row + 1, col, cw)
        const right = Rules.pyramidX(row + 1, col + 1, cw)
        assert.equal(rectsOverlap(parent, left, cw), true, `left cw ${cw} r ${row} c ${col}`)
        assert.equal(rectsOverlap(parent, right, cw), true, `right cw ${cw} r ${row} c ${col}`)
        if (col > 0) {
          const before = Rules.pyramidX(row + 1, col - 1, cw)
          assert.equal(rectsOverlap(parent, before, cw), false, `spill left cw ${cw}`)
        }
        const after = Rules.pyramidX(row + 1, col + 2, cw)
        assert.equal(rectsOverlap(parent, after, cw), false, `spill right cw ${cw}`)
      }
    }
  }
})

test("pyramid overlaps match the seven-row layout", () => {
  assert.deepEqual(Rules.coverIndexes(0), [1, 2])
  assert.deepEqual(Rules.coverIndexes(1), [3, 4])
  assert.deepEqual(Rules.coverIndexes(2), [4, 5])
  assert.deepEqual(Rules.coverIndexes(15), [21, 22])
  assert.deepEqual(Rules.coverIndexes(20), [26, 27])
  assert.deepEqual(Rules.coverIndexes(21), [])
  assert.deepEqual(Rules.coverIndexes(27), [])
  assert.equal(Rules.rowOf(0), 0)
  assert.equal(Rules.rowOf(1), 1)
  assert.equal(Rules.rowOf(20), 5)
  assert.equal(Rules.rowOf(21), 6)
})

test("only a free king comes off alone", () => {
  const buried = game({
    pyramid: filled({ 0: KS, 1: ACE, 2: SIX })
  })
  assert.equal(Rules.canRemoveKing(buried, "p0"), false)
  assert.equal(Rules.removeKing(buried, "p0", 0), null)
  assert.equal(buried.pyramid[0], KS)

  const free = game({ pyramid: filled({ 21: HEART_KING, 22: ACE }) })
  assert.equal(Rules.canRemoveKing(free, "p21"), true)
  const next = Rules.removeKing(free, "p21", 0)
  assert.equal(next.pyramid[21], -1)
  assert.equal(next.pyramid[22], ACE)
  assert.equal(next.won, false)
  assert.deepEqual(next.removed, [HEART_KING])
  assert.equal(next.score, Rules.SCORE_PYRAMID)
  assert.equal(free.pyramid[21], HEART_KING)
})

test("two free cards pair when they sum to 13", () => {
  const g = game({ pyramid: filled({ 21: SIX, 22: SEVEN, 23: ACE }) })
  assert.equal(Rules.canPair(g, "p21", "p22"), true)
  assert.equal(Rules.canPair(g, "p21", "p23"), false)
  const next = Rules.removePair(g, "p21", "p22", 0)
  assert.equal(next.pyramid[21], -1)
  assert.equal(next.pyramid[22], -1)
  assert.equal(next.pyramid[23], ACE)
  assert.equal(next.score, Rules.SCORE_PYRAMID * 2)
  assert.deepEqual(next.removed, [SIX, SEVEN])
})

test("a card pairs with the single card covering it, and with nothing else", () => {
  const open = game({
    pyramid: filled({ 15: QUEEN, 21: ACE }),
    waste: [SIX]
  })
  assert.equal(Rules.coverCount(open, 15), 1)
  assert.equal(Rules.canPair(open, "p15", "p21"), true)
  assert.equal(Rules.canPair(open, "p15", "w"), false)
  assert.deepEqual(Rules.partners(open, "p15"), ["p21"])

  const blocked = game({
    pyramid: filled({ 15: QUEEN, 21: ACE, 22: SIX })
  })
  assert.equal(Rules.canPair(blocked, "p15", "p21"), false)

  const coverBuried = game({
    pyramid: filled({ 14: QUEEN, 19: ACE, 25: SIX, 26: SEVEN })
  })
  // Row 4 index 14 is covered by row 5 indexes 19 and 20.
  // 19 is itself covered while 20 is gone, so the queen's only cover is buried.
  assert.equal(Rules.coverCount(coverBuried, 14), 1)
  assert.equal(Rules.canPair(coverBuried, "p14", "p19"), false)
})

test("the waste top pairs and a buried waste card does not", () => {
  const g = game({
    pyramid: filled({ 21: QUEEN }),
    waste: [ACE, SIX]
  })
  assert.equal(Rules.locOf(g, SIX), "w")
  assert.equal(Rules.locOf(g, ACE), "")
  assert.equal(Rules.canPair(g, "w", "p21"), false)
  g.waste = [SEVEN, QUEEN]
  g.pyramid = filled({ 21: ACE, 22: SIX })
  assert.equal(Rules.canPair(g, "w", "p21"), true)
  const next = Rules.removePair(g, "w", "p21", 10)
  assert.equal(next.won, false)
  assert.deepEqual(next.waste, [SEVEN])
  assert.equal(next.pyramid[21], -1)
  assert.equal(next.pyramid[22], SIX)
  assert.equal(next.score, Rules.SCORE_WASTE + Rules.SCORE_PYRAMID)
})

test("draw three keeps the third card on top, and the waste flips back", () => {
  const g = game({ stock: [0, 1, 2, 3, 4] })
  const drawn = Rules.draw(g)
  assert.deepEqual(drawn.stock, [0, 1])
  assert.deepEqual(drawn.waste, [4, 3, 2])
  assert.equal(g.stock.length, 5)

  const short = Rules.draw(game({ stock: [8, 9] }))
  assert.deepEqual(short.stock, [])
  assert.deepEqual(short.waste, [9, 8])

  const turned = Rules.draw(game({ waste: [4, 3, 2] }))
  assert.deepEqual(turned.stock, [2, 3, 4])
  assert.deepEqual(turned.waste, [])
  assert.equal(turned.passes, 1)
  assert.equal(Rules.draw(game({})), null)
})

test("clearing the pyramid wins once and pays the time bonus", () => {
  const g = game({ pyramid: filled({ 27: HEART_KING }) })
  const slow = Rules.removeKing(g, "p27", 200)
  assert.equal(slow.won, true)
  assert.equal(slow.winBonus, Rules.WIN_FLAT)
  assert.equal(slow.score, Rules.SCORE_PYRAMID + Rules.WIN_FLAT)
  assert.equal(Rules.removeKing(slow, "p27", 0), null)

  const fast = Rules.removeKing(g, "p27", 30)
  assert.equal(fast.winBonus, Rules.WIN_FLAT + (Rules.WIN_TIME - 30))
  assert.equal(Rules.clearedCount(fast), 28)
})

test("hint points at a buried pair before a draw", () => {
  const g = game({
    pyramid: filled({ 15: QUEEN, 21: HEART_ACE }),
    stock: [1, 2, 3]
  })
  const hint = Rules.findHint(g)
  assert.equal(hint.kind, "pair")
  assert.equal(hint.a, "p15")
  assert.equal(hint.b, "p21")
})

test("a saved game must still be one deck, with Tut on the apex or already removed", () => {
  const dealt = Rules.deal(() => 0.25)
  assert.equal(Rules.acceptSaved(dealt), true)
  const restored = Rules.fromSaved(dealt)
  assert.deepEqual(restored.pyramid, dealt.pyramid)
  assert.equal(restored.won, false)

  const moved = Rules.deal(() => 0.25)
  moved.pyramid[3] = KS
  moved.pyramid[0] = moved.stock.pop()
  assert.equal(Rules.acceptSaved(moved), false)

  const duplicate = Rules.deal(() => 0.25)
  duplicate.stock[0] = duplicate.pyramid[1]
  assert.equal(Rules.acceptSaved(duplicate), false)

  const won = Rules.deal(() => 0.25)
  won.won = true
  assert.equal(Rules.acceptSaved(won), false)

  const removed = Rules.emptyGame()
  const rest = []
  for (let cid = 0; cid < 52; cid++) if (cid !== KS) rest.push(cid)
  removed.removed = [KS]
  removed.stock = rest
  assert.equal(Rules.acceptSaved(removed), true)
})

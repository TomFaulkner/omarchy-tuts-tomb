// Tut's Tomb, the pyramid patience.
//
// Card ids match Quattrolitaire (MIT, Gavin Nugent / 28allday):
//   suit = cid / 13   (0 spades, 1 hearts, 2 diamonds, 3 clubs)
//   rank = cid % 13 + 1   (1 ace … 13 king)
// The King of Spades (cid 12) is dealt face up as the apex.
//
// Rules, as played here:
//   * 28-card pyramid, 7 rows. The other 24 cards are the stock.
//   * A card is free when nothing overlaps it. Overlaps come from the
//     row below: card (row, i) is covered by (row+1, i) and (row+1, i+1).
//   * Remove two free cards whose ranks sum to 13, or a free king alone.
//   * A card covered by exactly one card may be removed with that card
//     when the two sum to 13, and only when nothing outside the pair
//     covers either of them.
//   * Draw three from the stock onto the waste. Only the waste top is
//     playable. An empty stock turns the waste back over, unlimited.
//   * The pyramid alone has to be cleared. Stock and waste may remain.
//
// Scoring is this table's, not a traditional points table:
//   +10 for each pyramid card removed, +5 for each waste card removed,
//   and on a win 100 plus one point for each second under three minutes.

var KING_OF_SPADES = 12
var SCORE_PYRAMID = 10
var SCORE_WASTE = 5
var WIN_FLAT = 100
var WIN_TIME = 180

// Horizontal step as a fraction of card width. A card in the row below is
// dealt onto the two cards above it. The step has to be at least 2/3 of a
// card, or that lower card also spills onto the neighbor beside those two
// and looks like it blocks a card it does not.
var PYRAMID_STEP_X = 0.72

function stepXFor(cw) {
  return Math.max(1, Math.round(cw * PYRAMID_STEP_X))
}

function pyramidX(row, col, cw) {
  var stepX = stepXFor(cw)
  var bottomW = cw + 6 * stepX
  var rowW = cw + row * stepX
  return Math.round((bottomW - rowW) / 2) + col * stepX
}

function rankOf(cid) { return (cid % 13) + 1 }
function suitOf(cid) { return Math.floor(cid / 13) }

function rowStart(row) { return row * (row + 1) / 2 }

function rowOf(index) {
  var row = 0
  while (row < 6 && index >= rowStart(row + 1)) row++
  return row
}

function coverIndexes(index) {
  var row = rowOf(index)
  if (row >= 6) return []
  var pos = index - rowStart(row)
  var next = rowStart(row + 1)
  return [next + pos, next + pos + 1]
}

function emptyGame() {
  var pyramid = []
  var i
  for (i = 0; i < 28; i++) pyramid.push(-1)
  return {
    pyramid: pyramid,
    stock: [],
    waste: [],
    removed: [],
    score: 0,
    moves: 0,
    passes: 0,
    won: false,
    winBonus: 0
  }
}

function deal(random) {
  var rng = random || Math.random
  var deck = []
  var i
  for (i = 0; i < 52; i++) if (i !== KING_OF_SPADES) deck.push(i)
  for (i = deck.length - 1; i > 0; i--) {
    var k = Math.floor(rng() * (i + 1))
    var swap = deck[i]
    deck[i] = deck[k]
    deck[k] = swap
  }

  var pyramid = []
  for (i = 0; i < 28; i++) pyramid.push(-1)
  pyramid[0] = KING_OF_SPADES
  for (i = 1; i < 28; i++) pyramid[i] = deck[i - 1]

  // deck[27] is the next card after the pyramid, so it is the top of the
  // stock. Stock stores the top at the end.
  var rest = deck.slice(27)
  var stock = []
  for (i = rest.length - 1; i >= 0; i--) stock.push(rest[i])

  return {
    pyramid: pyramid,
    stock: stock,
    waste: [],
    removed: [],
    score: 0,
    moves: 0,
    passes: 0,
    won: false,
    winBonus: 0
  }
}

function clone(state) {
  return {
    pyramid: state.pyramid.slice(),
    stock: state.stock.slice(),
    waste: state.waste.slice(),
    removed: state.removed.slice(),
    score: state.score,
    moves: state.moves,
    passes: state.passes,
    won: state.won,
    winBonus: state.winBonus
  }
}

function pyramidIndex(loc) {
  if (typeof loc !== "string" || loc.charAt(0) !== "p") return -1
  var n = parseInt(loc.substring(1), 10)
  if (isNaN(n) || n < 0 || n > 27) return -1
  return n
}

function cardAt(state, loc) {
  if (!state || !loc) return -1
  if (loc === "w") {
    if (!state.waste.length) return -1
    return state.waste[state.waste.length - 1]
  }
  var idx = pyramidIndex(loc)
  if (idx < 0) return -1
  var cid = state.pyramid[idx]
  return typeof cid === "number" ? cid : -1
}

function locOf(state, cid) {
  if (!state || typeof cid !== "number") return ""
  var i
  for (i = 0; i < 28; i++) if (state.pyramid[i] === cid) return "p" + i
  if (state.waste.length && state.waste[state.waste.length - 1] === cid) return "w"
  return ""
}

function livingCovers(state, index) {
  var ids = coverIndexes(index)
  var out = []
  var i
  for (i = 0; i < ids.length; i++) {
    if (state.pyramid[ids[i]] >= 0) out.push(ids[i])
  }
  return out
}

function coverCount(state, index) {
  return livingCovers(state, index).length
}

function clearedCount(state) {
  var n = 0
  var i
  for (i = 0; i < 28; i++) if (state.pyramid[i] < 0) n++
  return n
}

function pyramidClear(state) {
  return clearedCount(state) === 28
}

// A location may be removed as part of a pair with `other`.
// Waste top is always available. An uncovered pyramid card is available
// to anyone. A card with exactly one cover is available only to that cover,
// and only when the cover itself is not blocked by something outside the pair.
function availableFor(state, loc, other) {
  if (loc === "w") return state.waste.length > 0
  var idx = pyramidIndex(loc)
  if (idx < 0 || state.pyramid[idx] < 0) return false
  var covers = livingCovers(state, idx)
  if (covers.length === 0) return true
  if (covers.length !== 1) return false
  if (other !== "p" + covers[0]) return false
  // The covering card has to be free of anything that is not this pair.
  return coverCount(state, covers[0]) === 0
}

function canPair(state, locA, locB) {
  if (!state || state.won) return false
  if (!locA || !locB || locA === locB) return false
  var a = cardAt(state, locA)
  var b = cardAt(state, locB)
  if (a < 0 || b < 0) return false
  if (rankOf(a) + rankOf(b) !== 13) return false
  if (rankOf(a) === 13 || rankOf(b) === 13) return false
  return availableFor(state, locA, locB) && availableFor(state, locB, locA)
}

function canRemoveKing(state, loc) {
  if (!state || state.won) return false
  var cid = cardAt(state, loc)
  if (cid < 0 || rankOf(cid) !== 13) return false
  if (loc === "w") return true
  var idx = pyramidIndex(loc)
  return idx >= 0 && coverCount(state, idx) === 0
}

function partners(state, loc) {
  var out = []
  if (!state || state.won || !loc) return out
  var cid = cardAt(state, loc)
  if (cid < 0 || rankOf(cid) === 13) return out

  var seen = {}
  var cand = []
  var i
  for (i = 0; i < 28; i++) {
    if (state.pyramid[i] < 0) continue
    cand.push("p" + i)
  }
  if (state.waste.length) cand.push("w")

  for (i = 0; i < cand.length; i++) {
    var other = cand[i]
    if (other === loc || seen[other]) continue
    if (canPair(state, loc, other)) {
      seen[other] = true
      out.push(other)
    }
  }
  return out
}

function hasPlay(state, loc) {
  if (canRemoveKing(state, loc)) return true
  return partners(state, loc).length > 0
}

function removalScore(loc) {
  return loc === "w" ? SCORE_WASTE : SCORE_PYRAMID
}

function finishIfWon(state, seconds) {
  if (!pyramidClear(state)) return
  var bonus = WIN_FLAT + Math.max(0, WIN_TIME - (seconds || 0))
  state.won = true
  state.winBonus = bonus
  state.score += bonus
}

function take(state, loc) {
  if (loc === "w") return state.waste.pop()
  var idx = pyramidIndex(loc)
  var cid = state.pyramid[idx]
  state.pyramid[idx] = -1
  return cid
}

function removeKing(state, loc, seconds) {
  if (!canRemoveKing(state, loc)) return null
  var next = clone(state)
  var cid = take(next, loc)
  next.removed.push(cid)
  next.score += removalScore(loc)
  next.moves += 1
  finishIfWon(next, seconds)
  return next
}

function removePair(state, locA, locB, seconds) {
  if (!canPair(state, locA, locB)) return null
  var next = clone(state)
  var cidA = take(next, locA)
  var cidB = take(next, locB)
  next.removed.push(cidA, cidB)
  next.score += removalScore(locA) + removalScore(locB)
  next.moves += 1
  finishIfWon(next, seconds)
  return next
}

function draw(state) {
  if (!state || state.won) return null
  if (state.stock.length === 0) return recycle(state)
  var next = clone(state)
  var n = Math.min(3, next.stock.length)
  var i
  // Pop order is draw order: the old top goes down first, the third card
  // lands on top of the waste and is the one you can play.
  for (i = 0; i < n; i++) next.waste.push(next.stock.pop())
  next.moves += 1
  return next
}

function recycle(state) {
  if (!state || state.won) return null
  if (state.stock.length > 0 || state.waste.length === 0) return null
  var next = clone(state)
  // Flip the waste face down. The old bottom becomes the new top.
  var flipped = []
  var i
  for (i = next.waste.length - 1; i >= 0; i--) flipped.push(next.waste[i])
  next.stock = flipped
  next.waste = []
  next.passes += 1
  next.moves += 1
  return next
}

function findHint(state) {
  if (!state || state.won) return null
  var i
  var covers
  var pair
  // The buried pair is the move that is easiest to miss.
  for (i = 0; i < 28; i++) {
    if (state.pyramid[i] < 0 || coverCount(state, i) !== 1) continue
    covers = livingCovers(state, i)
    if (coverCount(state, covers[0]) !== 0) continue
    if (canPair(state, "p" + i, "p" + covers[0]))
      return { kind: "pair", a: "p" + i, b: "p" + covers[0] }
  }
  for (i = 0; i < 28; i++) {
    if (canRemoveKing(state, "p" + i)) return { kind: "king", a: "p" + i, b: "" }
  }
  if (canRemoveKing(state, "w")) return { kind: "king", a: "w", b: "" }
  for (i = 27; i >= 0; i--) {
    if (state.pyramid[i] < 0 || coverCount(state, i) !== 0) continue
    pair = partners(state, "p" + i)
    if (pair.length) return { kind: "pair", a: "p" + i, b: pair[0] }
  }
  if (state.waste.length) {
    pair = partners(state, "w")
    if (pair.length) return { kind: "pair", a: "w", b: pair[0] }
  }
  if (state.stock.length > 0 || state.waste.length > 0) return { kind: "draw", a: "", b: "" }
  return null
}

function acceptSaved(g) {
  if (!g || typeof g !== "object" || g.won === true) return false
  if (!Array.isArray(g.pyramid) || g.pyramid.length !== 28) return false
  if (!Array.isArray(g.stock) || !Array.isArray(g.waste) || !Array.isArray(g.removed)) return false

  var seen = []
  var i
  for (i = 0; i < 52; i++) seen.push(false)

  function claim(cid) {
    if (typeof cid !== "number" || cid !== Math.floor(cid) || cid < 0 || cid > 51) return false
    if (seen[cid]) return false
    seen[cid] = true
    return true
  }

  for (i = 0; i < 28; i++) {
    if (g.pyramid[i] === -1) continue
    if (!claim(g.pyramid[i])) return false
  }
  for (i = 0; i < g.stock.length; i++) if (!claim(g.stock[i])) return false
  for (i = 0; i < g.waste.length; i++) if (!claim(g.waste[i])) return false
  for (i = 0; i < g.removed.length; i++) if (!claim(g.removed[i])) return false
  for (i = 0; i < 52; i++) if (!seen[i]) return false

  var ksAt = -1
  var ksRemoved = false
  for (i = 0; i < 28; i++) if (g.pyramid[i] === KING_OF_SPADES) ksAt = i
  for (i = 0; i < g.removed.length; i++) if (g.removed[i] === KING_OF_SPADES) ksRemoved = true
  if (ksAt !== -1 && ksAt !== 0) return false
  if (ksAt === -1 && !ksRemoved) return false
  return true
}

function fromSaved(g) {
  return {
    pyramid: g.pyramid.slice(),
    stock: g.stock.slice(),
    waste: g.waste.slice(),
    removed: g.removed.slice(),
    score: Number(g.score) || 0,
    moves: Math.max(0, Number(g.moves) || 0),
    passes: Math.max(0, Number(g.passes) || 0),
    won: false,
    winBonus: 0
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    KING_OF_SPADES: KING_OF_SPADES,
    SCORE_PYRAMID: SCORE_PYRAMID,
    SCORE_WASTE: SCORE_WASTE,
    WIN_FLAT: WIN_FLAT,
    WIN_TIME: WIN_TIME,
    PYRAMID_STEP_X: PYRAMID_STEP_X,
    stepXFor: stepXFor,
    pyramidX: pyramidX,
    rankOf: rankOf,
    suitOf: suitOf,
    rowOf: rowOf,
    coverIndexes: coverIndexes,
    emptyGame: emptyGame,
    deal: deal,
    cardAt: cardAt,
    locOf: locOf,
    coverCount: coverCount,
    clearedCount: clearedCount,
    pyramidClear: pyramidClear,
    canPair: canPair,
    canRemoveKing: canRemoveKing,
    partners: partners,
    hasPlay: hasPlay,
    removeKing: removeKing,
    removePair: removePair,
    draw: draw,
    recycle: recycle,
    findHint: findHint,
    acceptSaved: acceptSaved,
    fromSaved: fromSaved
  }
}

Tut's Tomb for Omarchy
======================

This plugin is a new game built on the Quattrolitaire table.

  Game and panel:     Tom Faulkner
  Deck and card code: Gavin Nugent (28allday)
  Upstream:           https://github.com/28allday/Quattrolitaire
  License:            MIT

The 52 faces, the card back, and the table tile in `cards/` are copied
unchanged from Quattrolitaire. The back started as vulturetone's
`1-quattro.jpg` from Omarchy's tokyo-night theme; the framing is
Quattrolitaire's. See cards/CREDITS.md.

The self-registration snippet in Panel.qml follows the one in
Quattrolitaire: `omarchy plugin enable` does not yet write a `plugins[]`
entry for a panel that is also a bar widget, and that snippet is how the
keybinding keeps working if the bar icon is removed.

Tut's Tomb itself, the pyramid patience, is a public-domain card game.
The King of Spades is dealt as the apex, stock is drawn three at a time,
and pairs that sum to 13 leave the pyramid. The points table in Rules.js
is this program's, not a historical scoring system.

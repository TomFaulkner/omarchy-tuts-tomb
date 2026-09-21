import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Rules.js" as Rules

// Tut's Tomb for omarchy-shell.
//   omarchy-shell shell toggle io.github.tomfaulkner.tuts-tomb
// The host calls open(payloadJson) / close() and reads `opened`. It injects
// `shell` after the Loader resolves.
//
// The deck in cards/ is Quattrolitaire's, used under its MIT license.
// Faces are named by card code. Felt, chrome and highlights come from the
// live theme. Rules live in Rules.js; this file is the table.
//
// keepLoaded is load-bearing. Without it the host destroys this item on
// hide and the game in progress goes with it. State is also written to
// disk, so a restart of the shell can resume the same deal.

Item {
  id: root

  property bool opened: false
  property bool started: false
  property bool stateLoaded: false
  property int stateLoads: 0
  readonly property string selfId: "io.github.tomfaulkner.tuts-tomb"

  property var shell: null
  onShellChanged: {
    if (!root.opened && root.shell && root.shell.openPanelIds
        && root.shell.openPanelIds[root.selfId] === true)
      root.open("{}")
  }

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color accent: Color.accent
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding

  function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
  function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }
  readonly property bool darkSurface: root.lum(root.background) < 0.5
  readonly property color felt: root.mix(root.darkSurface ? Qt.darker(root.background, 1.45)
                                                          : Qt.darker(root.background, 1.10),
                                         root.accent, 0.10)
  readonly property color feltLine: root.mix(root.felt, root.foreground, 0.28)

  // Same self-registration as Quattrolitaire. `omarchy plugin enable` writes
  // the bar layout entry for a panel+bar-widget plugin and not plugins[], so
  // a keybinding dies with the bar icon unless the plugin claims its own
  // entry. The id is an argument, never spliced into the script. The rewrite
  // refuses a symlink and keeps the original mode. Drop this once upstream
  // registers panel plugins itself.
  property bool selfRefEnsured: false
  readonly property string ensureSelfRefScript: [
    'umask 077',
    'id="$1"',
    'f="$HOME/.config/omarchy/shell.json"',
    '[ -f "$f" ] || exit 0',
    '[ -L "$f" ] && exit 0',
    'jq -e --arg id "$id" \'any(.plugins[]?; (.id // empty) == $id)\' "$f" >/dev/null && exit 0',
    'tmp="$f.selfref.$$"',
    'jq --arg id "$id" \'.plugins = ((.plugins // []) + [{id: $id}])\' "$f" > "$tmp" || {',
    '  rm -f "$tmp"; exit 1;',
    '}',
    '[ -s "$tmp" ] || { rm -f "$tmp"; exit 1; }',
    'chmod --reference="$f" "$tmp" 2>/dev/null || chmod 600 "$tmp"',
    'mv "$tmp" "$f"'
  ].join("\n")

  function ensureSelfReference() {
    if (root.selfRefEnsured) return
    root.selfRefEnsured = true
    Quickshell.execDetached(["sh", "-c", root.ensureSelfRefScript, "plugin-selfref", root.selfId])
  }

  property var game: Rules.emptyGame()
  property int seconds: 0
  property var history: []
  property string selected: ""
  property string hintA: ""
  property var stats: ({ played: 0, won: 0, best: 0, bestTime: 0 })
  property int rev: 0

  property int dragCid: -1
  property real dragOriginX: 0
  property real dragOriginY: 0
  property real dragDX: 0
  property real dragDY: 0
  property bool dragMoved: false

  function touch() { root.rev++ }

  function clearDrag() {
    root.dragCid = -1
    root.dragDX = 0
    root.dragDY = 0
    root.dragMoved = false
  }

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: {
    var xdg = Quickshell.env("XDG_STATE_HOME")
    return (xdg && xdg.length) ? xdg : (root.home + "/.local/state")
  }
  readonly property string stateDir: root.stateHome + "/omarchy-tuts-tomb"
  readonly property string statePath: root.stateDir + "/state.json"

  readonly property var rankNames: ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
  readonly property var suitLetters: ["S", "H", "D", "C"]
  readonly property url backImage: Qt.resolvedUrl("cards/back.png")
  readonly property url tableImage: Qt.resolvedUrl("cards/table.png")

  function cardCode(cid) {
    return root.rankNames[Rules.rankOf(cid) - 1] + root.suitLetters[Rules.suitOf(cid)]
  }
  function cardImage(cid) {
    return Qt.resolvedUrl("cards/" + root.cardCode(cid) + ".png")
  }

  function timeText(total) {
    var m = Math.floor(total / 60)
    var s = total % 60
    return m + ":" + (s < 10 ? "0" : "") + s
  }

  function pushHistory() {
    var h = root.history.slice()
    h.push(JSON.stringify(root.game))
    if (h.length > 300) h = h.slice(h.length - 300)
    root.history = h
  }

  function commit(next) {
    if (!next) return
    var wonNow = next.won === true && root.game.won !== true
    root.pushHistory()
    root.game = next
    root.selected = ""
    root.hintA = ""
    root.clearDrag()
    if (wonNow) {
      root.stats = {
        played: root.stats.played,
        won: root.stats.won + 1,
        best: Math.max(root.stats.best, next.score),
        bestTime: (root.stats.bestTime === 0 || root.seconds < root.stats.bestTime)
                  ? root.seconds : root.stats.bestTime
      }
    }
    root.touch()
    root.save()
  }

  function newGame() {
    root.game = Rules.deal()
    root.seconds = 0
    root.history = []
    root.selected = ""
    root.hintA = ""
    root.clearDrag()
    root.started = true
    root.stats = {
      played: root.stats.played + 1,
      won: root.stats.won,
      best: root.stats.best,
      bestTime: root.stats.bestTime
    }
    root.touch()
    root.save()
  }

  function undo() {
    if (root.game.won || root.history.length === 0) return
    var h = root.history.slice()
    var raw = h.pop()
    root.history = h
    root.game = JSON.parse(raw)
    root.selected = ""
    root.hintA = ""
    root.clearDrag()
    root.touch()
    root.save()
  }

  function doDraw() {
    if (root.game.won) return
    root.commit(Rules.draw(root.game))
  }

  function showHint() {
    if (root.game.won) return
    var hint = Rules.findHint(root.game)
    root.hintA = ""
    root.selected = ""
    if (!hint) return
    if (hint.kind === "draw") root.hintA = "draw"
    else root.selected = hint.a
  }

  function clickCid(cid) {
    var loc = Rules.locOf(root.game, cid)
    if (!loc || root.game.won) return
    if (root.selected !== "" && Rules.canPair(root.game, root.selected, loc)) {
      root.commit(Rules.removePair(root.game, root.selected, loc, root.seconds))
      return
    }
    if (Rules.canRemoveKing(root.game, loc)) {
      root.commit(Rules.removeKing(root.game, loc, root.seconds))
      return
    }
    if (root.selected === loc) {
      root.selected = ""
      root.hintA = ""
      return
    }
    root.hintA = ""
    root.selected = Rules.partners(root.game, loc).length > 0 ? loc : ""
  }

  function cardAtPoint(px, py) {
    var cards = root.layout.cards
    var best = -1
    var bestZ = -1
    var i
    for (i = 0; i < 52; i++) {
      if (i === root.dragCid) continue
      var card = cards[i]
      if (!card || card.zone === "none" || card.zone === "stock" || card.zone === "tomb") continue
      if (px >= card.x && px < card.x + root.cardW && py >= card.y && py < card.y + root.cardH && card.z >= bestZ) {
        bestZ = card.z
        best = i
      }
    }
    return best
  }

  function dropAt(cid, px, py) {
    var target = root.cardAtPoint(px, py)
    if (target < 0) return
    var a = Rules.locOf(root.game, cid)
    var b = Rules.locOf(root.game, target)
    if (a !== "" && b !== "" && Rules.canPair(root.game, a, b))
      root.commit(Rules.removePair(root.game, a, b, root.seconds))
  }

  function mark(cid) {
    var loc = Rules.locOf(root.game, cid)
    if (loc === "") return ""
    if (root.selected === loc) return "selected"
    if (root.selected !== "" && Rules.canPair(root.game, root.selected, loc)) return "partner"
    return ""
  }

  function snapshotText() {
    var game = root.game
    var saved = (root.started && game && game.won !== true) ? {
      pyramid: game.pyramid,
      stock: game.stock,
      waste: game.waste,
      removed: game.removed,
      score: game.score,
      moves: game.moves,
      passes: game.passes,
      seconds: root.seconds,
      won: false
    } : null
    return JSON.stringify({ version: 1, stats: root.stats, game: saved }, null, 2) + "\n"
  }

  function writeState() {
    if (!root.stateLoaded) return
    stateFile.setText(root.snapshotText())
  }

  function save() {
    if (!root.stateLoaded) return
    saveTimer.restart()
  }

  function restoreStats(st) {
    if (!st || typeof st !== "object") return
    root.stats = {
      played: Math.max(0, Number(st.played) || 0),
      won: Math.max(0, Number(st.won) || 0),
      best: Math.max(0, Number(st.best) || 0),
      bestTime: Math.max(0, Number(st.bestTime) || 0)
    }
  }

  function applyState(raw) {
    // mkdir reloads the state file once at startup. Ignore that second read
    // once the player has moved, so it cannot roll back an in-progress game.
    if (root.stateLoads > 0 && root.game && root.game.moves > 0) return
    root.stateLoads++
    var st = null
    try { st = JSON.parse(String(raw || "").trim()) } catch (e) { st = null }
    if (st && typeof st === "object") root.restoreStats(st.stats)

    if (st && st.game && Rules.acceptSaved(st.game)) {
      root.game = Rules.fromSaved(st.game)
      root.seconds = Math.max(0, Number(st.game.seconds) || 0)
      root.history = []
      root.selected = ""
      root.hintA = ""
      root.started = true
      root.stateLoaded = true
      root.clearDrag()
      root.touch()
      return
    }

    if (!root.stateLoaded) {
      root.stateLoaded = true
      root.newGame()
      return
    }
    root.stateLoaded = true
  }

  Timer {
    id: saveTimer
    interval: 200
    repeat: false
    onTriggered: root.writeState()
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.opened && root.started && root.game && root.game.won !== true
    onTriggered: root.seconds++
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: function(err) { root.applyState("") }
  }

  Process {
    id: mkStateDir
    command: ["mkdir", "-p", root.stateDir]
    onExited: stateFile.reload()
  }

  Component.onCompleted: mkStateDir.running = true

  function open(payloadJson) {
    root.opened = true
    root.ensureSelfReference()
    if (root.stateLoaded && root.game && root.game.won === true) root.newGame()
    else if (root.stateLoaded && !root.started) root.newGame()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    if (!root.opened) return
    root.opened = false
    root.clearDrag()
    root.selected = ""
    root.hintA = ""
    if (root.game && root.game.won === true) root.newGame()
    root.writeState()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.selfId)
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  readonly property real tableW: table.width
  readonly property real tableH: table.height
  readonly property int cardW: {
    var byWidth = root.tableW / (1 + 6 * Rules.PYRAMID_STEP_X)
    var byHeight = root.tableH / (1.4 * 4.3)
    var side = Math.min(byWidth, byHeight)
    if (!(side > 0)) side = 36
    return Math.max(36, Math.min(168, Math.floor(side)))
  }
  readonly property int cardH: Math.round(root.cardW * 1.4)
  readonly property var layout: root.computeLayout(root.rev, root.game, root.cardW, root.cardH,
                                                   root.tableW, root.tableH)

  function computeLayout(rev, game, cw, ch, tw, th) {
    var cards = []
    var i
    for (i = 0; i < 52; i++)
      cards.push({ x: 0, y: 0, z: 0, up: false, zone: "none", index: -1 })
    var empty = { cards: cards, stockX: 0, wasteX: 0, wasteTopX: 0, tombX: 0, bandY: 0 }
    if (!game || !game.pyramid || game.pyramid.length !== 28 || tw < 10 || th < 10) return empty

    var gap = Math.max(8, Math.round(cw * 0.16))
    var stepX = Rules.stepXFor(cw)
    var fan = Math.round(cw * 0.28)
    var bottomW = cw + 6 * stepX
    var originX = Math.max(0, Math.round((tw - bottomW) / 2))
    var preferred = Math.round(ch * 0.30)
    var minStep = Math.round(ch * 0.24)
    var room = th - ch - gap
    var fitted = Math.floor((room - ch) / 6)
    var stepY = preferred
    if (fitted > 0) stepY = Math.min(preferred, Math.max(minStep, fitted))
    if (fitted > 0 && fitted < minStep) stepY = Math.max(4, fitted)

    var bandY = 6 * stepY + ch + gap
    if (bandY + ch > th) bandY = Math.max(0, th - ch)

    var row = 0
    var col = 0
    var count = 1
    for (i = 0; i < 28; i++) {
      var cid = game.pyramid[i]
      if (cid >= 0 && cid < 52) {
        cards[cid] = {
          x: originX + Rules.pyramidX(row, col, cw),
          y: row * stepY,
          z: 20 + row * 10 + col,
          up: true,
          zone: "pyramid",
          index: i
        }
      }
      col++
      if (col >= count) { row++; count++; col = 0 }
    }

    var stockX = originX
    for (i = 0; i < game.stock.length; i++) {
      var stockCid = game.stock[i]
      if (stockCid < 0 || stockCid > 51) continue
      cards[stockCid] = { x: stockX, y: bandY, z: 200 + i, up: false, zone: "stock", index: i }
    }

    var wasteX = stockX + cw + gap
    var wasteN = game.waste.length
    for (i = 0; i < wasteN; i++) {
      var wasteCid = game.waste[i]
      if (wasteCid < 0 || wasteCid > 51) continue
      var slot = Math.min(Math.max(0, i - (wasteN - 3)), 2)
      cards[wasteCid] = {
        x: wasteX + slot * fan, y: bandY, z: 300 + i,
        up: true, zone: "waste", index: i
      }
    }

    var tombX = originX + bottomW - cw
    var removedN = game.removed.length
    for (i = 0; i < removedN; i++) {
      var gone = game.removed[i]
      if (gone < 0 || gone > 51) continue
      var shift = Math.min(i, 8)
      cards[gone] = {
        x: tombX + shift, y: bandY - shift, z: 400 + i,
        up: true, zone: "tomb", index: i
      }
    }

    return {
      cards: cards,
      stockX: stockX,
      wasteX: wasteX,
      wasteTopX: wasteX + 2 * fan,
      tombX: tombX,
      bandY: bandY
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-tuts-tomb"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: surface
      width: Math.min(Style.space(1120), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(920), panel.height - Style.bar.sizeHorizontal - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin
      clip: true

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) root.close()
          else if (event.key === Qt.Key_N) root.newGame()
          else if (event.key === Qt.Key_U || event.key === Qt.Key_Backspace || event.key === Qt.Key_Z) root.undo()
          else if (event.key === Qt.Key_H) root.showHint()
          else if (event.key === Qt.Key_Space || event.key === Qt.Key_D) root.doDraw()
          else return
          keyCatcher.forceActiveFocus()
          event.accepted = true
        }
      }

      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: surface.contentTopInset
        anchors.leftMargin: surface.contentLeftInset
        anchors.rightMargin: surface.contentRightInset
        height: Math.max(titleCol.implicitHeight, controls.implicitHeight)

        Column {
          id: titleCol
          anchors.left: parent.left
          anchors.right: controls.left
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0

          Text {
            text: "Tut's Tomb"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            width: titleCol.width
            text: "The king of spades is Tut"
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Row {
          id: controls
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm

          Button {
            text: "New"
            bordered: true
            fontFamily: root.fontFamily
            tooltipText: "Deal a new game  (n)"
            onClicked: { root.newGame(); keyCatcher.forceActiveFocus() }
          }
          Button {
            text: "Undo"
            bordered: true
            fontFamily: root.fontFamily
            tooltipText: "Take back the last move  (u)"
            enabled: root.history.length > 0 && root.game.won !== true
            opacity: enabled ? 1 : 0.4
            onClicked: { root.undo(); keyCatcher.forceActiveFocus() }
          }
          Button {
            text: "Hint"
            bordered: true
            fontFamily: root.fontFamily
            tooltipText: "Show one legal move  (h)"
            enabled: root.game.won !== true
            opacity: enabled ? 1 : 0.4
            onClicked: { root.showHint(); keyCatcher.forceActiveFocus() }
          }
        }
      }

      Item {
        id: statusRow
        anchors.top: header.bottom
        anchors.left: header.left
        anchors.right: header.right
        anchors.topMargin: Style.spacing.xs
        height: scoreText.implicitHeight + ruleText.implicitHeight + Style.spacing.xs

        Text {
          id: scoreText
          anchors.left: parent.left
          anchors.right: creditText.left
          anchors.rightMargin: Style.spacing.sm
          text: "Cleared " + Rules.clearedCount(root.game) + "/28"
                + "   ·   Score " + root.game.score
                + "   ·   Moves " + root.game.moves
                + "   ·   " + root.timeText(root.seconds)
                + (root.game.passes > 0 ? "   ·   Redeals " + root.game.passes : "")
                + (root.stats.played > 0 ? "   ·   Won " + root.stats.won + "/" + root.stats.played : "")
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          id: creditText
          anchors.right: parent.right
          text: "Deck from Quattrolitaire"
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          id: ruleText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: scoreText.bottom
          text: "Pair cards that sum to 13. Kings go alone. A card may match the single card covering it. Space draws three."
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelSeparator {
        id: sep
        anchors.top: statusRow.bottom
        anchors.left: header.left
        anchors.right: header.right
        anchors.topMargin: Style.spacing.sm
      }

      Rectangle {
        id: feltSurface
        anchors.top: sep.bottom
        anchors.left: header.left
        anchors.right: header.right
        anchors.bottom: parent.bottom
        anchors.topMargin: Style.spacing.md
        anchors.bottomMargin: surface.contentBottomInset
        radius: Math.max(2, root.cornerRadius)
        color: root.felt
        clip: true

        Image {
          id: tableTile
          readonly property int tileSize: Math.max(160, Math.round(feltSurface.width * 0.34))
          anchors.fill: parent
          source: root.tableImage
          fillMode: Image.Tile
          sourceSize.width: tableTile.tileSize
          sourceSize.height: tableTile.tileSize
          smooth: true
          cache: true
          opacity: 0.55
        }

        Item {
          id: table
          anchors.fill: parent
          anchors.margins: Math.max(Style.spacing.sm, Math.round(feltSurface.width * 0.012))

          MouseArea {
            anchors.fill: parent
            onClicked: { root.selected = ""; root.hintA = "" }
          }

          Repeater {
            model: 3
            delegate: Item {
              readonly property int slot: index
              readonly property var lay: root.layout
              width: root.cardW
              height: root.cardH
              x: slot === 0 ? lay.stockX : slot === 1 ? lay.wasteTopX : lay.tombX
              y: lay.bandY
              z: 1

              Rectangle {
                anchors.fill: parent
                radius: Math.max(2, root.cardW * 0.09)
                color: "transparent"
                border.width: slot === 0 && root.hintA === "draw" ? 2 : 1
                border.color: slot === 0 && root.hintA === "draw" ? root.accent : root.feltLine
                opacity: slot === 0 && root.hintA === "draw" ? 1 : 0.7
              }

              Text {
                anchors.centerIn: parent
                visible: slot === 0 && root.game.stock.length === 0 && root.game.waste.length > 0
                text: "↻"
                color: root.feltLine
                font.family: root.fontFamily
                font.pixelSize: Math.max(12, root.cardH * 0.28)
              }

              MouseArea {
                anchors.fill: parent
                enabled: slot === 0 && root.game.won !== true
                onClicked: { root.doDraw(); keyCatcher.forceActiveFocus() }
              }
            }
          }

          Repeater {
            model: 52
            delegate: Item {
              id: cardItem
              readonly property int cid: index
              readonly property var info: root.layout.cards[cid]
              readonly property bool held: root.dragCid === cid
              readonly property string mark: root.mark(cid)

              visible: info && info.zone !== "none"
              width: root.cardW
              height: root.cardH
              x: held ? root.dragOriginX + root.dragDX : (info ? info.x : 0)
              y: held ? root.dragOriginY + root.dragDY : (info ? info.y : 0)
              z: held ? 900 : (info ? info.z : 0)

              Behavior on x {
                enabled: !cardItem.held
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
              }
              Behavior on y {
                enabled: !cardItem.held
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
              }

              Rectangle {
                anchors.fill: parent
                anchors.margins: -Math.max(2, Math.round(root.cardW * 0.025))
                radius: Math.max(3, root.cardW * 0.1)
                color: "transparent"
                border.width: cardItem.mark === "" ? 0 : Math.max(2, Math.round(root.cardW * 0.03))
                border.color: cardItem.mark === "partner" ? root.mix(root.accent, root.foreground, 0.25) : root.accent
                opacity: cardItem.mark === "" ? 0 : 1
              }

              Image {
                anchors.fill: parent
                source: cardItem.info && cardItem.info.up ? root.cardImage(cardItem.cid) : root.backImage
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.max(64, Math.round(root.cardW * 2))
                smooth: true
                mipmap: true
                asynchronous: true
                cache: true
                scale: cardItem.held ? 1.04 : 1
                Behavior on scale { NumberAnimation { duration: 90 } }
              }

              MouseArea {
                id: grab
                anchors.fill: parent
                enabled: root.game.won !== true
                acceptedButtons: Qt.LeftButton
                cursorShape: {
                  if (!cardItem.info) return Qt.ArrowCursor
                  if (cardItem.info.zone === "stock") return Qt.PointingHandCursor
                  var loc = Rules.locOf(root.game, cardItem.cid)
                  if (loc !== "" && Rules.hasPlay(root.game, loc)) return Qt.PointingHandCursor
                  return Qt.ArrowCursor
                }
                property point pressAt: Qt.point(0, 0)
                property bool armed: false

                onPressed: function(mouse) {
                  grab.armed = false
                  if (!cardItem.info || root.game.won === true) return
                  if (cardItem.info.zone === "stock" || cardItem.info.zone === "tomb") return
                  if (cardItem.info.zone !== "pyramid" && cardItem.info.zone !== "waste") return
                  grab.armed = true
                  grab.pressAt = grab.mapToItem(table, mouse.x, mouse.y)
                  var loc = Rules.locOf(root.game, cardItem.cid)
                  if (loc !== "" && Rules.hasPlay(root.game, loc)) {
                    root.dragCid = cardItem.cid
                    root.dragOriginX = cardItem.info.x
                    root.dragOriginY = cardItem.info.y
                    root.dragDX = 0
                    root.dragDY = 0
                    root.dragMoved = false
                  }
                }

                onPositionChanged: function(mouse) {
                  if (!grab.armed || root.dragCid !== cardItem.cid) return
                  var p = grab.mapToItem(table, mouse.x, mouse.y)
                  root.dragDX = p.x - grab.pressAt.x
                  root.dragDY = p.y - grab.pressAt.y
                  if (!root.dragMoved && Math.abs(root.dragDX) + Math.abs(root.dragDY) > 5)
                    root.dragMoved = true
                }

                onReleased: function(mouse) {
                  if (cardItem.info && cardItem.info.zone === "stock") {
                    grab.armed = false
                    root.clearDrag()
                    if (root.game.won !== true) root.doDraw()
                    return
                  }
                  if (!grab.armed) return
                  var moved = root.dragMoved && root.dragCid === cardItem.cid
                  var p = grab.mapToItem(table, mouse.x, mouse.y)
                  var cid = cardItem.cid
                  grab.armed = false
                  if (moved) root.dropAt(cid, p.x, p.y)
                  else root.clickCid(cid)
                  root.clearDrag()
                }

                onCanceled: {
                  grab.armed = false
                  root.clearDrag()
                }
              }
            }
          }

          Rectangle {
            visible: root.game.won === true
            anchors.fill: parent
            z: 1000
            color: Qt.rgba(0, 0, 0, root.darkSurface ? 0.55 : 0.35)

            MouseArea { anchors.fill: parent; onClicked: {} }

            Item {
              anchors.centerIn: parent
              width: Math.max(winTitle.implicitWidth, winScore.implicitWidth, winButton.implicitWidth)
              height: winTitle.implicitHeight + winScore.implicitHeight + winButton.implicitHeight + Style.spacing.sm * 2

              Text {
                id: winTitle
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                text: "The tomb is clear"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                id: winScore
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: winTitle.bottom
                anchors.topMargin: Style.spacing.sm
                text: "Score " + root.game.score
                      + "  ·  " + root.timeText(root.seconds)
                      + (root.game.winBonus > 0 ? "  ·  includes " + root.game.winBonus + " time bonus" : "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Button {
                id: winButton
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: winScore.bottom
                anchors.topMargin: Style.spacing.sm
                text: "New game"
                bordered: true
                fontFamily: root.fontFamily
                tooltipText: "Deal again  (n)"
                onClicked: { root.newGame(); keyCatcher.forceActiveFocus() }
              }
            }
          }
        }
      }
    }
  }
}

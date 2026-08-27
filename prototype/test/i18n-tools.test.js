// Tests for the hub tooling: PO parsing, string extraction, catalog building.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("fs")
const os = require("os")
const path = require("path")
const po = require("../tools/lib/po.js")
const extract = require("../tools/omarchy-i18n-extract")
const build = require("../tools/omarchy-i18n-build")

// ---------------------------------------------------------------------------
test("po: round-trips header, context, plurals, flags, references", () => {
  const src = `msgid ""
msgstr ""
"Content-Type: text/plain; charset=UTF-8\\n"
"Plural-Forms: nplurals=2; plural=(n != 1);\\n"
"X-Omarchy-Source: quattro@abc123\\n"

#: shell/plugins/menu/Menu.qml:12
#, qt-format
msgid "Removing %1"
msgstr "Suprimint %1"

#: shell/plugins/menu/Menu.qml:40 shell/plugins/menu/Menu.qml:41
msgctxt "verb"
msgid "Open"
msgstr "Obre"

#, fuzzy
msgid "Stale"
msgstr "Antic"

msgid "%1 city"
msgid_plural "%1 cities"
msgstr[0] "%1 ciutat"
msgstr[1] "%1 ciutats"

msgid ""
"multi "
"line"
msgstr ""
"multi "
"línia"

#~ msgid "Gone"
#~ msgstr "Desaparegut"
`
  const cat = po.parse(src)
  assert.equal(cat.header["Plural-Forms"], "nplurals=2; plural=(n != 1);")
  assert.equal(cat.header["X-Omarchy-Source"], "quattro@abc123")
  assert.equal(cat.entries.length, 5)
  const [rem, open, stale, city, multi] = cat.entries
  assert.deepEqual(rem.flags, ["qt-format"])
  assert.deepEqual(rem.references, ["shell/plugins/menu/Menu.qml:12"])
  assert.equal(open.msgctxt, "verb")
  assert.equal(po.key(open), "verb\u0004Open")
  assert.deepEqual(open.references.length, 2)
  assert.deepEqual(stale.flags, ["fuzzy"])
  assert.equal(city.msgid_plural, "%1 cities")
  assert.deepEqual(city.msgstr, ["%1 ciutat", "%1 ciutats"])
  assert.equal(multi.msgid, "multi line")
  assert.equal(multi.msgstr[0], "multi línia")

  const again = po.parse(po.serialize(cat))
  assert.deepEqual(again.entries.map(po.key), cat.entries.map(po.key))
  assert.deepEqual(again.entries[3].msgstr, ["%1 ciutat", "%1 ciutats"])
  assert.equal(again.header["Plural-Forms"], cat.header["Plural-Forms"])
})

test("po: escapes survive a round trip", () => {
  const e = po.newEntry()
  e.msgid = 'say "hi"\\now'
  e.msgstr = ["digues \"hola\"\\ara"]
  const back = po.parse(po.serialize({ header: {}, entries: [e] }))
  assert.equal(back.entries[0].msgid, e.msgid)
  assert.equal(back.entries[0].msgstr[0], e.msgstr[0])
})

// ---------------------------------------------------------------------------
test("extract: QML/JS scanner finds tr, trc, ntr, noop on any receiver", () => {
  const src = `
    Text { text: I18n.tr("Connect") }
    Text { text: _.tr('Single quoted') }
    Text { text: _.trc("verb", "Open") }
    Text { text: _.ntr(count, "%1 city", "%1 cities", [count]) }
    property string s: root.t.noop("Connection failed")
    // not ours:
    var x = qsTr("Qt string")
    el.attr("class")
    obj.tr(variable)
    text: _.tr("with \\"escape\\"")
  `
  const found = extract.scanQmlJs(src)
  assert.deepEqual(found.map(f => [f.msgctxt, f.msgid, f.msgid_plural]), [
    [null, "Connect", null],
    [null, "Single quoted", null],
    ["verb", "Open", null],
    [null, "%1 city", "%1 cities"],
    [null, "Connection failed", null],
    [null, 'with "escape"', null],
  ])
  assert.equal(found[0].line, 2)
})

test("extract: a one-word string followed by another call on the same line", () => {
  // The count slot is for omarchy_tn <n> "one" "many"; it must not swallow a
  // quoted one-word msgid as the count. This exact shape lost "Remove".
  const bash = `printf '%s' "$(omarchy_t "Move up")" "$(omarchy_t "Remove")" "$(omarchy_t "Back")"`
  assert.deepEqual(extract.scanBash(bash).map(f => f.msgid), ["Move up", "Remove", "Back"])
  // and omarchy_tn still takes its count
  assert.deepEqual(extract.scanBash(`omarchy_tn "$n" "%1 file" "%1 files"`).map(f => [f.msgid, f.msgid_plural]), [["%1 file", "%1 files"]])
  assert.deepEqual(extract.scanBash(`omarchy_tn 3 "%1 item" "%1 items"`).map(f => f.msgid), ["%1 item"])
})

test("extract: bash scanner finds omarchy_t and omarchy_tn", () => {
  const src = `
    echo "$(omarchy_t "Update now?")"
    gum confirm "$(omarchy_t 'Really?')"
    msg="$(omarchy_t "Removing %1" "$pkg")"
    omarchy_tn "$n" "%1 package" "%1 packages" "$n"
    omarchy_translate "not us"
  `
  const found = extract.scanBash(src)
  assert.deepEqual(found.map(f => [f.msgid, f.msgid_plural]), [
    ["Update now?", null],
    ["Really?", null],
    ["Removing %1", null],
    ["%1 package", "%1 packages"],
  ])
})

test("extract: menu jsonc yields labels, titles, descriptions with entry-id references", () => {
  const src = `{
    // comment
    "apps": {"icon":"x","label":"Apps","aliases":["app"]},   /* block */
    "system.lock": {"label":"Lock","title":"Lock the session","action":"omarchy-system-lock"},
    "empty": {"label":""},
  }`
  const found = extract.scanMenuData(src, ["label", "title", "description"])
  assert.deepEqual(found.map(f => [f.msgid, f.line]), [
    ["Apps", "apps.label"],
    ["Lock", "system.lock.label"],
    ["Lock the session", "system.lock.title"],
  ])
})

test("extract: full-line comments are not scanned, trailing ones are", () => {
  const qml = `
    // Text { text: _.tr("In a comment") }
    Text { text: _.tr("Real") } // _.tr("Trailing comment is scanned")
    property string u: _.tr("https://x.y/not-a-comment")
  `
  assert.deepEqual(extract.scanQmlJs(qml).map(f => f.msgid),
    ["Real", "Trailing comment is scanned", "https://x.y/not-a-comment"])
  assert.equal(extract.scanQmlJs(qml)[0].line, 3)
  const bash = `
    #   omarchy_t "Example in header"
    omarchy_t "Actual"
  `
  assert.deepEqual(extract.scanBash(bash).map(f => f.msgid), ["Actual"])
  assert.equal(extract.declaredDomain(`// I18n.domain("in.comment")\nfoo`), null)
})

test("extract: stripJsonc leaves // inside strings alone", () => {
  assert.deepEqual(JSON.parse(extract.stripJsonc(`{"url": "https://x.y", // c\n "a": 1,}`)), { url: "https://x.y", a: 1 })
})

test("extract: domain from path, via the nearest manifest for plugins", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "omarchy-"))
  fs.mkdirSync(path.join(root, "shell/plugins/panels/weather"), { recursive: true })
  fs.writeFileSync(path.join(root, "shell/plugins/panels/weather/manifest.json"), JSON.stringify({ id: "omarchy.weather" }))
  fs.mkdirSync(path.join(root, "shell/plugins/menu"), { recursive: true })
  fs.writeFileSync(path.join(root, "shell/plugins/menu/manifest.json"), JSON.stringify({ id: "omarchy.menu" }))
  assert.equal(extract.domainForFile(root, "shell/plugins/panels/weather/Panel.qml"), "omarchy.weather")
  assert.equal(extract.domainForFile(root, "shell/plugins/menu/Menu.qml"), "omarchy.menu")
  assert.equal(extract.domainForFile(root, "shell/plugins/menu/MenuModel.js"), "omarchy.menu")
  assert.equal(extract.domainForFile(root, "shell/Ui/ConfirmDialog.qml"), "omarchy.shell")
  assert.equal(extract.domainForFile(root, "shell/shell.qml"), "omarchy.shell")
  assert.equal(extract.domainForFile(root, "bin/omarchy-update"), "omarchy.cli")
  assert.equal(extract.domainForFile(root, "default/bash/i18n"), "omarchy.cli")
  assert.equal(extract.domainForFile(root, "default/omarchy/omarchy-menu.jsonc"), "omarchy.menu")
  assert.equal(extract.domainForFile(root, "themes/x.conf"), null)
  fs.rmSync(root, { recursive: true })
})

test("extract: declared literal binding is detected", () => {
  assert.equal(extract.declaredDomain(`readonly property var _: I18n.domain("dev.foo.weather")`), "dev.foo.weather")
  assert.equal(extract.declaredDomain(`readonly property var _: I18n.domain(root.manifest.id)`), null)
})

// ---------------------------------------------------------------------------
test("build: compiles PO to the runtime JSON shape and skips fuzzy/untranslated", () => {
  const cat = po.parse(`msgid ""
msgstr ""
"Plural-Forms: nplurals=2; plural=(n != 1);\\n"
"X-Omarchy-Source: quattro@abc123\\n"

msgid "Connect"
msgstr "Connecta"

msgctxt "verb"
msgid "Open"
msgstr "Obre"

msgid "%1 city"
msgid_plural "%1 cities"
msgstr[0] "%1 ciutat"
msgstr[1] "%1 ciutats"

#, fuzzy
msgid "Stale"
msgstr "Antic"

msgid "Untranslated"
msgstr ""

msgid "%1 thing"
msgid_plural "%1 things"
msgstr[0] ""
msgstr[1] ""
`)
  const { json, total, translated } = build.compile(cat, "ca")
  assert.deepEqual(json, {
    "": { language: "ca", "plural-forms": "nplurals=2; plural=(n != 1);", source: "quattro@abc123" },
    "Connect": "Connecta",
    "verb\u0004Open": "Obre",
    "%1 city": ["%1 ciutat", "%1 ciutats"],
  })
  assert.equal(total, 6)
  assert.equal(translated, 3)
})

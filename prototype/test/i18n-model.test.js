// Run with: npm test
const test = require("node:test")
const assert = require("node:assert/strict")
const M = require("../shell/Commons/I18nModel.js")

// ---------------------------------------------------------------------------
test("normalizeLocale", () => {
  assert.equal(M.normalizeLocale("ca_ES.UTF-8"), "ca_ES")
  assert.equal(M.normalizeLocale("ca-es"), "ca_ES")
  assert.equal(M.normalizeLocale("es_MX.UTF-8@euro"), "es_MX")
  assert.equal(M.normalizeLocale("C"), "")
  assert.equal(M.normalizeLocale("POSIX"), "")
  assert.equal(M.normalizeLocale(""), "")
  assert.equal(M.normalizeLocale(undefined), "")
  assert.equal(M.normalizeLocale("de"), "de")
})

test("localeCandidates: LANG only expands regional then language", () => {
  assert.deepEqual(M.localeCandidates({ LANG: "ca_ES.UTF-8" }), ["ca_ES", "ca"])
})

test("localeCandidates: precedence LANGUAGE > LC_ALL > LC_MESSAGES > LANG", () => {
  assert.deepEqual(M.localeCandidates({ LANG: "de_DE", LC_MESSAGES: "fr_FR" }), ["fr_FR", "fr"])
  assert.deepEqual(M.localeCandidates({ LANG: "de_DE", LC_ALL: "es" }), ["es"])
  assert.deepEqual(M.localeCandidates({ LANG: "de_DE", LANGUAGE: "ca:es" }), ["ca", "es"])
})

test("localeCandidates: stops at English so nothing lower applies", () => {
  assert.deepEqual(M.localeCandidates({ LANGUAGE: "fr:en:es" }), ["fr", "en"])
  assert.deepEqual(M.localeCandidates({ LANG: "en_US.UTF-8" }), ["en_US", "en"])
})

test("localeCandidates: empty and C locales yield nothing", () => {
  assert.deepEqual(M.localeCandidates({}), [])
  assert.deepEqual(M.localeCandidates({ LANG: "C" }), [])
})

// ---------------------------------------------------------------------------
test("interpolate: basic and out-of-range", () => {
  assert.equal(M.interpolate("%1 of %2", ["3", 7]), "3 of 7")
  assert.equal(M.interpolate("%1 and %3", ["a"]), "a and %3")
  assert.equal(M.interpolate("no placeholders", ["x"]), "no placeholders")
  assert.equal(M.interpolate(null, []), "")
})

test("interpolate: %10 is not %1 followed by 0", () => {
  const args = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
  assert.equal(M.interpolate("%10 %1", args), "j a")
})

test("interpolate: an argument containing a placeholder is inserted verbatim", () => {
  assert.equal(M.interpolate("%1 in %2 min", ["say %2", 5]), "say %2 in 5 min")
})

test("contextKey joins with U+0004", () => {
  assert.equal(M.contextKey("verb", "Open"), "verb\u0004Open")
  assert.equal(M.contextKey("", "Open"), "Open")
  assert.equal(M.contextKey(undefined, "Open"), "Open")
})

// ---------------------------------------------------------------------------
const RULES = {
  en: "nplurals=2; plural=(n != 1);",
  fr: "nplurals=2; plural=(n > 1);",
  pl: "nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);",
  ru: "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);",
  ar: "nplurals=6; plural=(n==0 ? 0 : n==1 ? 1 : n==2 ? 2 : n%100>=3 && n%100<=10 ? 3 : n%100>=11 ? 4 : 5);",
  ja: "nplurals=1; plural=0;",
}

test("parsePluralForms: English and French", () => {
  const en = M.parsePluralForms(RULES.en)
  assert.equal(en.nplurals, 2)
  assert.deepEqual([0, 1, 2, 5].map(en.plural), [1, 0, 1, 1])
  const fr = M.parsePluralForms(RULES.fr)
  assert.deepEqual([0, 1, 2].map(fr.plural), [0, 0, 1])
})

test("parsePluralForms: Polish, Russian, Arabic, Japanese", () => {
  const pl = M.parsePluralForms(RULES.pl)
  assert.deepEqual([1, 2, 5, 12, 22, 25, 102].map(pl.plural), [0, 1, 2, 2, 1, 2, 1])
  const ru = M.parsePluralForms(RULES.ru)
  assert.deepEqual([1, 21, 11, 2, 22, 5, 12].map(ru.plural), [0, 0, 2, 1, 1, 2, 2])
  const ar = M.parsePluralForms(RULES.ar)
  assert.deepEqual([0, 1, 2, 3, 10, 11, 99, 100, 103].map(ar.plural), [0, 1, 2, 3, 3, 4, 4, 5, 3])
  const ja = M.parsePluralForms(RULES.ja)
  assert.equal(ja.nplurals, 1)
  assert.deepEqual([0, 1, 7].map(ja.plural), [0, 0, 0])
})

test("parsePluralForms: index is clamped to nplurals and negatives are absolute", () => {
  const bad = M.parsePluralForms("nplurals=2; plural=(n);")
  assert.equal(bad.plural(7), 1)
  assert.equal(bad.plural(-1), 1)
  assert.equal(bad.plural(-0), 0)
})

test("parsePluralForms: rejects garbage rather than evaluating it", () => {
  assert.equal(M.parsePluralForms("nplurals=2; plural=(process.exit(1));"), null)
  assert.equal(M.parsePluralForms("nplurals=2; plural=(n ? );"), null)
  assert.equal(M.parsePluralForms("plural=(n != 1);"), null)
  assert.equal(M.parsePluralForms(""), null)
  assert.equal(M.parsePluralForms(undefined), null)
  assert.equal(M.parsePluralForms("nplurals=0; plural=0;"), null)
})

test("parsePluralForms: integer division and unary not", () => {
  const r = M.parsePluralForms("nplurals=3; plural=(!(n%2) ? 0 : n/3);")
  assert.deepEqual([2, 3, 7].map(r.plural), [0, 1, 2])
})

// ---------------------------------------------------------------------------
test("sanitizeCatalog drops bad entries but keeps the rest", () => {
  const out = M.sanitizeCatalog({
    "": { language: "ca" },
    "Connect": "Connecta",
    "%1 city": ["%1 ciutat", "%1 ciutats"],
    "bad number": 42,
    "bad array": ["ok", 3],
    "empty array": [],
    "bad object": { x: 1 },
  })
  assert.deepEqual(out, {
    "": { language: "ca" },
    "Connect": "Connecta",
    "%1 city": ["%1 ciutat", "%1 ciutats"],
  })
  assert.equal(M.sanitizeCatalog(null), null)
  assert.equal(M.sanitizeCatalog([1, 2]), null)
  assert.equal(M.sanitizeCatalog("str"), null)
})

// ---------------------------------------------------------------------------
function catalan() {
  const reg = M.createRegistry()
  reg.setCatalogs("lang.ca", {
    "omarchy.shell": { "": { "plural-forms": RULES.en }, "Cancel": "Cancel·la", "Open": "Obre" },
    "omarchy.menu":  { "": { "plural-forms": RULES.en }, "Connect": "Connecta", "Open": "Obre",
                       "%1 city": ["%1 ciutat", "%1 ciutats"], "verb\u0004Play": "Reprodueix" },
    "dev.foo.weather": { "": { "plural-forms": RULES.en }, "Open": "Obert", "Sunny": "Assolellat" },
  })
  return reg
}

test("registry: English fallback with nothing registered", () => {
  const reg = M.createRegistry()
  assert.equal(reg.translate("Connect"), "Connect")
  assert.equal(reg.translate("Connect", { domain: "omarchy.menu" }), "Connect")
  assert.equal(reg.translatePlural(1, "%1 city", "%1 cities", { args: [1] }), "1 city")
  assert.equal(reg.translatePlural(3, "%1 city", "%1 cities", { args: [3] }), "3 cities")
  assert.equal(reg.translate(undefined), "")
})

test("registry: bound lookup resolves in its own domain", () => {
  const reg = catalan()
  assert.equal(reg.translate("Connect", { domain: "omarchy.menu" }), "Connecta")
  assert.equal(reg.translate("Sunny", { domain: "dev.foo.weather" }), "Assolellat")
})

test("registry: two bound plugins translate the same English word differently", () => {
  const reg = catalan()
  assert.equal(reg.translate("Open", { domain: "omarchy.menu" }), "Obre")
  assert.equal(reg.translate("Open", { domain: "dev.foo.weather" }), "Obert")
})

test("registry: bound caller falls through to the global merge for a key its domain lacks", () => {
  const reg = catalan()
  assert.equal(reg.translate("Cancel", { domain: "dev.foo.weather" }), "Cancel·la")
})

test("registry: unbound caller gets the global merge, later domain wins on collision", () => {
  const reg = catalan()
  assert.equal(reg.translate("Connect"), "Connecta")
  // registration order: shell, menu, weather → weather's "Open" registered last
  assert.equal(reg.translate("Open"), "Obert")
})

test("registry: context disambiguation", () => {
  const reg = catalan()
  assert.equal(reg.translate("Play", { domain: "omarchy.menu", context: "verb" }), "Reprodueix")
  assert.equal(reg.translate("Play", { domain: "omarchy.menu" }), "Play")
})

test("registry: plurals use the rule from the domain the key was found in", () => {
  const reg = catalan()
  const o = { domain: "omarchy.menu" }
  assert.equal(reg.translatePlural(1, "%1 city", "%1 cities", { ...o, args: [1] }), "1 ciutat")
  assert.equal(reg.translatePlural(4, "%1 city", "%1 cities", { ...o, args: [4] }), "4 ciutats")
  assert.equal(reg.translatePlural(0, "%1 city", "%1 cities", { ...o, args: [0] }), "0 ciutats")
})

test("registry: a Polish catalog picks the third form", () => {
  const reg = M.createRegistry()
  reg.setCatalogs("lang.pl", {
    "omarchy.menu": { "": { "plural-forms": RULES.pl },
      "%1 file": ["%1 plik", "%1 pliki", "%1 plików"] },
  })
  const o = { domain: "omarchy.menu" }
  assert.equal(reg.translatePlural(1, "%1 file", "%1 files", { ...o, args: [1] }), "1 plik")
  assert.equal(reg.translatePlural(3, "%1 file", "%1 files", { ...o, args: [3] }), "3 pliki")
  assert.equal(reg.translatePlural(5, "%1 file", "%1 files", { ...o, args: [5] }), "5 plików")
  assert.equal(reg.translatePlural(22, "%1 file", "%1 files", { ...o, args: [22] }), "22 pliki")
})

test("registry: a translated plural with too few forms uses the last one", () => {
  const reg = M.createRegistry()
  reg.setCatalogs("x", { "d": { "": { "plural-forms": RULES.ar }, "%1 item": ["a", "b"] } })
  assert.equal(reg.translatePlural(100, "%1 item", "%1 items", { domain: "d" }), "b")
})

test("registry: a tr() hit on a plural entry returns the singular form", () => {
  const reg = catalan()
  assert.equal(reg.translate("%1 city", { domain: "omarchy.menu", args: [1] }), "1 ciutat")
})

// ---------------------------------------------------------------------------
// A pack registers everything it has in one call: re-registering an owner
// replaces its previous set, so the clone's catalog must ship alongside the rest.
function withClone() {
  const reg = M.createRegistry()
  reg.setCatalogs("lang.ca", {
    "omarchy.shell": { "Cancel": "Cancel·la" },
    "omarchy.menu":  { "Connect": "Connecta", "Open": "Obre", "Refresh": "Actualitza" },
    "dev.foo.weather": { "Open": "Obert" },
    "my.menu":       { "Open": "Obre-ho", "Frobnicate": "Frobnica" },
  }, { links: { "my.menu": "omarchy.menu" } })
  return reg
}

test("clone chain: adds a string and translates it in its own catalog", () => {
  assert.equal(withClone().translate("Frobnicate", { domain: "my.menu" }), "Frobnica")
})

test("clone chain: inherits an upstream string unchanged", () => {
  assert.equal(withClone().translate("Refresh", { domain: "my.menu" }), "Actualitza")
})

test("clone chain: overrides one upstream translation", () => {
  const reg = withClone()
  assert.equal(reg.translate("Open", { domain: "my.menu" }), "Obre-ho")
  assert.equal(reg.translate("Open", { domain: "omarchy.menu" }), "Obre")
})

test("clone chain: unbound caller sees the clone's override (parents fold first)", () => {
  assert.equal(withClone().translate("Open"), "Obre-ho")
  assert.deepEqual(withClone().chain("my.menu"), ["my.menu", "omarchy.menu"])
})

test("clone chain: self-links and cycles are ignored", () => {
  const reg = M.createRegistry()
  reg.setCatalogs("o", { a: { k: "A" }, b: { k: "B" } }, { links: { a: "b", b: "a", c: "c" } })
  assert.deepEqual(reg.chain("a"), ["a", "b"])
  assert.equal(reg.translate("k", { domain: "a" }), "A")
  assert.equal(reg.translate("k", { domain: "b" }), "B")
})

// ---------------------------------------------------------------------------
test("owners: setCatalogs replaces an owner atomically", () => {
  const reg = M.createRegistry()
  assert.equal(reg.setCatalogs("p", { d: { a: "1", b: "2" } }), "added")
  assert.equal(reg.setCatalogs("p", { d: { a: "9" } }), "replaced")
  assert.equal(reg.translate("a", { domain: "d" }), "9")
  assert.equal(reg.translate("b", { domain: "d" }), "b")
})

test("owners: clearOwner removes its catalogs and links", () => {
  const reg = withClone()
  assert.equal(reg.clearOwner("lang.ca"), true)
  assert.equal(reg.clearOwner("lang.ca"), false)
  assert.equal(reg.translate("Connect", { domain: "omarchy.menu" }), "Connect")
  assert.deepEqual(reg.chain("my.menu"), ["my.menu"])
  assert.deepEqual(reg.domains(), [])
})

test("owners: lower precedence number wins across owners", () => {
  const reg = M.createRegistry()
  reg.setCatalogs("lang.es", { d: { Hello: "Hola" } }, { precedence: 1 })
  reg.setCatalogs("lang.ca", { d: { Hello: "Hola!" } }, { precedence: 0 })
  assert.equal(reg.translate("Hello", { domain: "d" }), "Hola!")
  reg.clearOwner("lang.ca")
  assert.equal(reg.translate("Hello", { domain: "d" }), "Hola")
})

test("owners: equal precedence, later registration wins", () => {
  const reg = M.createRegistry()
  reg.setCatalogs("a", { d: { k: "first" } })
  reg.setCatalogs("b", { d: { k: "second" } })
  assert.equal(reg.translate("k", { domain: "d" }), "second")
})

test("revision increments on every change", () => {
  const reg = M.createRegistry()
  const r0 = reg.revision()
  reg.setCatalogs("a", { d: { k: "v" } })
  const r1 = reg.revision()
  reg.clearOwner("a")
  const r2 = reg.revision()
  assert.ok(r1 > r0 && r2 > r1)
})

test("malformed catalogs are ignored without losing good ones", () => {
  const reg = M.createRegistry()
  reg.setCatalogs("p", { good: { k: "v" }, bad: "not an object", worse: [1, 2] })
  assert.deepEqual(reg.domains(), ["good"])
  assert.equal(reg.translate("k", { domain: "good" }), "v")
})

// ---------------------------------------------------------------------------
test("snapshot round-trips catalogs and links through the cache owner", () => {
  const snap = withClone().snapshot()
  assert.equal(snap.version, 1)
  const json = JSON.parse(JSON.stringify(snap))

  const fresh = M.createRegistry()
  assert.equal(fresh.loadSnapshot(json), true)
  assert.equal(fresh.translate("Frobnicate", { domain: "my.menu" }), "Frobnica")
  assert.equal(fresh.translate("Refresh", { domain: "my.menu" }), "Actualitza")
  assert.equal(fresh.translate("Cancel", { domain: "omarchy.shell" }), "Cancel·la")
  assert.deepEqual(fresh.owners(), ["cache"])
})

test("snapshot: a live pack overrides the cache as soon as it registers", () => {
  const fresh = M.createRegistry()
  fresh.loadSnapshot(withClone().snapshot())
  fresh.setCatalogs("lang.ca", { "omarchy.menu": { Connect: "Connecta (nova)" } })
  assert.equal(fresh.translate("Connect", { domain: "omarchy.menu" }), "Connecta (nova)")
  fresh.clearOwner("cache")
  assert.equal(fresh.translate("Refresh", { domain: "omarchy.menu" }), "Refresh")
})

test("snapshot: rejects unknown versions", () => {
  const reg = M.createRegistry()
  assert.equal(reg.loadSnapshot({ version: 2 }), false)
  assert.equal(reg.loadSnapshot(null), false)
  assert.deepEqual(reg.owners(), [])
})

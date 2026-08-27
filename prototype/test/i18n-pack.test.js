// Run with: npm test
//
// The language pack reads its catalogs with a Bash script that lives as a
// string inside Service.qml. Nothing else in the suite executes it: the model
// tests import JS, the tools tests run node, and the Bash tests source
// default/bash/i18n. That gap already cost one silent bug — a stray `shift`
// dropped the first domain of every registration, so the pack shipped three
// catalogs and registered two — which is why these tests pull the real string
// out of the QML rather than restating it here. A copy would have stayed green
// through that bug.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

const SERVICE_QML = path.join(__dirname, "..", "omarchy-lang-ca", "Service.qml")

// Lift `readonly property string loaderScript: [ ... ].join("\n")` out of the
// QML and evaluate the array literal, which is plain JS.
function loaderScript() {
  const src = fs.readFileSync(SERVICE_QML, "utf8")
  const decl = src.indexOf("readonly property string loaderScript:")
  assert.notEqual(decl, -1, "loaderScript declaration not found in Service.qml")
  const open = src.indexOf("[", decl)
  const close = src.indexOf('].join("\\n")', open)
  assert.notEqual(close, -1, "loaderScript is no longer an array joined with newlines")
  return Function("return " + src.slice(open, close + 1))().join("\n")
}

function hasJq() {
  try {
    execFileSync("jq", ["--version"], { stdio: "ignore" })
    return true
  } catch {
    return false
  }
}

// Run the loader the way Service.qml does: the catalog directory as $0, the
// wanted domains as the remaining arguments.
function runLoaderRaw(dir, domains) {
  return execFileSync("bash", ["-c", loaderScript(), dir, ...domains], { encoding: "utf8" })
}

function runLoader(dir, domains) {
  return JSON.parse(runLoaderRaw(dir, domains))
}

function fixture(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "omarchy-i18n-pack-"))
  for (const [name, body] of Object.entries(files)) {
    fs.writeFileSync(path.join(dir, name), typeof body === "string" ? body : JSON.stringify(body))
  }
  return dir
}

const catalog = (msgid, msgstr) => ({ "": { language: "ca" }, [msgid]: msgstr })
const skip = hasJq() ? false : "jq is not installed"

// ---------------------------------------------------------------------------

test("loader: returns every requested domain, including the first", { skip }, () => {
  const dir = fixture({
    "omarchy.shell.json": catalog("Cancel", "Cancel·la"),
    "omarchy.cli.json": catalog("Ready to update?", "Esteu a punt per a actualitzar?"),
    "omarchy.menu.json": catalog("Apps", "Aplicacions"),
  })
  // wantedDomains() puts omarchy.shell first, so a loader that drops the head
  // of the list loses it on every single registration and nothing else.
  const got = runLoader(dir, ["omarchy.shell", "omarchy.cli", "omarchy.menu"])
  assert.deepEqual(Object.keys(got).sort(), ["omarchy.cli", "omarchy.menu", "omarchy.shell"])
  assert.equal(got["omarchy.shell"]["Cancel"], "Cancel·la")
})

test("loader: the first domain survives whatever order it is asked for", { skip }, () => {
  const dir = fixture({
    "a.json": catalog("One", "Un"),
    "b.json": catalog("Two", "Dos"),
  })
  assert.deepEqual(Object.keys(runLoader(dir, ["a", "b"])).sort(), ["a", "b"])
  assert.deepEqual(Object.keys(runLoader(dir, ["b", "a"])).sort(), ["a", "b"])
  assert.deepEqual(Object.keys(runLoader(dir, ["a"])), ["a"])
})

test("loader: a domain with no catalog is skipped, not fatal", { skip }, () => {
  const dir = fixture({ "omarchy.menu.json": catalog("Apps", "Aplicacions") })
  // The pack asks for every enabled plugin; most ship no catalog at all.
  const got = runLoader(dir, ["omarchy.shell", "dev.someone.widget", "omarchy.menu"])
  assert.deepEqual(Object.keys(got), ["omarchy.menu"])
})

test("loader: an unreadable catalog is skipped, and the rest still load", { skip }, () => {
  const dir = fixture({
    "broken.json": "{ this is not json",
    "omarchy.menu.json": catalog("Apps", "Aplicacions"),
  })
  const got = runLoader(dir, ["broken", "omarchy.menu"])
  assert.deepEqual(Object.keys(got), ["omarchy.menu"])
})

test("loader: no domains gives an empty object", { skip }, () => {
  const dir = fixture({ "omarchy.menu.json": catalog("Apps", "Aplicacions") })
  assert.deepEqual(runLoader(dir, []), {})
})

test("loader: an unreachable directory emits nothing, and the caller absorbs it", { skip }, () => {
  const dir = fixture({ "omarchy.menu.json": catalog("Apps", "Aplicacions") })
  // `cd "$0" || exit 0` bails before the opening brace, so the output is empty
  // rather than valid JSON. That is only safe because Service.qml parses
  // `loaderOut.text || "{}"` — assert the guard is still there, since losing it
  // would turn a bad catalogDir into a parse error on every registration.
  assert.equal(runLoaderRaw(path.join(dir, "nope"), ["omarchy.menu"]).trim(), "")
  const service = fs.readFileSync(SERVICE_QML, "utf8")
  assert.match(service, /JSON\.parse\(loaderOut\.text \|\| "\{\}"\)/)
})

test("loader: catalog bodies survive intact, including non-ASCII", { skip }, () => {
  const body = { "": { language: "ca" }, "Uninstall": "Desinstal·la", "Go": "Vés" }
  const dir = fixture({ "omarchy.menu.json": body })
  assert.deepEqual(runLoader(dir, ["omarchy.menu"])["omarchy.menu"], body)
})

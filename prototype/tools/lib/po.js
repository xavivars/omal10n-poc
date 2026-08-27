// Minimal gettext PO reader/writer. Enough for what omarchy-i18n needs:
// header, msgctxt, msgid, msgid_plural, msgstr[n], flags, extracted comments,
// references, and obsolete entries (read and dropped). No dependencies.

"use strict"

function unescapePo(s) {
  return s.replace(/\\(n|t|r|"|\\)/g, function(_, c) {
    return { n: "\n", t: "\t", r: "\r", '"': '"', "\\": "\\" }[c]
  })
}

function escapePo(s) {
  return String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\t/g, "\\t")
}

function quote(s) {
  // Long or multi-line strings: empty first line, then one quoted line per row.
  const text = String(s)
  if (text.indexOf("\n") === -1 || text.indexOf("\n") === text.length - 1) return '"' + escapePo(text) + '"'
  const rows = text.split(/(?<=\n)/)
  return '""\n' + rows.map(r => '"' + escapePo(r) + '"').join("\n")
}

function newEntry() {
  return { msgctxt: null, msgid: "", msgid_plural: null, msgstr: [], flags: [], extracted: [], references: [], translator: [], obsolete: false }
}

function parseHeader(text) {
  const out = {}
  for (const line of String(text).split("\n")) {
    const i = line.indexOf(":")
    if (i > 0) out[line.slice(0, i).trim()] = line.slice(i + 1).trim()
  }
  return out
}

function serializeHeader(h) {
  return Object.keys(h).map(k => k + ": " + h[k] + "\n").join("")
}

// Returns { header: {...}, entries: [...] }. The header entry (msgid "") is
// parsed into an object and not included in entries.
function parse(text) {
  const lines = String(text).replace(/\r\n/g, "\n").split("\n")
  const entries = []
  let cur = newEntry()
  let target = null   // which string field continuation lines append to
  let targetIndex = 0

  function flush() {
    if (cur.msgid !== "" || cur.msgctxt !== null || cur.msgstr.length) entries.push(cur)
    cur = newEntry()
    target = null
  }

  for (let raw of lines) {
    let line = raw.trim()
    if (line === "") { flush(); continue }

    if (line.startsWith("#~")) { cur.obsolete = true; line = line.slice(2).trim() }
    if (line.startsWith("#")) {
      if (line.startsWith("#,")) cur.flags.push(...line.slice(2).split(",").map(s => s.trim()).filter(Boolean))
      else if (line.startsWith("#.")) cur.extracted.push(line.slice(2).trim())
      else if (line.startsWith("#:")) cur.references.push(...line.slice(2).trim().split(/\s+/).filter(Boolean))
      else if (line.startsWith("#|")) { /* previous msgid: ignore */ }
      else cur.translator.push(line.slice(1).trim())
      continue
    }

    let m
    if ((m = line.match(/^msgctxt\s+(".*")$/))) { cur.msgctxt = unescapePo(m[1].slice(1, -1)); target = "msgctxt"; continue }
    if ((m = line.match(/^msgid\s+(".*")$/))) { cur.msgid = unescapePo(m[1].slice(1, -1)); target = "msgid"; continue }
    if ((m = line.match(/^msgid_plural\s+(".*")$/))) { cur.msgid_plural = unescapePo(m[1].slice(1, -1)); target = "msgid_plural"; continue }
    if ((m = line.match(/^msgstr\[(\d+)\]\s+(".*")$/))) { targetIndex = Number(m[1]); cur.msgstr[targetIndex] = unescapePo(m[2].slice(1, -1)); target = "msgstr[]"; continue }
    if ((m = line.match(/^msgstr\s+(".*")$/))) { cur.msgstr = [unescapePo(m[1].slice(1, -1))]; targetIndex = 0; target = "msgstr[]"; continue }
    if ((m = line.match(/^(".*")$/)) && target) {
      const piece = unescapePo(m[1].slice(1, -1))
      if (target === "msgstr[]") cur.msgstr[targetIndex] = (cur.msgstr[targetIndex] || "") + piece
      else cur[target] = (cur[target] || "") + piece
      continue
    }
    throw new Error("po: cannot parse line: " + raw)
  }
  flush()

  let header = {}
  const rest = []
  for (const e of entries) {
    if (e.msgid === "" && e.msgctxt === null && !e.obsolete) header = parseHeader(e.msgstr[0] || "")
    else if (!e.obsolete) rest.push(e)
  }
  return { header, entries: rest }
}

function serializeEntry(e) {
  const out = []
  for (const c of e.translator) out.push("# " + c)
  for (const c of e.extracted) out.push("#. " + c)
  if (e.references.length) {
    // wrap references at ~76 columns like xgettext does
    let line = "#:"
    for (const r of e.references) {
      if (line.length + 1 + r.length > 76 && line !== "#:") { out.push(line); line = "#:" }
      line += " " + r
    }
    out.push(line)
  }
  if (e.flags.length) out.push("#, " + e.flags.join(", "))
  if (e.msgctxt !== null && e.msgctxt !== undefined) out.push("msgctxt " + quote(e.msgctxt))
  out.push("msgid " + quote(e.msgid))
  if (e.msgid_plural !== null && e.msgid_plural !== undefined) {
    out.push("msgid_plural " + quote(e.msgid_plural))
    const n = Math.max(2, e.msgstr.length)
    for (let i = 0; i < n; i++) out.push("msgstr[" + i + "] " + quote(e.msgstr[i] || ""))
  } else {
    out.push("msgstr " + quote(e.msgstr[0] || ""))
  }
  return out.join("\n")
}

function serialize(catalog) {
  const headerEntry = newEntry()
  headerEntry.msgstr = [serializeHeader(catalog.header || {})]
  headerEntry.flags = ["fuzzy"].filter(() => catalog.headerFuzzy)
  const parts = [serializeEntry(headerEntry)]
  for (const e of catalog.entries) parts.push(serializeEntry(e))
  return parts.join("\n\n") + "\n"
}

function key(e) {
  return (e.msgctxt ? e.msgctxt + "\u0004" : "") + e.msgid
}

module.exports = { parse, serialize, key, newEntry, escapePo, unescapePo }

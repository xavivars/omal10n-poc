# Prototype

Everything the architecture doc describes, built end to end against
`basecamp/omarchy@quattro`. This directory is "step 0" of the sequence: by the time
a PR opens upstream, the whole chain has been seen running.

```
prototype/
├── shell/Commons/          the primitive — drops into a dev-linked checkout
│   ├── I18n.qml              qs.Commons.I18n singleton (env, cache file, reactivity)
│   ├── I18nModel.js          Qt-free core: locale rules, plurals, the catalog registry
│   └── qmldir                upstream's file plus the one line exporting I18n
├── default/bash/i18n       omarchy_t / omarchy_tn for bin/ scripts
├── patches/                the same, as a git patch series against quattro
│   ├── 0001  Add the I18n translation primitive          ← PR #1
│   ├── 0002  Localize omarchy.menu and the confirm dialog ← PR #2, first slice
│   ├── 0003  Localize omarchy-update-confirm              ← PR #2, Bash slice
│   ├── 0004  Clock names from the interface locale        ← closes #6360
│   ├── 0005  Translatable default clock format            ← first login-visible string
│   └── 0006  Drop the startup cache once a pack registers ← fold into 0001 upstream
├── tools/                  what the omarchy-i18n hub would run in CI
│   ├── omarchy-i18n-extract  checkout → one POT per domain
│   ├── omarchy-i18n-build    PO → the JSON catalogs a language pack ships
│   └── lib/po.js             minimal gettext PO reader/writer
├── i18n/                   what the omarchy-i18n hub would hold
│   ├── pot/                  extracted from the patched checkout
│   └── po/ca/                Catalan, created with msginit and filled in
├── omarchy-lang-ca/        the language pack — an ordinary Omarchy plugin
│   ├── manifest.json         id lang.ca, kind service
│   ├── Service.qml           reads the registry, registers matching catalogs
│   └── catalogs/             built from i18n/po/ca by omarchy-i18n-build
└── test/                   npm test — model, tools, pack loader, Bash helper
```

## The chain, as it ran here

```
omarchy-i18n-extract <checkout> i18n/pot          # 245 strings in 4 domains
msginit -l ca_ES.UTF-8 -i pot/X.pot -o po/ca/X.po  # real gettext
…translate…                                        # msgfmt --check passes
omarchy-i18n-build po/ca omarchy-lang-ca/catalogs  # JSON the shell reads
```

Only the last artifact reaches a user machine. `msgmerge` against a fresh POT is how
the catalogs follow upstream as it moves.

## Running it on an Omarchy machine

This has now been run on a real Omarchy session — see *What the first run
settled*, below. The setup steps below are what produced it; `demo.sh` does the work.

```sh
prototype/demo.sh setup      # clone quattro → git am patches → install pack → omarchy dev link
# reboot — dev link only takes effect for a fresh session
prototype/demo.sh enable     # omarchy plugin enable lang.ca && omarchy restart shell
prototype/demo.sh status     # what the session sees: path, plugin, cache, bash helper, log
```

The session locale is read from `LANG` / `LC_MESSAGES` / `LC_ALL` / `LANGUAGE` as the
shell process inherits them — `omarchy restart shell` spawns via Hyprland precisely so
it gets the session environment, not a terminal's. A session already running with a
Catalan `LANG` needs nothing else.

While iterating:

| | |
|---|---|
| Restart the shell after editing QML | `omarchy restart shell` |
| Shell log | `journalctl --user -t omarchy-shell -f` |
| Is the pack seen and enabled | `omarchy-shell shell listPlugins \| jq '.[] \| select(.id=="lang.ca")'` |
| What the pack registered | `~/.cache/omarchy/i18n/ca.json` — `jq '.catalogs \| keys'` |
| Force the pack to re-register | `omarchy plugin disable lang.ca && omarchy plugin enable lang.ca` |
| Copy edits back out of the checkout | `prototype/demo.sh sync` |
| Undo everything | `prototype/demo.sh teardown`, then reboot |

**What to look for, in order** — ✅ = confirmed on a real session

| Check | Proves | |
|---|---|---|
| Menu opens with Catalan entries | pack → registry → `I18n` → bound `_.tr()` | ✅ |
| Root prompt reads «Vés…», and Install › Development still lists «Go» | `msgctxt` separation | ✅ |
| Uninstall dialog reads «Cancel·la» / «Desinstal·la» | unbound `I18n.tr()` in `omarchy.shell` | ✅ |
| `~/.cache/omarchy/i18n/ca.json` exists after first login | cache write | ✅ |
| `omarchy-update-confirm` prompts in Catalan on a tty | Bash helper reading the cache | ✅ |
| Second login shows no flash of English | synchronous cache load before first frame | ✅ |
| `omarchy plugin disable lang.ca` → English, next login stays English | owned registration, cache not self-feeding | ▶ retest after 0006 |

The uninstall dialog has no menu entry: open the **apps** menu (`SUPER + ALT + SPACE`),
filter, press `↓` so `cursorActive` is set, then `Delete`. `requestDeleteSelected()`
requires an `app`-kind row and returns silently otherwise. The clipboard dialog
(`SUPER + CTRL + V`, then `SHIFT + DELETE`) exercises the same `cancelText` default
against an unpatched plugin, so every other string on it stays English.

**Cold-boot result.** No flash of English, and the supporting evidence is stronger than
the observation: after the reboot the cache file's mtime still predated boot, so the
catalogs on screen came from a synchronous read of a file that already existed at
startup rather than from the pack re-registering. The pack did re-register, with
identical content, so nothing was rewritten. That is the sequence `blockLoading: true`
is meant to produce.

Not yet run: the negative control — delete the cache, cold boot, and confirm a flash
*does* appear. Without it, "no flash" is consistent with the pack simply being fast,
and `blockLoading` would be unproven complexity rather than a demonstrated need.

**The no-flash-of-English check is now runnable — patches 0004/0005 are what made it
so.** It could not be run before them: nothing the bar rendered at login went through
a catalog. Workspaces are numbers, Tray/SystemUpdate/Microphone/Indicators
are icon glyphs, ActiveWindow shows the window's own title, and the clock is
`Qt.formatDateTime` output. Every `I18n` call site in the tree lives in `Menu.qml` or
`ConfirmDialog.qml`, both of which are on-demand overlays. So `blockLoading: true` —
the synchronous cache load, one of the primitive's two real complexity costs — is
currently protecting nothing observable, and cannot be validated until some
login-visible string is catalog-backed. Worth saying plainly upstream rather than
shipping unexercised complexity.

That gap is what patches 0004 and 0005 close, and they are deliberately separate:

- **0004 — the #6360 fix.** `Panel.qml` pinned `Qt.locale("en_US")` and explained why:
  *"The interface is English throughout, so day names are not taken from the system
  locale."* A sound decision while the shell could only be English; the primitive
  removes its premise, so the patch satisfies the condition the comment set rather
  than overriding a judgement call. Separately, `BarWidget.qml` used
  `Qt.formatDateTime()`, which resolves `dddd`/`MMMM` against the C locale whatever
  the session is — that was the "Thursday" in a `ca_ES` bar. Neither path reads a
  catalog, so **locale-correct dates work with no language pack installed at all**:
  #6360 is fixed by PR #1 landing, independent of any community translation existing.
- **0005 — the translatable default format.** Field order and 12- vs 24-hour are
  locale conventions, so the *default* format is looked up in `omarchy.clock`. Catalan
  ships `dddd h:mm ap` against a source of `dddd HH:mm`. This is the first
  catalog-backed string the shell renders with no user interaction, which is precisely
  what makes `blockLoading` observable: a 24-hour first frame that flips to 12-hour
  means the cache loaded too late.

Confirmed rendering on a real session: `dijous 2:50 a. m.`

**A limit worth stating upstream before a maintainer finds it.** Only the *default* is
translated — a format the user pinned in `shell.json` is their explicit choice and
passes through untouched. But the clock entry is materialized into `shell.json` with a
format already in it, so on an existing install the translated default is never
reached. The machine this ran on had to have the pin removed for 0005 to show at all.
Translating defaults has limited reach when defaults get written into user config.

**A real bug, found by disabling the pack: the startup cache outlived it.**
`omarchy plugin disable lang.ca` left the interface Catalan until the next shell
restart. The evidence looked self-contradictory at first — the Bash helper reverted to
English immediately while the shell did not — and the split is the explanation. They
read different things that share a name: the helper reads the cache *file*, which was
rewritten empty and correctly so; the shell was reading the in-memory cache *owner*,
which was still full.

`loadSnapshot()` registers the startup cache as an ordinary owner at the lowest
precedence, so it can answer lookups before the packs load. Nothing dropped it once
they had. `clearOwner()` removed the pack, and the cache owner sat there holding a
byte-identical copy of the same strings, still answering. Patch 0006 drops it the
moment any live owner registers — the point where its job ends — and makes
`loadSnapshot()` refuse to seed it back afterwards, since writing the cache
re-triggers the `FileView` that loads it and would otherwise reintroduce a pack's own
strings as an owner that outlives the pack.

Two things worth knowing about this fix:

- **It reverses a decision the tests recorded as deliberate** — *"the cache is still
  serving this session until restart, by design"*. That contradicted the acceptance
  check above, which expects disabling a pack to revert the interface, and in practice
  a toggle with no visible effect reads as a broken plugin rather than an intentional
  one. The old assertion was rewritten rather than deleted.
- **0006 should be squashed into 0001 before this goes upstream.** PR #1 is the
  primitive; shipping it with a follow-up fix to itself is a wart a reviewer will
  notice. It is kept separate here because the prototype's job is to record what the
  first run found.

The two copies of the primitive had also drifted: the tests import
`prototype/shell/Commons/`, the session runs the dev-linked checkout, and the
disagreement only showed up because a test failed. `prototype/demo.sh sync` now closes
that loop — it copies the mirrored files one way, checkout to repo, rebuilds the patch
series from the same commits, and runs the tests. One direction on purpose: the
checkout is both where you edit and where the patches are cut, so a two-way sync would
only offer a way to overwrite the wrong one. It refuses to run against a checkout with
uncommitted changes to those files, since those would reach `prototype/` but not the
patches — a third kind of drift.

**`ConfirmDialog.confirmText` has no live call site.** Both users — `Menu.qml:1206`
and `Clipboard.qml:407` — override it (`_.tr("Uninstall")` and a bare `"Delete"`), so
only `cancelText` falls through to the default. `I18n.tr("Confirm")` is unreachable
and «Confirma» never renders. That leaves `omarchy.shell` a two-string domain with one
string dead, which is thin support for the "core `shell/Ui/` needs the primitive"
argument; patch 0002 should localize a second core component before this goes up.

**The pack's catalog loader is now tested.** `loaderScript` is a Bash string embedded
in QML, so nothing in the suite executed it — which is how the `shift` bug shipped
silently. `test/i18n-pack.test.js` lifts the string out of `Service.qml` and runs it
against fixture directories, rather than restating it; a copy would have stayed green
through that bug. Reintroducing the `shift` fails three of the seven.

**The clone test** — ✅ confirmed on a real session

```sh
omarchy plugin clone omarchy.menu     # creates a copy with a new id
```

The clone's `Menu.qml` binds `I18n.domain(manifest.id)`, so it resolves in its own
domain first and falls through to `omarchy.menu` via `clonedFrom`. With no catalog of
its own, it should render identically to the original. Then add
`catalogs/<clone-id>.json` to the pack with one overridden string — that string
changes; everything else keeps upstream's translation.

Both halves held. Worth recording what the run showed, because two of these were not
obvious from the code:

- `omarchy plugin clone` switches the **original to disabled** and the clone to
  enabled. The clone therefore depends on `wantedDomains()` pushing `clonedFrom`
  targets into the domain list *regardless of whether the source plugin is enabled* —
  without that line the clone falls back to bare English, not to the original's
  translation.
- The pack re-registered on the registry change with **no shell restart**:
  `onPluginsChanged` fires and `refresh()` re-runs. Cloning is a live operation.
- Overriding a single `msgctxt` key (`menu prompt\x04Go` → an emoji) moved only the
  root prompt. Everything else in the clone stayed Catalan via fallthrough, and
  Install › Development › `Go` — same msgid, no context — was untouched. That is
  `msgctxt` separation and clone fallthrough interacting correctly in one check.

The override catalog is named for the clone's id, which is machine-specific
(`xavi.menu` on the machine this ran on), so it is a local test artifact rather than
something `omarchy-lang-ca` ships.

## What the first run settled

Setup, enable, and status have been exercised on an Omarchy machine. The patch series
applies cleanly to the pinned base, the dev-linked shell loads the primitive, and the
pack registers `omarchy.shell`, `omarchy.cli`, and `omarchy.menu` into
`~/.cache/omarchy/i18n/ca.json` with no warnings in the shell log.

Settled:

- The `Process`-based catalog loader in `Service.qml` does fire, and `pluginRegistry`
  is injected in time — this was the ordering risk flagged before the first run.
- The cache file is written, and the Bash helper reads it (`omarchy_t "Continue with
  update?"` → «Voleu continuar amb l'actualització?»).

**One bug the first run caught.** `loaderScript` ran `shift` after `cd "$0"`. In
`bash -c script arg0 …` the directory arrives as `$0`, which is not part of `"$@"`, so
the `shift` consumed the first *domain* instead — always `omarchy.shell`, the first
entry `wantedDomains()` returns. The pack shipped three catalogs and registered two,
silently. Fixed by deleting the line. Worth noting how it hid: `loaderScript` is a
Bash string embedded in QML, so neither the node tests nor the Bash tests execute it.

Still open, and needing eyes on a display:

- Everything in *What to look for* above, plus the clone test.
- Whether `void root.revision` inside `_lookup()` is enough for QML to track the
  dependency, or whether `tr()` must read the property in a way the binding engine
  sees. If labels do not repaint when the pack registers, this is where to look.
- Whether `blockLoading: true` on the cache `FileView` runs early enough in singleton
  construction. If the first frame is English even with a cache present, it is not.
- Search matches on translated labels, so typing `apps` in a Catalan menu will not
  find «Aplicacions». Keeping the source label in the searchable text is a one-line
  change in `MenuModel.nameSearchText` if that turns out to matter.

# Prototype

Everything the architecture doc describes, built end to end against
`basecamp/omarchy@quattro` and run on a real Omarchy session.

```
prototype/
├── shell/Commons/          the primitive — drops into a dev-linked checkout
│   ├── I18n.qml              qs.Commons.I18n singleton (env, cache file, reactivity)
│   ├── I18nModel.js          Qt-free core: locale rules, plurals, the catalog registry
│   └── qmldir                upstream's file plus the one line exporting I18n
├── default/bash/i18n       omarchy_t / omarchy_tn for bin/ scripts
├── bin/omarchy-language    the picker's backend: chain expansion, LANG, packs, restart
├── patches/                the same, as a git patch series against quattro
│   ├── 0001  Add the I18n translation primitive          ← PR #1
│   ├── 0002  Localize omarchy.menu and the confirm dialog ← PR #2, first slice
│   ├── 0003  Localize omarchy-update-confirm              ← PR #2, Bash slice
│   ├── 0004  Clock names from the interface locale        ← closes #6360
│   ├── 0005  Translatable default clock format            ← first login-visible string
│   └── 0006  Add a language picker under Setup            ← Setup › Language
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
├── screenshots/            what it looks like on a real session
│   ├── menu-ca.png           the menu, and the «Vés…» root prompt
│   └── clock-ca.png          the bar clock, which is issue #6360
└── test/                   npm test — model, tools, pack loader, Bash helper, picker
```

## The chain

```
omarchy-i18n-extract <checkout> i18n/pot           # 245 strings in 4 domains
msginit -l ca_ES.UTF-8 -i pot/X.pot -o po/ca/X.po  # real gettext
…translate…                                        # msgfmt --check passes
omarchy-i18n-build po/ca omarchy-lang-ca/catalogs  # JSON the shell reads
```

Only the last artifact reaches a user machine. `msgmerge` against a fresh POT is how
the catalogs follow upstream as it moves.

## Running it on an Omarchy machine

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
| Republish the pack after rebuilding catalogs | `prototype/demo.sh pack` |
| Undo everything | `prototype/demo.sh teardown`, then reboot |

The pack is installed the way a real one would be — `omarchy plugin add` from a git
remote — so that `omarchy-language` can update it. The remote is a bare repo at
`~/src/omarchy-lang-ca.git` that `setup` creates and `pack` republishes to, and
`~/.config/omarchy/language-packs` points `ca` at it instead of GitHub.

The primitive exists twice — `prototype/shell/` is what the tests import, the
dev-linked checkout is what actually runs — so `demo.sh sync` copies the mirrored files
one way, checkout to repo, rebuilds the patch series from the same commits, and runs
the tests. One direction on purpose: the checkout is both where you edit and where the
patches are cut from, so a two-way sync would only offer a way to overwrite the wrong
copy. It refuses to run against uncommitted changes in those files, since those would
reach `prototype/` but not the patches.

## Switching language from the menu

`SUPER + SPACE` → Setup → Language → pick one. That is the whole demo.

The submenu lists the languages with a pack, ticks the current one, and has three more
rows. **Other…** opens a picker over every language this machine can generate a locale
for (by endonym — Deutsch, 日本語 — 43 on a stock install), then a second one over
the regions and variants glibc knows for it — *Any region* first, then *Argentina*,
*Spain (valencia)*, *Serbia (latin)* — with the territory names taken from glibc's own
locale sources, so nothing is hand-maintained. **Language order** is the
fallback list as a priority list, the way Ubuntu's Language Support did it: pick an
entry, then *Move to top / up / down / Remove*, add one from the picker, Apply — all from
the keyboard, no file in sight. **Advanced** opens the same chain as a file in a floating
terminal and applies it on save.

A chain written out in full, from the list or the file, is taken *as written*: entries
removed stay removed. Only a single pick is expanded (`ca_ES` → `ca_ES:ca`). Note that
gettext itself still tries `ll_CC@mod`, `ll_CC`, `ll` for each entry it is given, so the
list is what the user chose to say rather than what glibc will do with it. After every
switch the new shell shows a toast, in the new language, saying what was set and that
apps already open keep theirs until the next login — and, when a language has no
translation pack yet, that the interface stays in English for it.

Behind it, `omarchy-language <code>`:

1. resolves the code to a chain: a bare language keeps whatever chain is already in
   force for it — the picker's own file, else `/etc/locale.conf` — so picking «Català»
   on a machine set up as `ca_ES@valencia:ca@valencia:ca_ES:ca` keeps exactly that,
   and a hand-edited chain survives re-picking its language. Otherwise the code is
   expanded the way gettext would (`ca_ES@valencia` → `ca_ES@valencia:ca@valencia:ca_ES:ca`).
   `LANG` follows as the first entry with a generated locale — glibc ignores
   `LANGUAGE` under the C locale, so a chain with no real `LANG` behind it would
   translate the shell and nothing else;
2. generates the locale first, in a floating terminal, if none in the chain exists;
3. writes both to `~/.config/environment.d/omarchy-language.conf` — applied by the
   user manager at next login, and sourced by `omarchy-launch-shell` right now;
4. installs or updates the pack for each language in the chain;
5. restarts the shell. About half a second, end to end;
6. then asks — once, through Omarchy's polkit agent — to write the same `LANG` and
   `LANGUAGE` into `/etc/locale.conf`, so the system default follows the picker. Not
   with `localectl`: `localed` validates each value as a single locale name and refuses
   a chain with a colon in it, which is what every real chain has. The file is rewritten
   in place through `pkexec`, other lines and comments kept. Skipped when the system
   already says the same; declined leaves it alone, changes nothing about the session,
   and says so in a toast.

GNOME does the first five per user (AccountsService, applied by GDM at login) and makes
the sixth an explicit "apply system-wide" button; KDE stops at the fifth. Omarchy is a
one-user desktop, so the system default following the picker is the less surprising
choice here — and `/etc/locale.conf` is also what `preferred_chain` falls back to for a
language never picked, which only makes sense if it is kept current.

Setup › Language › Advanced opens the file in a floating terminal and applies whatever
`LANGUAGE` says when the editor closes — the same steps 1–5, from a hand-written
chain. The first time, the file is seeded from what is in force.

`hyprctl setenv` was the obvious route for the live change and does not work: the
compositor's exec environment is fixed at session start, which is why the shell
sources the file itself. Apps launched after a switch keep the old language until
the next login; the shell switches immediately.

## Verifying it

✅ = confirmed on a real session.

| Check | Proves | |
|---|---|---|
| Menu opens with Catalan entries | pack → registry → `I18n` → bound `_.tr()` | ✅ |
| Root prompt reads «Vés…», and Install › Development still lists «Go» | `msgctxt` separation | ✅ |
| Uninstall dialog reads «Cancel·la» / «Desinstal·la» | unbound `I18n.tr()` in `omarchy.shell` | ✅ |
| Bar clock reads «dijous 2:50 a. m.» | catalog-backed string with no interaction | ✅ |
| `~/.cache/omarchy/i18n/ca.json` exists after first login | cache write | ✅ |
| `omarchy-update-confirm` prompts in Catalan on a tty | Bash helper reading the cache | ✅ |
| Second login shows no flash of English | synchronous cache load before first frame | ✅ |
| The clone test, below | `clonedFrom` fallthrough | ✅ |
| `omarchy plugin disable lang.ca` → English with no restart | owned registration, cache not self-feeding | ▶ |
| Setup › Language › English, then › Català, from the menu | the picker, end to end | ▶ |
| After the next login the choice is still in force | `environment.d` reaches the session | ▶ |

The uninstall dialog has no menu entry: open the **apps** menu (`SUPER + ALT + SPACE`),
filter, press `↓` so `cursorActive` is set, then `Delete`. `requestDeleteSelected()`
requires an `app`-kind row and returns silently otherwise. The clipboard dialog
(`SUPER + CTRL + V`, then `SHIFT + DELETE`) exercises the same `cancelText` default
against an unpatched plugin, so every other string on it stays English — which makes it
the better check of the two.

**The clone test**

```sh
omarchy plugin clone omarchy.menu     # creates a copy with a new id
```

The clone's `Menu.qml` binds `I18n.domain(manifest.id)`, so it resolves in its own
domain first and falls through to `omarchy.menu` via `clonedFrom`. With no catalog of
its own it renders identically to the original. Add `catalogs/<clone-id>.json` to the
pack with one overridden string and only that string changes.

Note that `omarchy plugin clone` **disables the original**. The clone therefore depends
on `wantedDomains()` pushing `clonedFrom` targets into the domain list regardless of
whether the source plugin is enabled — without that, a clone falls back to bare English
rather than to the original's translation. The override catalog is named for the
clone's id, which is machine-specific, so it stays a local test artifact rather than
something `omarchy-lang-ca` ships.

## Known limits

Worth stating upstream rather than being caught by:

- **`ConfirmDialog.confirmText` has no live call site.** Both users — `Menu.qml:1206`
  and `Clipboard.qml:407` — override it, so only `cancelText` falls through to the
  default and `I18n.tr("Confirm")` is unreachable. That leaves `omarchy.shell` a
  two-string domain with one string dead, which is thin support for the "core
  `shell/Ui/` needs the primitive" argument. Patch 0002 should localize a second core
  component before this goes up.
- **A translated default only reaches fresh installs.** 0005 translates the *default*
  clock format; a format the user pinned in `shell.json` is their choice and passes
  through untouched. But the clock entry is materialized into `shell.json` with a
  format already in it, so on an existing install the translated default is never
  reached. Translating defaults has limited reach when defaults get written into user
  config.
- **Search matches on translated labels**, so typing `apps` in a Catalan menu will not
  find «Aplicacions». Keeping the source label in the searchable text is a one-line
  change in `MenuModel.nameSearchText` if that turns out to matter.
- **Apps launched after a switch keep the old language until the next login.** The
  compositor's exec environment is fixed at session start and `hyprctl setenv` does not
  reach it; only the shell re-reads the file. The toast says so. GNOME behaves the same.
- **The polkit-agent readiness signal is a log line.** After the restart the agent plugin
  registers asynchronously; until it does, polkit refuses rather than asks. The picker
  waits for the shell's *"polkit agent registered"* journal line before writing
  `/etc/locale.conf`. Brittle, and worth an IPC upstream.
- **`localectl` cannot write a chain.** `localed` validates each value as one locale name
  and refuses `LANGUAGE=a:b`, so the system file is rewritten through `pkexec` instead.
- **Territory names are English** (*Spain*, not *Espanya*): they come from glibc's locale
  sources. Translating them is its own domain and a few hundred strings.

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
│   └── 0003  Localize omarchy-update-confirm              ← PR #2, Bash slice
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
└── test/                   npm test — model, tools, and Bash helper
```

## The chain, as it ran here

```
omarchy-i18n-extract <checkout> i18n/pot          # 243 strings in 3 domains
msginit -l ca_ES.UTF-8 -i pot/X.pot -o po/ca/X.po  # real gettext
…translate…                                        # msgfmt --check passes
omarchy-i18n-build po/ca omarchy-lang-ca/catalogs  # JSON the shell reads
```

Only the last artifact reaches a user machine. `msgmerge` against a fresh POT is how
the catalogs follow upstream as it moves.

## Running it on an Omarchy machine

Nothing in `prototype/` has been executed on a real session yet — there is no Qt on
the machine this was written on. The QML is written against the `FileView` and
`Quickshell` APIs as read from the Quickshell source and as `shell.qml` itself uses
them. `demo.sh` does the setup; this is what it does and what to do around it.

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
| Undo everything | `prototype/demo.sh teardown`, then reboot |

**What to look for, in order**

| Check | Proves |
|---|---|
| Menu opens with Catalan entries | pack → registry → `I18n` → bound `_.tr()` |
| Root prompt reads «Vés…», and Install › Development still lists «Go» | `msgctxt` separation |
| Uninstall dialog buttons read «Cancel·la» / «Confirma» | unbound `I18n.tr()` in `omarchy.shell` |
| `omarchy-update-confirm` prompts in Catalan on a tty | Bash helper reading the cache |
| `~/.cache/omarchy/i18n/ca.json` exists after first login | cache write |
| Second login shows no flash of English | synchronous cache load before first frame |
| `omarchy plugin disable lang.ca` → English, next login stays English | owned registration, cache not self-feeding |

**The clone test**

```sh
omarchy plugin clone omarchy.menu     # creates a copy with a new id
```

The clone's `Menu.qml` binds `I18n.domain(manifest.id)`, so it resolves in its own
domain first and falls through to `omarchy.menu` via `clonedFrom`. With no catalog of
its own, it should render identically to the original. Then add
`catalogs/<clone-id>.json` to the pack with one overridden string — that string
changes; everything else keeps upstream's translation.

## Things the first run is likely to surface

- Whether `void root.revision` inside `_lookup()` is enough for QML to track the
  dependency, or whether `tr()` must read the property in a way the binding engine
  sees. If labels do not repaint when the pack registers, this is where to look.
- Whether `blockLoading: true` on the cache `FileView` runs early enough in singleton
  construction. If the first frame is English even with a cache present, it is not.
- The `Process`-based catalog loader in `Service.qml` mirrors how `PluginRegistry`
  scans manifests; if it never fires, check that `pluginRegistry` is injected before
  `Component.onCompleted` (the `onPluginRegistryChanged` handler covers the other
  order).
- Search matches on translated labels, so typing `apps` in a Catalan menu will not
  find «Aplicacions». Keeping the source label in the searchable text is a one-line
  change in `MenuModel.nameSearchText` if that turns out to matter.

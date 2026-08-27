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
them. This is the checklist for the first run.

**1. Dev-link a checkout with the patches applied**

```sh
git clone -b quattro https://github.com/basecamp/omarchy ~/src/omarchy
git -C ~/src/omarchy am ~/omal10n-poc/prototype/patches/*.patch
omarchy dev link ~/src/omarchy     # takes effect on reboot
```

**2. Install the language pack, enabled**

```sh
cp -r ~/omal10n-poc/prototype/omarchy-lang-ca ~/.config/omarchy/plugins/
omarchy plugin enable lang.ca      # third-party plugins land disabled
```

**3. Set the locale and log in again**

`LANG=ca_ES.UTF-8` in the session environment (or `LANGUAGE=ca`).

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

**4. The clone test**

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

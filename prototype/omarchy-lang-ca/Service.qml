import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// lang.ca — a language pack. Ships one JSON catalog per translation domain
// under catalogs/ and registers the ones that apply to the plugins currently
// installed and enabled. It never has to be told what to translate: it reads
// the plugin registry, re-runs whenever the registry changes, and hands the
// I18n singleton the clonedFrom links so a cloned plugin resolves its own
// catalog first and falls through to the original's.

Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string locale: manifest && manifest.omarchy && manifest.omarchy.locale
    ? String(manifest.omarchy.locale) : "ca"
  readonly property string ownerId: manifest && manifest.id ? String(manifest.id) : "lang.ca"
  readonly property string catalogDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir).replace(/\/$/, "") + "/catalogs" : ""

  // Where this locale sits in the user's preference order; -1 = not wanted.
  readonly property int precedence: I18n.precedenceFor(locale)

  // Domains to look for, and clone links, derived from the registry.
  function wantedDomains() {
    var domains = ["omarchy.shell", "omarchy.cli"]
    var links = ({})
    var plugins = pluginRegistry && pluginRegistry.installedPlugins ? pluginRegistry.installedPlugins : ({})
    for (var id in plugins) {
      var m = plugins[id]
      if (!m || !pluginRegistry.isEnabled(id)) continue
      if (domains.indexOf(id) === -1) domains.push(id)
      var from = m.omarchy && m.omarchy.clonedFrom ? String(m.omarchy.clonedFrom) : ""
      if (from && from !== id) {
        links[id] = from
        if (domains.indexOf(from) === -1) domains.push(from)
      }
    }
    return { domains: domains, links: links }
  }

  property var pendingLinks: ({})

  function refresh() {
    if (!catalogDir) return
    if (precedence < 0) {
      // The user does not want this language: contribute nothing.
      I18n.clearCatalogs(ownerId)
      return
    }
    var wanted = wantedDomains()
    root.pendingLinks = wanted.links
    // One process reads every catalog that exists into a single JSON object
    // keyed by domain, the same way PluginRegistry scans manifests.
    loader.command = ["bash", "-c", root.loaderScript, root.catalogDir].concat(wanted.domains)
    loader.running = true
  }

  readonly property string loaderScript: [
    // The catalog dir arrives as $0, which is not part of "$@" — the domains
    // are $@ in full, so there is nothing to shift off.
    'cd "$0" || exit 0',
    'printf "{"',
    'sep=""',
    'for d in "$@"; do',
    '  f="$d.json"',
    '  [[ -f $f ]] || continue',
    '  body="$(jq -c . "$f" 2>/dev/null)" || continue',
    '  printf "%s" "$sep"; printf "%s" "\\"$d\\":"; printf "%s" "$body"',
    '  sep=","',
    'done',
    'printf "}"'
  ].join("\n")

  property Process loader: Process {
    stdout: StdioCollector {
      id: loaderOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var catalogs = ({})
      try {
        var parsed = JSON.parse(loaderOut.text || "{}")
        if (parsed && typeof parsed === "object") catalogs = parsed
      } catch (error) {
        console.warn(root.ownerId + ": could not read catalogs: " + error)
      }
      I18n.setCatalogs(root.ownerId, catalogs, { links: root.pendingLinks, precedence: root.precedence })
    }
  }

  // The registry is injected after creation and rescans on every plugin
  // change; both are reasons to recompute what applies.
  onPluginRegistryChanged: refresh()
  Connections {
    target: root.pluginRegistry
    function onPluginsChanged() { root.refresh() }
  }

  Component.onCompleted: refresh()
  Component.onDestruction: I18n.clearCatalogs(ownerId)
}

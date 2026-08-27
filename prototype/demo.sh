#!/bin/bash
# Set up, inspect, or remove the localization prototype on an Omarchy machine.
#
#   prototype/demo.sh setup      clone quattro, apply the patches, dev-link, install the pack
#   prototype/demo.sh enable     after the reboot: enable the pack and restart the shell
#   prototype/demo.sh status     what the running session actually sees
#   prototype/demo.sh sync       copy edits back out of the checkout, rebuild the patches
#   prototype/demo.sh pack       publish omarchy-lang-ca to its git remote and update the install
#   prototype/demo.sh teardown   undo everything (dev-unlink needs a reboot too)
#
# The checkout goes to $OMARCHY_L10N_CHECKOUT (default ~/src/omarchy).

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checkout="${OMARCHY_L10N_CHECKOUT:-$HOME/src/omarchy}"
# The commit the patches were cut against. quattro moves fast; setup pins to
# this so `git am` is deterministic. Set OMARCHY_L10N_BASE=quattro to try HEAD.
base="${OMARCHY_L10N_BASE:-0ae1694830b6bd9511042fe1b89a0062d8c083cb}"
# The language pack is installed the way a real one would be: cloned by
# `omarchy plugin add` from a git remote. Here the remote is a bare repo next
# to the checkout, and ~/.config/omarchy/language-packs points lang.ca at it.
pack_repo="${OMARCHY_L10N_PACK_REPO:-$HOME/src/omarchy-lang-ca.git}"
plugin_dir="$HOME/.config/omarchy/plugins/lang.ca"
packs_conf="$HOME/.config/omarchy/language-packs"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/i18n"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
no() { printf '  \033[31m✗\033[0m %s\n' "$*"; }

session_omarchy_path() {
  systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1
}

# Commit the current prototype/omarchy-lang-ca into the bare repo the pack is
# installed from, so `omarchy plugin update lang.ca` (and omarchy-language)
# pull the latest catalogs the way they would from GitHub.
publish_pack() {
  local work
  work="$(mktemp -d)"
  [[ -d $pack_repo ]] || git init -q --bare "$pack_repo"
  git clone -q "$pack_repo" "$work" 2>/dev/null || git -C "$work" init -q
  rm -rf "${work:?}"/* && cp -r "$here/omarchy-lang-ca/." "$work/"
  git -C "$work" add -A
  if git -C "$work" diff --cached --quiet 2>/dev/null; then
    echo "      (pack unchanged)"
  else
    git -C "$work" -c user.name=omarchy-l10n -c user.email=l10n@omarchy.invalid commit -q -m "Update catalogs from $(git -C "$here/.." rev-parse --short HEAD 2>/dev/null || echo local)"
    git -C "$work" push -q "$pack_repo" HEAD:refs/heads/main 2>/dev/null || git -C "$work" push -q "$pack_repo" HEAD:main
    git -C "$pack_repo" symbolic-ref HEAD refs/heads/main
    ok "published $(git -C "$work" rev-parse --short HEAD)"
  fi
  rm -rf "$work"
}

cmd_pack() {
  say "Publishing the pack"
  publish_pack
  if [[ -d $plugin_dir/.git ]]; then
    say "Updating the installed copy"
    omarchy-plugin-update lang.ca --yes | sed 's/^/      /'
  fi
}

cmd_setup() {
  say "1. Checkout at $checkout"
  if [[ -d $checkout/.git ]]; then
    git -C "$checkout" fetch -q origin quattro
  else
    git clone -q -b quattro https://github.com/basecamp/omarchy "$checkout"
  fi
  git -C "$checkout" branch -D l10n-prototype >/dev/null 2>&1 || true
  git -C "$checkout" checkout -q -b l10n-prototype "$base"
  ok "branch l10n-prototype from $(git -C "$checkout" rev-parse --short HEAD) ($base)"

  say "2. Applying patches"
  git -C "$checkout" am -q "$here"/patches/*.patch
  git -C "$checkout" log --oneline "$base"..l10n-prototype | sed 's/^/  /'

  say "3. Publishing the language pack to $pack_repo"
  publish_pack

  say "4. Installing it with omarchy plugin add"
  rm -rf "$plugin_dir" "$HOME/.config/omarchy/plugins/omarchy-lang-ca"
  mkdir -p "$(dirname "$packs_conf")"
  grep -v '^ca ' "$packs_conf" 2>/dev/null > "$packs_conf.tmp" || true
  echo "ca file://$pack_repo" >> "$packs_conf.tmp" && mv "$packs_conf.tmp" "$packs_conf"
  omarchy-plugin-add "file://$pack_repo" --yes >/dev/null
  ok "$plugin_dir (git-managed, so omarchy-language can update it)"

  say "5. Dev-linking the checkout"
  omarchy dev link "$checkout" --no-reboot
  ok "OMARCHY_PATH will be $checkout after reboot"

  say "Next"
  echo "  reboot, log in, then:  $0 enable"
}

cmd_enable() {
  local live
  live="$(session_omarchy_path)"
  if [[ $live != "$checkout" ]]; then
    no "session OMARCHY_PATH is '${live:-unset}', not $checkout — reboot after setup first"
    exit 1
  fi
  say "Enabling lang.ca"
  omarchy plugin enable lang.ca
  say "Restarting the shell so the pack loads cleanly"
  omarchy restart shell
  echo
  echo "  Open the menu. Then:  $0 status"
}

cmd_status() {
  local live
  live="$(session_omarchy_path)"
  say "Session"
  [[ $live == "$checkout" ]] && ok "OMARCHY_PATH=$live" || no "OMARCHY_PATH=${live:-unset} (expected $checkout)"
  [[ -f $live/shell/Commons/I18n.qml ]] && ok "I18n.qml present in the linked tree" || no "I18n.qml missing from $live/shell/Commons"
  echo "  LANG=${LANG:-} LANGUAGE=${LANGUAGE:-} LC_ALL=${LC_ALL:-} LC_MESSAGES=${LC_MESSAGES:-}"

  say "Language"
  echo "  omarchy-language → $("$live/bin/omarchy-language" 2>/dev/null || echo '(not on this checkout)')   chain: $("$live/bin/omarchy-language" --chain 2>/dev/null)"
  [[ -f $HOME/.config/environment.d/omarchy-language.conf ]] && ok "environment.d/omarchy-language.conf present" || echo "  (no environment.d override — session locale from /etc/locale.conf)"

  say "Plugin"
  if command -v omarchy-shell >/dev/null; then
    omarchy-shell shell listPlugins 2>/dev/null | jq -r '.[] | select(.id == "lang.ca") | "  " + (. | tostring)' || no "shell did not answer listPlugins"
  fi

  say "Cache ($cache_dir)"
  if ls "$cache_dir"/*.json >/dev/null 2>&1; then
    for f in "$cache_dir"/*.json; do
      ok "$(basename "$f"): $(jq -r '.catalogs | keys | join(", ")' "$f")"
    done
  else
    no "no cache yet — it is written ~250ms after the pack registers"
  fi

  say "Bash helper"
  # shellcheck disable=SC1091
  source "$live/default/bash/i18n"
  echo "  omarchy_t \"Continue with update?\"  →  $(omarchy_t "Continue with update?")"

  say "Shell log (journal, last i18n-related lines)"
  journalctl --user -t omarchy-shell -n 200 --no-pager 2>/dev/null | grep -iE "i18n|lang\.ca|service plugin|warn" | tail -n 12 | sed 's/^/  /' || true
}

# The primitive exists twice: prototype/shell/ and default/ are what the tests
# import and what a reader browses, while the dev-linked checkout is what
# actually runs. Editing the live one and forgetting the other is easy — it
# already happened once, and the copies only disagreed when a test failed.
# This copies one way, checkout -> repo, because the checkout is both where
# you edit and where the patch series is cut from.
MIRRORED=(
  shell/Commons/I18n.qml
  shell/Commons/I18nModel.js
  shell/Commons/qmldir
  default/bash/i18n
  bin/omarchy-language
)

cmd_sync() {
  [[ -d $checkout/.git ]] || { no "no checkout at $checkout — run '$0 setup' first"; exit 1; }

  say "1. Copying the primitive out of $checkout"
  local dirty
  dirty="$(git -C "$checkout" status --porcelain -- shell/Commons default/bash)"
  if [[ -n $dirty ]]; then
    no "uncommitted changes in the checkout — these would reach prototype/ but not the patches:"
    printf '%s\n' "$dirty" | sed 's/^/      /'
    echo "      commit them in $checkout first, then re-run"
    exit 1
  fi
  local changed=0
  for f in "${MIRRORED[@]}"; do
    if [[ ! -f $checkout/$f ]]; then
      no "missing from the checkout: $f"
      exit 1
    fi
    if cmp -s "$checkout/$f" "$here/$f"; then
      echo "      unchanged  $f"
    else
      cp "$checkout/$f" "$here/$f"
      ok "updated    $f"
      changed=$((changed + 1))
    fi
  done
  [[ $changed -eq 0 ]] && echo "      (already in sync)"

  say "2. Rebuilding the patch series from $base..HEAD"
  rm -f "$here"/patches/*.patch
  git -C "$checkout" format-patch -q -o "$here/patches" "$base..HEAD"
  ls "$here"/patches | sed 's/^/      /'

  say "3. Tests"
  npm --prefix "$here/.." test

  say "Next"
  echo "  review with:  git -C $(cd "$here/.." && pwd) diff"
}

cmd_teardown() {
  say "Removing the pack and its cache"
  omarchy plugin disable lang.ca >/dev/null 2>&1 || true
  rm -rf "$plugin_dir" "$cache_dir" "$HOME/.config/omarchy/plugins/omarchy-lang-ca"
  rm -f "$packs_conf" "$HOME/.config/environment.d/omarchy-language.conf"
  say "Dev-unlinking"
  omarchy dev unlink
  echo "  reboot to return to the packaged shell; the checkout at $checkout is left in place"
}

case "${1:-}" in
  setup) cmd_setup ;;
  enable) cmd_enable ;;
  status) cmd_status ;;
  sync) cmd_sync ;;
  pack) cmd_pack ;;
  teardown) cmd_teardown ;;
  *) sed -n '2,11p' "$0"; exit 2 ;;
esac

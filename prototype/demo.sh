#!/bin/bash
# Set up, inspect, or remove the localization prototype on an Omarchy machine.
#
#   prototype/demo.sh setup      clone quattro, apply the patches, dev-link, install the pack
#   prototype/demo.sh enable     after the reboot: enable the pack and restart the shell
#   prototype/demo.sh status     what the running session actually sees
#   prototype/demo.sh teardown   undo everything (dev-unlink needs a reboot too)
#
# The checkout goes to $OMARCHY_L10N_CHECKOUT (default ~/src/omarchy).

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checkout="${OMARCHY_L10N_CHECKOUT:-$HOME/src/omarchy}"
# The commit the patches were cut against. quattro moves fast; setup pins to
# this so `git am` is deterministic. Set OMARCHY_L10N_BASE=quattro to try HEAD.
base="${OMARCHY_L10N_BASE:-0ae1694830b6bd9511042fe1b89a0062d8c083cb}"
plugin_dir="$HOME/.config/omarchy/plugins/omarchy-lang-ca"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/i18n"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
no() { printf '  \033[31m✗\033[0m %s\n' "$*"; }

session_omarchy_path() {
  systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1
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

  say "3. Installing the language pack (disabled until the new shell runs)"
  rm -rf "$plugin_dir"
  cp -r "$here/omarchy-lang-ca" "$plugin_dir"
  ok "$plugin_dir"

  say "4. Dev-linking the checkout"
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

cmd_teardown() {
  say "Removing the pack and its cache"
  omarchy plugin disable lang.ca >/dev/null 2>&1 || true
  rm -rf "$plugin_dir" "$cache_dir"
  say "Dev-unlinking"
  omarchy dev unlink
  echo "  reboot to return to the packaged shell; the checkout at $checkout is left in place"
}

case "${1:-}" in
  setup) cmd_setup ;;
  enable) cmd_enable ;;
  status) cmd_status ;;
  teardown) cmd_teardown ;;
  *) sed -n '2,9p' "$0"; exit 2 ;;
esac

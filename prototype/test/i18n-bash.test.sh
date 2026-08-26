#!/usr/bin/env bash
# Tests for prototype/default/bash/i18n. Run with: npm test (or directly).
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
helper="$here/../default/bash/i18n"

pass=0
fail=0
check() {
  local label="$1" expected="$2" actual="$3"
  if [[ $expected == "$actual" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  expected: %q\n  actual:   %q\n' "$label" "$expected" "$actual"
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/omarchy/i18n"

cat >"$tmp/omarchy/i18n/ca.json" <<'JSON'
{
  "version": 1,
  "catalogs": {
    "omarchy.cli": {
      "": { "language": "ca", "plural-forms": "nplurals=2; plural=(n != 1);" },
      "Update now?": "Actualitzar ara?",
      "Removing %1": "Suprimint %1",
      "%1 package": ["%1 paquet", "%1 paquets"],
      "Ampersand": "A & B"
    },
    "omarchy.menu": { "Update now?": "WRONG DOMAIN" }
  },
  "links": {}
}
JSON

cat >"$tmp/omarchy/i18n/pl.json" <<'JSON'
{
  "version": 1,
  "catalogs": {
    "omarchy.cli": {
      "": { "plural-forms": "nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);" },
      "%1 file": ["%1 plik", "%1 pliki", "%1 plików"]
    }
  },
  "links": {}
}
JSON

cat >"$tmp/omarchy/i18n/xx.json" <<'JSON'
{
  "version": 1,
  "catalogs": {
    "omarchy.cli": {
      "": { "plural-forms": "nplurals=2; plural=(a[$(touch /tmp/pwned)]);" },
      "%1 item": ["one", "many"]
    }
  },
  "links": {}
}
JSON

export XDG_CACHE_HOME="$tmp"
export HOME="$tmp/nohome"
unset LANGUAGE LC_ALL LC_MESSAGES

# ---- language detection ----------------------------------------------------
LANG=ca_ES.UTF-8; source "$helper"
check "language from LANG" "ca" "$(omarchy_i18n_language)"
LANG=C;            check "C locale is English" "" "$(omarchy_i18n_language)"
LANG=en_US.UTF-8;  check "en is English" "" "$(omarchy_i18n_language)"
LANG=de_DE LC_MESSAGES=fr_FR; check "LC_MESSAGES beats LANG" "fr" "$(omarchy_i18n_language)"
unset LC_MESSAGES
LANG=de_DE LANGUAGE=ca:es; check "LANGUAGE first entry wins" "ca" "$(omarchy_i18n_language)"
unset LANGUAGE

# ---- English path never needs the cache ------------------------------------
LANG=en_US.UTF-8
check "en: source returned" "Update now?" "$(omarchy_t "Update now?")"
check "en: interpolation" "Removing vim" "$(omarchy_t "Removing %1" vim)"
check "en: plural 1" "1 package" "$(omarchy_tn 1 "%1 package" "%1 packages" 1)"
check "en: plural 3" "3 packages" "$(omarchy_tn 3 "%1 package" "%1 packages" 3)"

# ---- Catalan ---------------------------------------------------------------
LANG=ca_ES.UTF-8
check "ca: cache path" "$tmp/omarchy/i18n/ca.json" "$(omarchy_i18n_cache_path)"
check "ca: translated" "Actualitzar ara?" "$(omarchy_t "Update now?")"
check "ca: interpolation" "Suprimint vim" "$(omarchy_t "Removing %1" vim)"
check "ca: missing key falls back" "Not in catalog" "$(omarchy_t "Not in catalog")"
check "ca: plural 1" "1 paquet" "$(omarchy_tn 1 "%1 package" "%1 packages" 1)"
check "ca: plural 0" "0 paquets" "$(omarchy_tn 0 "%1 package" "%1 packages" 0)"
check "ca: plural 5" "5 paquets" "$(omarchy_tn 5 "%1 package" "%1 packages" 5)"
check "ca: tr on a plural entry gives singular" "7 paquet" "$(omarchy_t "%1 package" 7)"
check "ca: ampersand in translation survives" "A & B" "$(omarchy_t "Ampersand")"

# ---- interpolation edge cases ----------------------------------------------
check "%10 is not %1+0" "j a" "$(omarchy_i18n_interpolate "%10 %1" a b c d e f g h i j)"
check "arg containing %2 is not re-expanded" "say %2 in 5 min" "$(omarchy_i18n_interpolate "%1 in %2 min" "say %2" 5)"
check "arg containing & is literal" "x & y" "$(omarchy_i18n_interpolate "%1" "x & y")"
check "missing arg left as-is" "a and %3" "$(omarchy_i18n_interpolate "%1 and %3" a)"

# ---- Polish plural rule evaluated in bash arithmetic -----------------------
LANG=pl_PL.UTF-8
check "pl: 1" "1 plik"    "$(omarchy_tn 1 "%1 file" "%1 files" 1)"
check "pl: 3" "3 pliki"   "$(omarchy_tn 3 "%1 file" "%1 files" 3)"
check "pl: 5" "5 plików"  "$(omarchy_tn 5 "%1 file" "%1 files" 5)"
check "pl: 22" "22 pliki" "$(omarchy_tn 22 "%1 file" "%1 files" 22)"
check "pl: 102" "102 pliki" "$(omarchy_tn 102 "%1 file" "%1 files" 102)"

# ---- hostile plural rule is refused, not evaluated -------------------------
LANG=xx_XX.UTF-8
rm -f /tmp/pwned
check "hostile rule: English behaviour" "many" "$(omarchy_tn 3 "%1 item" "%1 items")"
check "hostile rule: singular" "one" "$(omarchy_tn 1 "%1 item" "%1 items")"
[[ -e /tmp/pwned ]] && check "hostile rule: no command ran" "absent" "present"

# ---- no cache file ---------------------------------------------------------
LANG=de_DE.UTF-8
check "no cache: source returned" "Update now?" "$(omarchy_t "Update now?")"

# ---- set -e / set -u safety ------------------------------------------------
out="$(set -eu; source "$helper"; LANG=ca_ES.UTF-8 omarchy_t "Update now?"; echo "|ok")"
check "survives set -eu" "Actualitzar ara?|ok" "$out"

printf 'bash i18n: %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))

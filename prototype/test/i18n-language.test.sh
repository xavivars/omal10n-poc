#!/usr/bin/env bash
# Tests for prototype/bin/omarchy-language's pure helpers. Run with: npm test.
#
# The script is sourced rather than run, which exposes expand_chain,
# first_supported, suggest_locale and friends without touching the machine.
# `locale -a` is shimmed through PATH so the generated-locale set is fixed.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../bin/omarchy-language"

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

# A machine with Catalan (both variants) and US English generated, nothing else.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/locale" <<'SH'
#!/usr/bin/env bash
printf '%s\n' C C.utf8 POSIX ca_ES.utf8 ca_ES.utf8@valencia en_US.utf8
SH
chmod +x "$tmp/bin/locale"
export PATH="$tmp/bin:$PATH"

# glibc's list of what could be generated.
printf '%s\n' "ca_ES.UTF-8 UTF-8" "de_DE.UTF-8 UTF-8" "de_AT.UTF-8 UTF-8" "pt_BR.UTF-8 UTF-8" "pt_PT.UTF-8 UTF-8" >"$tmp/SUPPORTED"
export OMARCHY_SUPPORTED_LOCALES="$tmp/SUPPORTED"
export XDG_CONFIG_HOME="$tmp/config"

# shellcheck disable=SC1090
source "$script"

# --- language_of ------------------------------------------------------------
check "language_of bare"      "ca" "$(language_of ca)"
check "language_of region"    "ca" "$(language_of ca_ES)"
check "language_of encoding"  "ca" "$(language_of ca_ES.UTF-8)"
check "language_of modifier"  "ca" "$(language_of ca_ES@valencia)"
check "language_of bare+mod"  "ca" "$(language_of ca@valencia)"

# --- expand_chain -----------------------------------------------------------
check "expand: bare"            "ca"                                        "$(expand_chain ca)"
check "expand: region"          "ca_ES:ca"                                  "$(expand_chain ca_ES)"
check "expand: gettext order"   "ca_ES@valencia:ca@valencia:ca_ES:ca"       "$(expand_chain ca_ES@valencia)"
check "expand: encoding dropped" "ca_ES:ca"                                 "$(expand_chain ca_ES.UTF-8)"
check "expand: two languages"   "ca_ES:ca:es_ES:es"                         "$(expand_chain ca_ES:es_ES)"
check "expand: dedup"           "ca_ES:ca:es"                               "$(expand_chain ca_ES:ca:es)"
check "expand: stops at en"     "de_DE:de:en"                               "$(expand_chain de_DE:en:fr)"
check "expand: C ignored"       "ca"                                        "$(expand_chain C:ca)"
check "expand: empty"           ""                                          "$(expand_chain "")"

# --- first_supported (LANG derivation) -------------------------------------
check "LANG: regional+modifier generated" "ca_ES.UTF-8@valencia" "$(first_supported ca_ES@valencia:ca@valencia:ca_ES:ca)"
check "LANG: bare picks a generated region" "ca_ES.UTF-8" "$(first_supported ca)"
check "LANG: English" "en_US.UTF-8" "$(first_supported en)"
check "LANG: first *supported*, not first" "ca_ES.UTF-8" "$(first_supported de_DE:de:ca_ES:ca)"
check "LANG: nothing generated → empty, non-zero" "|1" "$(first_supported de_DE:de || echo "|$?")"
check "LANG: bare+modifier never matches alone" "ca_ES.UTF-8" "$(first_supported ca@valencia:ca)"

# --- suggest_locale (what to locale-gen) -----------------------------------
check "suggest: regional entry wins"     "de_DE.UTF-8" "$(suggest_locale de_DE:de)"
check "suggest: modifier stripped"       "de_DE.UTF-8" "$(suggest_locale de_DE@euro:de)"
check "suggest: bare → ll_LL preferred" "pt_PT.UTF-8" "$(suggest_locale pt)"
printf 'de_AT.UTF-8 UTF-8\n' >"$tmp/SUPPORTED.at-only"
check "suggest: bare → first listed otherwise" "de_AT.UTF-8" "$(SUPPORTED_LOCALES="$tmp/SUPPORTED.at-only" suggest_locale de)"
check "suggest: unknown → non-zero"      "1" "$(suggest_locale xx >/dev/null || echo $?)"

# --- current_chain: file beats environment ----------------------------------
LANGUAGE="es_ES:es" LANG="es_ES.UTF-8"
check "chain: env when no file" "es_ES:es" "$(current_chain)"
mkdir -p "$tmp/config/environment.d"
printf 'LANG=ca_ES.UTF-8\nLANGUAGE=ca_ES:ca\n' >"$tmp/config/environment.d/omarchy-language.conf"
LANGUAGE_CONF="$tmp/config/environment.d/omarchy-language.conf"
check "chain: file wins" "ca_ES:ca" "$(current_chain)"
unset LANGUAGE
rm "$LANGUAGE_CONF"
LANG="ca_ES.UTF-8"
check "chain: LANG only is expanded" "ca_ES:ca" "$(current_chain)"

# --- pack_url ---------------------------------------------------------------
check "pack_url: template" "https://github.com/omarchy-i18n/omarchy-lang-ca.git" "$(pack_url ca)"
mkdir -p "$tmp/config/omarchy"
PACKS_CONF="$tmp/config/omarchy/language-packs"
printf 'ca file:///srv/omarchy-lang-ca.git\n' >"$PACKS_CONF"
check "pack_url: override file" "file:///srv/omarchy-lang-ca.git" "$(pack_url ca)"
check "pack_url: override misses → template" "https://github.com/omarchy-i18n/omarchy-lang-de.git" "$(pack_url de)"

# --- preferred_chain: a bare language keeps a chain already in force --------
rm -f "$LANGUAGE_CONF"
SYSTEM_LOCALE_CONF="$tmp/locale.conf"
printf 'LANG=ca_ES.UTF-8\nLANGUAGE=ca_ES@valencia:ca@valencia:ca_ES:ca\n' >"$SYSTEM_LOCALE_CONF"
check "preferred: system LANGUAGE for its language" "ca_ES@valencia:ca@valencia:ca_ES:ca" "$(preferred_chain ca)"
check "preferred: other language → none"            "1" "$(preferred_chain de >/dev/null || echo $?)"
printf 'LANG=de_DE.UTF-8\n' >"$SYSTEM_LOCALE_CONF"
check "preferred: system LANG alone is expanded"    "de_DE:de" "$(preferred_chain de)"
printf 'LANGUAGE=ca_ES:es_ES\n' >"$LANGUAGE_CONF"
check "preferred: own file beats the system"        "ca_ES:ca:es_ES:es" "$(preferred_chain ca)"
check "preferred: own file, other language → system" "de_DE:de" "$(preferred_chain de)"
rm -f "$LANGUAGE_CONF"

# --- remembered chains: an edit survives leaving the language and coming back
CHAINS_CONF="$tmp/config/omarchy/language-chains"
printf 'LANG=ca_ES.UTF-8\nLANGUAGE=ca_ES@valencia:ca@valencia:ca_ES:ca\n' >"$SYSTEM_LOCALE_CONF"
remember_chain "ca_ES:ca"                      # the user edited Advanced down to ca_ES
remember_chain "en"                            # then switched to English
check "remembered: per-language file" "ca ca_ES:ca
en en" "$(cat "$CHAINS_CONF")"
check "remembered: beats the system's chain"   "ca_ES:ca" "$(preferred_chain ca)"
remember_chain "ca_ES:ca:es"                   # re-applied: replaces, no duplicate
check "remembered: replaced in place" "1" "$(grep -c '^ca ' "$CHAINS_CONF")"
check "remembered: latest wins" "ca_ES:ca:es" "$(preferred_chain ca)"
check "remembered: unknown language → system" "1" "$(preferred_chain de >/dev/null || echo $?)"
rm -f "$CHAINS_CONF"

# --- seed_conf: the first edit starts from what is in force -----------------
LANGUAGE="ca_ES@valencia:ca" LANG="ca_ES.UTF-8@valencia"
seed_conf
check "seed: LANGUAGE from session" "ca_ES@valencia:ca" "$(conf_value "$LANGUAGE_CONF" LANGUAGE)"
check "seed: LANG from session"     "ca_ES.UTF-8@valencia" "$(conf_value "$LANGUAGE_CONF" LANG)"
printf 'LANGUAGE=hand:edited\n' >"$LANGUAGE_CONF"
seed_conf
check "seed: never overwrites an existing file" "hand:edited" "$(conf_value "$LANGUAGE_CONF" LANGUAGE)"
rm -f "$LANGUAGE_CONF"; unset LANGUAGE
LANG="C.UTF-8"
printf 'LANG=ca_ES.UTF-8\nLANGUAGE=ca_ES:ca\n' >"$SYSTEM_LOCALE_CONF"
seed_conf
check "seed: falls back to the system file" "ca_ES:ca" "$(conf_value "$LANGUAGE_CONF" LANGUAGE)"
rm -f "$LANGUAGE_CONF"

# --- language_rows: endonyms, filtered to what glibc can generate ------------
printf '%s\n' "ca_ES.UTF-8 UTF-8" "de_DE.UTF-8 UTF-8" "pt_BR.UTF-8 UTF-8" >"$tmp/SUPPORTED.rows"
SUPPORTED_LOCALES="$tmp/SUPPORTED.rows"
LANGUAGE="ca_ES:ca"
rows="$(language_rows)"
check "rows: only generatable languages" "3" "$(wc -l <<<"$rows")"
check "rows: glyph, endonym, code"       "󰗊	Deutsch	de" "$(grep -P '\tde$' <<<"$rows")"
check "rows: current one is ticked"      "󰗊	Català ✓	ca" "$(grep -P '\tca$' <<<"$rows")"
check "rows: three fields, so the name is the label not the icon" "3" "$(grep -P '\tde$' <<<"$rows" | awk -F'\t' '{print NF}')"
check "rows: en absent when not generatable" "" "$(grep -P '\ten$' <<<"$rows")"
check "language_name: known"   "Português" "$(language_name pt)"
check "language_name: unknown falls back to the code" "xx" "$(language_name xx)"
unset LANGUAGE

# --- system default: rewritten in place through pkexec ---------------------
cat >"$tmp/bin/pkexec" <<'SH'
#!/usr/bin/env bash
# sh -c "cat > '<file>'" — capture what would be written, honour a decline
[[ -n ${PKEXEC_STATUS:-} && $PKEXEC_STATUS != 0 ]] && { cat >/dev/null; exit "$PKEXEC_STATUS"; }
echo "called" >>"${PKEXEC_LOG:?}"
target="${3#cat > \'}"; target="${target%\'}"
cat >"$target"
SH
chmod +x "$tmp/bin/pkexec"
cat >"$tmp/bin/omarchy-notification-send" <<'SH'
#!/usr/bin/env bash
echo "$*" >>"${TOAST_LOG:?}"
SH
chmod +x "$tmp/bin/omarchy-notification-send"; export TOAST_LOG="$tmp/toast.log" PKEXEC_LOG="$tmp/pkexec.log"

existing=$'# LANG drives formats.\nLANG=ca_ES.UTF-8\n\n# the chain\nLANGUAGE=ca_ES:ca\nLC_TIME=en_DK.UTF-8'
check "merge: replaces in place, keeps the rest" $'# LANG drives formats.\nLANG=en_US.UTF-8\n\n# the chain\nLANGUAGE=en\nLC_TIME=en_DK.UTF-8' "$(merge_locale_conf "$existing" en_US.UTF-8 en)"
check "merge: appends what is missing" $'LC_TIME=en_DK.UTF-8\nLANG=en_US.UTF-8\nLANGUAGE=en' "$(merge_locale_conf "LC_TIME=en_DK.UTF-8" en_US.UTF-8 en)"
check "merge: empty file" $'LANG=en_US.UTF-8\nLANGUAGE=en' "$(merge_locale_conf "" en_US.UTF-8 en)"
check "merge: a chain with colons is fine" "LANGUAGE=ca_ES@valencia:ca:es" "$(merge_locale_conf "" x ca_ES@valencia:ca:es | tail -n 1)"

SYSTEM_LOCALE_CONF="$tmp/etc-locale.conf"; printf '%s\n' "$existing" >"$SYSTEM_LOCALE_CONF"
: >"$PKEXEC_LOG"; : >"$TOAST_LOG"
set_system_locale ca_ES.UTF-8 ca_ES:ca
check "system: unchanged → not asked" "" "$(cat "$PKEXEC_LOG")"
set_system_locale en_US.UTF-8 en
check "system: differs → written through pkexec" "called" "$(cat "$PKEXEC_LOG")"
check "system: …comments survive" "# LANG drives formats." "$(head -n 1 "$SYSTEM_LOCALE_CONF")"
check "system: …values replaced" "LANGUAGE=en" "$(grep ^LANGUAGE= "$SYSTEM_LOCALE_CONF")"
: >"$PKEXEC_LOG"; : >"$TOAST_LOG"
check "system: declined → non-zero" "1" "$(PKEXEC_STATUS=126 set_system_locale ca_ES.UTF-8 ca 2>/dev/null; echo $?)"
check "system: declined → file untouched" "LANGUAGE=en" "$(grep ^LANGUAGE= "$SYSTEM_LOCALE_CONF")"
check "system: declined → says so" "1" "$(grep -c "System default not updated" "$TOAST_LOG")"

# --- effective_language: what the interface will really render in ----------
check "effective: first has a pack"            "ca" "$(effective_language ca_ES:ca:es "es")"
check "effective: first missing, second has"   "es" "$(effective_language ca:es "ca")"
check "effective: all missing → English"       "en" "$(effective_language ca:es "ca es")"
check "effective: English is its own pack"     "en" "$(effective_language en:ca "ca")"
check "effective: nothing missing"             "ca" "$(effective_language ca_ES@valencia:ca "")"

# --- region_rows: territories from glibc's own sources ----------------------
printf '%s\n' "es_ES.UTF-8 UTF-8" "es_AR.UTF-8 UTF-8" "ca_ES.UTF-8 UTF-8" "ca_ES.UTF-8@valencia UTF-8" "ca_AD.UTF-8 UTF-8" "ca_ES.UTF-8@euro UTF-8" "de_DE.UTF-8 UTF-8" "sr_RS.UTF-8 UTF-8" "sr_RS.UTF-8@latin UTF-8" >"$tmp/SUPPORTED.regions"
mkdir -p "$tmp/locales"
printf 'territory "Serbia"\n' >"$tmp/locales/sr_RS"
printf 'LC_IDENTIFICATION\ntitle "Spanish locale for Argentina"\nterritory "Argentina"\n' >"$tmp/locales/es_AR"
printf 'territory "Spain"\n' >"$tmp/locales/es_ES"
printf 'territory "Spain"\n' >"$tmp/locales/ca_ES"
printf 'territory "Spain"\n' >"$tmp/locales/ca_ES@valencia"
SUPPORTED_LOCALES="$tmp/SUPPORTED.regions"; LOCALE_SOURCES="$tmp/locales"
check "regions: Any region first, bare code"  "Any region	es" "$(region_rows es | head -n 1 | cut -f2-)"
check "regions: territory name, code subtext" "Argentina	es_AR" "$(region_rows es | grep -P '\tes_AR$' | cut -f2-)"
check "regions: only that language"           "3" "$(region_rows es | wc -l)"
check "regions: modifier shown"               "Spain (valencia)	ca_ES@valencia" "$(region_rows ca | grep valencia | cut -f2-)"
check "regions: no source file → code"        "ca_AD	ca_AD" "$(region_rows ca | grep -P '\tca_AD$' | cut -f2-)"
check "regions: none known → just Any region" "1" "$(region_rows xx | wc -l)"
check "territory_of: unknown → code" "zz_ZZ" "$(territory_of zz_ZZ)"
check "regions: script modifier"  "Serbia (latin)	sr_RS@latin" "$(region_rows sr | grep latin | cut -f2-)"
check "regions: @euro left out"   "" "$(region_rows ca | grep euro)"

printf 'bash language: %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))

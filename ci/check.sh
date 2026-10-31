#!/usr/bin/env bash
# Quality gate shared by every d-labsit Magento module. CI runs it on each pull
# request (.github/workflows/module-ci.yml); developers and AI agents run the
# same script locally before opening one:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/d-labsit/.github/main/ci/check.sh)
#
# Run it from the module root inside a Magento dev container (PHP 8.4+,
# composer, xmllint, phpcs with the Magento2 standard). phpstan/phpunit run
# through the module's own dev/ci/run.sh, or else through ci/module-run.sh when
# the module ships composer.ci.json.
#
# Convention checks (marked "soft" below) only warn for now, so no module goes
# red before it is fixed; DLABSIT_CI_STRICT=1 makes them fail the gate.
set -uo pipefail

RAW_BASE=https://raw.githubusercontent.com/d-labsit/.github/main
CANONICAL_AGENTS_URL=$RAW_BASE/AGENTS.md
BEGIN_MARK='<!-- BEGIN d-labsit shared rules -->'
END_MARK='<!-- END d-labsit shared rules -->'
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)

failed=()
warned=()
in_ci() { [ -n "${GITHUB_ACTIONS:-}" ]; }
group() { if in_ci; then echo "::group::$1"; else echo "== $1"; fi; }
endgroup() { if in_ci; then echo "::endgroup::"; fi; }
run() {
    local name=$1; shift
    group "$name"
    if "$@"; then echo "ok"; else failed+=("$name"); in_ci && echo "::error::$name failed"; fi
    endgroup
}
# Like run, but a failure is a warning unless DLABSIT_CI_STRICT=1.
soft() {
    local name=$1; shift
    if [ "${DLABSIT_CI_STRICT:-0}" = 1 ]; then run "$name" "$@"; return; fi
    group "$name"
    local out
    if out=$("$@" 2>&1); then echo "ok"; endgroup; return; fi
    echo "$out"
    endgroup
    warned+=("$name")
    if in_ci; then
        out=${out//'%'/%25}; out=${out//$'\r'/%0D}; out=${out//$'\n'/%0A}
        echo "::warning title=$name::$out"
    fi
}

# Tracked files only: vendor/, generated output and the CI checkout of this
# repo (.module-ci) never count.
files() { git ls-files -- "$@" 2>/dev/null; }

check_composer() {
    composer validate --no-check-lock --no-check-publish --no-interaction
}

check_php_lint() {
    local out
    out=$(files '*.php' '*.phtml' | xargs -r -n1 -P4 php -l 2>&1 | grep -v '^No syntax errors detected')
    [ -z "$out" ] || { echo "$out"; return 1; }
}

check_phpcs() {
    local phpcs
    phpcs=$(command -v phpcs || echo vendor/bin/phpcs)
    [ -x "$phpcs" ] || { echo "phpcs not found (install magento/magento-coding-standard)"; return 1; }
    local list
    list=$(files '*.php' '*.phtml' | grep -v -e '^dev/' -e '^Test/Unit/_files/')
    [ -n "$list" ] || return 0
    # Errors only (-n); warnings are advice, not a gate. testVersion follows the
    # PHP 8.4 baseline, otherwise PHPCompatibility flags 8.2+ syntax.
    echo "$list" | xargs "$phpcs" --standard=Magento2 -n -q --extensions=php,phtml --runtime-set testVersion 8.4-
}

# Substantive Magento2 warnings (severity 7 and up: escaping, discouraged
# functions, empty catch blocks, performance). The lower ones (docblocks, line
# length) stay advice: typed code and phpstan level 6 cover what they ask for.
check_phpcs_warnings() {
    local phpcs list
    phpcs=$(command -v phpcs || echo vendor/bin/phpcs)
    [ -x "$phpcs" ] || return 0
    list=$(files '*.php' '*.phtml' | grep -v -e '^dev/' -e '^Test/')
    [ -n "$list" ] || return 0
    echo "$list" | xargs "$phpcs" --standard=Magento2 --error-severity=0 --warning-severity=7 -q \
        --extensions=php,phtml --runtime-set testVersion 8.4- --runtime-set ignore_warnings_on_exit 0
}


# 9.4/9.10: session and cookie state in cacheable code ends up in the
# full-page cache and is served to the next visitor. The request is fine: the
# URL is part of the cache key. Controllers and plugins on controllers may use
# session and cookies.
check_session_in_cacheable_code() {
    local out
    out=$(src_php | grep -E '^(Block|ViewModel|Model|Plugin|Observer|Helper)/' | grep -v '^Plugin/Controller/' \
        | xargs -r grep -HnE '^\s*(private|protected|public)?\s*(readonly\s+)?\\?([A-Za-z\\]*\\)?(SessionManagerInterface|Session|CookieManagerInterface)\s+\$' \
        | grep -vE 'adobe-tg: ' )
    [ -z "$out" ] || { echo "$out"; echo "session/cookie injected in code that can render into a cached page: one visitor's state can be served to the next (Adobe TG 9.4, 9.10). Move it to a controller, a CustomerData section or JS; or put '// adobe-tg: <why this never renders into a cached page>' on that line"; return 1; }
}

# 4.x + extension best practices: around plugins cost a stack frame on every
# call and hide the original; before/after plugins are the default.
check_around_plugins() {
    local out
    out=$(src_php | grep '^Plugin/' | xargs -r grep -HnE -B2 'public function around[A-Z]' \
        | awk '/adobe-tg: /{skip=1} /public function around[A-Z]/{ if (!skip) print; skip=0 } /^--$/{skip=0}')
    [ -z "$out" ] || { echo "$out"; echo "around plugin without a reason: use a before/after plugin, or put '// adobe-tg: <why around is needed>' on the line above"; return 1; }
}

# Extension best practices: no Helper catch-all classes; put the code in the
# class it belongs to (service, view model, value object).
check_helper_classes() {
    local out
    out=$(src_php | grep -E '(^|/)Helper/[^/]+\.php$' | xargs -r grep -L 'adobe-tg: ')
    [ -z "$out" ] || { echo "$out"; echo "Helper classes: move the code to a service, view model or the class it operates on (Adobe extension best practices). An existing helper that stays gets '// adobe-tg: legacy helper, no new methods' at the class"; return 1; }
}

# 15.7.2: data changes only through POST. A GET action that saves or deletes is
# reachable by a link or an image tag (CSRF).
check_get_actions_change_data() {
    local f out=""
    for f in $(src_php | grep '^Controller/'); do
        grep -q 'HttpGetActionInterface' "$f" || continue
        grep -q 'HttpPostActionInterface' "$f" && continue
        grep -q 'adobe-tg: ' "$f" && continue
        grep -qE '\->(save|delete|deleteById)\(' "$f" && out+="$f"$'\n'
    done
    [ -z "$out" ] || { echo "$out"; echo "GET action that saves or deletes: data changes go through POST (Adobe TG 15.7.2), or put '// adobe-tg: <why GET is safe here>' at the class"; return 1; }
}

check_xml() {
    local rc=0 f
    while IFS= read -r f; do
        xmllint --noout "$f" || rc=1
    done < <(files '*.xml' '*.xsd')
    return $rc
}

# Every locale CSV must parse, hold no duplicate phrases, and translate the same
# set of phrases as the other locales: a phrase added to one file and not the
# others shows up untranslated in those store views. en_US.csv may hold a subset
# (an untranslated phrase already renders in English).
check_i18n() {
    [ -d i18n ] || { echo "no i18n/ directory"; return 0; }
    php <<'PHP'
<?php
$files = glob('i18n/*.csv');
if (!$files) { echo "i18n/ has no CSV files\n"; exit(0); }
$keys = []; $bad = false;
foreach ($files as $file) {
    $locale = basename($file, '.csv');
    $fh = fopen($file, 'r'); $line = 0; $seen = [];
    while (($row = fgetcsv($fh, null, ',', '"', '')) !== false) {
        $line++;
        if ($row === [null]) { continue; }
        if (count($row) < 2) { echo "$file:$line: needs \"phrase\",\"translation\"\n"; $bad = true; continue; }
        if (isset($seen[$row[0]])) { echo "$file:$line: duplicate phrase \"{$row[0]}\"\n"; $bad = true; }
        $seen[$row[0]] = true;
    }
    fclose($fh);
    $keys[$locale] = $seen;
}
$all = [];
foreach ($keys as $locale => $set) { if ($locale !== 'en_US') { $all += $set; } }
foreach ($keys as $locale => $set) {
    if ($locale === 'en_US') { continue; }
    foreach (array_diff_key($all, $set) as $phrase => $_) {
        echo "i18n/$locale.csv: missing \"$phrase\"\n"; $bad = true;
    }
}
exit($bad ? 1 : 0);
PHP
}

# AGENTS.md carries the shared rules between two markers, copied verbatim from
# d-labsit/.github; CLAUDE.md imports it. A stale copy means an agent works
# from old rules, so drift fails the gate.
check_agents() {
    [ -f AGENTS.md ] || { echo "AGENTS.md missing"; return 1; }
    grep -qx '@AGENTS.md' CLAUDE.md 2>/dev/null || { echo "CLAUDE.md must contain the line @AGENTS.md"; return 1; }
    local canonical
    if [ -n "${MODULE_CI_DIR:-}" ] && [ -f "$MODULE_CI_DIR/AGENTS.md" ]; then
        canonical=$(cat "$MODULE_CI_DIR/AGENTS.md")
    else
        canonical=$(curl -fsSL "$CANONICAL_AGENTS_URL") || { echo "cannot fetch $CANONICAL_AGENTS_URL"; return 1; }
    fi
    local block='/^'"$BEGIN_MARK"'$/,/^'"$END_MARK"'$/p'
    if ! diff <(echo "$canonical" | sed -n "$block") <(sed -n "$block" AGENTS.md); then
        echo "AGENTS.md shared block differs from d-labsit/.github (diff above: < canonical, > this repo)"
        return 1
    fi
}

# --- Convention checks (soft) -------------------------------------------------

# Non-test PHP: Test/ and dev/ may do what production code must not.
src_php() { files '*.php' '*.phtml' | grep -v -e '^Test/' -e '^dev/'; }
# composer.json field via PHP (always present: composer needs it).
composer_get() {
    php -r '$j = json_decode((string) @file_get_contents(getenv("COMPOSER_JSON") ?: "composer.json"), true);
        $v = $j; foreach (array_slice($argv, 1) as $k) { $v = is_array($v) ? ($v[$k] ?? null) : null; }
        if (is_string($v)) { echo $v; }' -- "$@"
}
# A package can hold several modules in sub-directories (magento2-ga4-datalayer:
# DataLayer/, TagManager/). Module-level checks run once per module directory,
# with the package's composer.json.
module_dirs() {
    if [ -f registration.php ]; then echo .; return; fi
    files '*/registration.php' | xargs -r -n1 dirname | grep -v -e '^dev' -e '^Test' | sort -u
}
per_module() {
    local fn=$1 d rc=0 root=$PWD
    for d in $(module_dirs); do
        (cd "$d" && COMPOSER_JSON="$root/composer.json" "$fn") || rc=1
    done
    return $rc
}

is_core() { [ "$(composer_get name)" = dlabsit/module-core ]; }
needs_core() { [ -n "$(composer_get require dlabsit/module-core)" ]; }

# Without the whitelist Magento refuses to drop or rename columns and indexes later.
check_db_whitelist() {
    [ -z "$(files etc/db_schema.xml)" ] || [ -f etc/db_schema_whitelist.json ] \
        || { echo "etc/db_schema.xml without etc/db_schema_whitelist.json (bin/magento setup:db-declaration:generate-whitelist)"; return 1; }
}

# The git tag vX.Y.Z is the version; a "version" field is a second truth that drifts.
check_composer_version() {
    [ -z "$(composer_get version)" ] || { echo "composer.json has \"version\": remove it, the tag vX.Y.Z is the version"; return 1; }
}

# '*' or '>=' without an upper bound lets a breaking Core 2.0 in.
check_core_constraint() {
    local c
    c=$(composer_get require dlabsit/module-core)
    [ -n "$c" ] || return 0
    if [ "$c" = '*' ] || { [[ $c == *'>='* ]] && [[ $c != *'<'* ]]; }; then
        echo "dlabsit/module-core constraint \"$c\" has no upper bound: use ^1.2"; return 1
    fi
}

# Core defines the one dlabsit tab; modules put their sections in it.
check_config_tab() {
    is_core && return 0
    local out
    out=$(files 'etc/adminhtml/system.xml' | xargs -r grep -HnE '<tab[[:space:]]+id=' | grep -v 'id="dlabsit"')
    [ -z "$out" ] || { echo "$out"; echo "own <tab id=...> in system.xml: use <tab>dlabsit</tab> from Dlabsit_Core"; return 1; }
}

# A module with admin config that depends on Core gets an entry under Core's
# Dlabsit menu. Modules without system.xml or without Core are skipped.
check_menu() {
    is_core && return 0
    [ -n "$(files etc/adminhtml/system.xml)" ] && needs_core || return 0
    grep -qs 'parent="Dlabsit_Core::dlabsit"' etc/adminhtml/menu.xml \
        || { echo "admin config without a menu item under Dlabsit_Core::dlabsit (etc/adminhtml/menu.xml)"; return 1; }
    grep -qsE 'id="Dlabsit_[A-Za-z0-9]+::dlabsit_menu"' etc/adminhtml/menu.xml \
        || { echo "no menu heading Dlabsit_<Name>::dlabsit_menu with the module's pages and Configuration under it (see AGENTS.md, Admin menu)"; return 1; }
}

# The Core dashboard is the module list; its entry must match the module.
check_module_info() {
    is_core && return 0
    needs_core || return 0
    local di name section reg heading
    di=$(cat etc/di.xml etc/adminhtml/di.xml 2>/dev/null | tr '\n' ' ')
    [[ $di == *'Dlabsit\Core\Model\ModuleRegistry'* ]] \
        || { echo "not registered with Dlabsit\\Core\\Model\\ModuleRegistry in etc/di.xml: the module is missing from the dashboard"; return 1; }
    name=$(composer_get name)
    grep -qE "name=\"composer_name\"[^>]*>[[:space:]]*${name}[[:space:]]*<" <<<"$di" \
        || { echo "ModuleRegistry entry: composer_name is not \"$name\""; return 1; }
    reg=$(sed 's/.*Dlabsit\\Core\\Model\\ModuleRegistry//' <<<"$di" | grep -oE '<item name="name"[^>]*>[^<]*' | head -1 | sed -E 's/.*>[[:space:]]*//; s/[[:space:]]*$//')
    heading=$(tr '\n' ' ' < etc/adminhtml/menu.xml 2>/dev/null | grep -oE '<add id="Dlabsit_[A-Za-z0-9]+::dlabsit_menu"[^>]*' | grep -oE 'title="[^"]*"' | head -1 | sed -E 's/title="(.*)"/\1/')
    [ -z "$heading" ] || [ "$reg" = "$heading" ] \
        || { echo "ModuleRegistry name \"$reg\" differs from the menu heading \"$heading\": use the product name in both"; return 1; }
    ! grep -q 'name="version"' <<<"$di" \
        || { echo "ModuleRegistry entry has \"version\": remove it, Core reads the installed version from Composer"; return 1; }
    section=$(grep -oE 'name="config_section"[^>]*>[[:space:]]*[a-z0-9_]+' <<<"$di" | sed -E 's/.*>[[:space:]]*//')
    [ -z "$section" ] || grep -qs "<section id=\"$section\"" etc/adminhtml/system.xml \
        || { echo "ModuleRegistry config_section \"$section\" is not a <section> in etc/adminhtml/system.xml"; return 1; }
    [ -z "$section" ] || sed -n '/<group id="dlabsit_info"/,/<\/group>/p' etc/adminhtml/system.xml | tr '\n' ' ' \
        | grep -q 'type="expanded">1<.*InfoBanner</frontend_model>' \
        || { echo "section \"$section\" has no open Module Info group at the top: add <group id=\"dlabsit_info\" sortOrder=\"1\"> with <attribute type=\"expanded\">1</attribute> and the Core InfoBanner (magento2-core README)"; return 1; }
}

check_object_manager() {
    local out
    out=$(src_php | xargs -r grep -Hn 'ObjectManager::getInstance')
    [ -z "$out" ] || { echo "$out"; echo "ObjectManager::getInstance() outside Test/: use constructor injection"; return 1; }
}

# Level 6 is the org minimum; errors from before live in phpstan-baseline.neon.
check_phpstan_level() {
    [ "$(composer_get type)" = magento2-language ] && return 0
    [ -n "$(src_php)" ] || return 0
    local conf lvl
    conf=$(files phpstan.neon phpstan.neon.dist phpstan.dist.neon | head -1)
    [ -n "$conf" ] || { echo "no phpstan config: add phpstan.neon with level: 6 and composer.ci.json (see AGENTS.md)"; return 1; }
    lvl=$(grep -oE '^[[:space:]]*level:[[:space:]]*[0-9a-z]+' "$conf" | head -1 | sed -E 's/.*:[[:space:]]*//')
    [ "$lvl" = max ] || [ "${lvl:-0}" -ge 6 ] 2>/dev/null \
        || { echo "$conf: phpstan level ${lvl:-unset}, the minimum is 6 (existing errors go in phpstan-baseline.neon)"; return 1; }
}

# Declarative schema and patches made setup_version obsolete.
check_setup_version() {
    ! grep -qs 'setup_version' etc/module.xml || { echo "etc/module.xml has setup_version: remove it"; return 1; }
}

# check_i18n compares locales; this makes sure there is something to compare.
check_i18n_locale() {
    [ -n "$(src_php | xargs -r grep -lE '(^|[^A-Za-z0-9_])__\(')" ] || return 0
    ls i18n/*.csv 2>/dev/null | grep -qv '/en_US\.csv$' \
        || { echo "__() is used but i18n/ has no locale besides en_US (add at least el_GR.csv / nl_NL.csv)"; return 1; }
}

has_tests() { [ -n "$(files 'Test/Unit/*' phpunit.xml phpunit.xml.dist phpstan.neon phpstan.neon.dist phpstan.dist.neon)" ]; }
check_tests_wired() {
    has_tests || return 0
    [ -f dev/ci/run.sh ] || [ -f composer.ci.json ] \
        || { echo "tests not run in CI: the module has Test/Unit or a phpstan/phpunit config but no composer.ci.json (see d-labsit/.github README)"; return 1; }
}

module_run() {
    local script
    if [ -n "${MODULE_CI_DIR:-}" ] && [ -f "$MODULE_CI_DIR/ci/module-run.sh" ]; then
        script=$MODULE_CI_DIR/ci/module-run.sh
    elif [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/module-run.sh" ]; then
        script=$SCRIPT_DIR/module-run.sh
    else
        bash <(curl -fsSL "$RAW_BASE/ci/module-run.sh"); return
    fi
    bash "$script"
}

run "composer.json valid" check_composer
run "PHP syntax" check_php_lint
run "phpcs (Magento2, errors)" check_phpcs
run "XML well-formed" check_xml
run "i18n complete" check_i18n
run "AGENTS.md up to date" check_agents
soft "db_schema whitelist" check_db_whitelist
soft "no version in composer.json" check_composer_version
soft "module-core constraint bounded" check_core_constraint
soft "config under the dlabsit tab" per_module check_config_tab
soft "menu under Dlabsit_Core::dlabsit" per_module check_menu
soft "module info on the Core dashboard" per_module check_module_info
soft "no ObjectManager::getInstance()" check_object_manager
soft "no setup_version" check_setup_version
soft "i18n has a non-en_US locale" per_module check_i18n_locale
soft "tests wired into CI" check_tests_wired
soft "phpstan level 6" check_phpstan_level
soft "Magento2 warnings (severity 7+)" check_phpcs_warnings
soft "no session/cookie in cacheable code (Adobe TG 9)" check_session_in_cacheable_code
soft "around plugins have a reason (Adobe TG 4)" check_around_plugins
soft "no Helper classes" check_helper_classes
soft "GET actions do not change data (Adobe TG 15)" check_get_actions_change_data
if [ -f dev/ci/run.sh ]; then
    run "module checks (dev/ci/run.sh)" bash dev/ci/run.sh
elif [ -f composer.ci.json ] && has_tests; then
    run "module checks (ci/module-run.sh)" module_run
fi

if [ ${#warned[@]} -gt 0 ]; then
    printf 'WARNING (fatal with DLABSIT_CI_STRICT=1): %s\n' "${warned[@]}"
fi
if [ ${#failed[@]} -gt 0 ]; then
    printf 'FAILED: %s\n' "${failed[@]}"
    exit 1
fi
echo "All checks passed."

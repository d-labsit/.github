#!/usr/bin/env bash
# Quality gate shared by every d-labsit Magento module. CI runs it on each pull
# request (.github/workflows/module-ci.yml); developers and AI agents run the
# same script locally before opening one:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/d-labsit/.github/main/ci/check.sh)
#
# Run it from the module root inside a Magento dev container (PHP 8.3+,
# composer, xmllint, phpcs with the Magento2 standard). Module-specific checks
# (phpstan/phpunit with a Magento dependency set) live in dev/ci/run.sh and are
# picked up automatically.
set -uo pipefail

CANONICAL_AGENTS_URL=https://raw.githubusercontent.com/d-labsit/.github/main/AGENTS.md
BEGIN_MARK='<!-- BEGIN d-labsit shared rules -->'
END_MARK='<!-- END d-labsit shared rules -->'

failed=()
in_ci() { [ -n "${GITHUB_ACTIONS:-}" ]; }
group() { if in_ci; then echo "::group::$1"; else echo "== $1"; fi; }
endgroup() { if in_ci; then echo "::endgroup::"; fi; }
run() {
    local name=$1; shift
    group "$name"
    if "$@"; then echo "ok"; else failed+=("$name"); in_ci && echo "::error::$name failed"; fi
    endgroup
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

run "composer.json valid" check_composer
run "PHP syntax" check_php_lint
run "phpcs (Magento2, errors)" check_phpcs
run "XML well-formed" check_xml
run "i18n complete" check_i18n
run "AGENTS.md up to date" check_agents
if [ -f dev/ci/run.sh ]; then
    run "module checks (dev/ci/run.sh)" bash dev/ci/run.sh
fi

if [ ${#failed[@]} -gt 0 ]; then
    printf 'FAILED: %s\n' "${failed[@]}"
    exit 1
fi
echo "All checks passed."

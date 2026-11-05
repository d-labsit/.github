#!/usr/bin/env bash
# Front-end lint shared by the webshops (mistlampen.nl, maxprohair.gr, chicret.gr;
# Vikunja #48). Errors only, no style opinions:
#   stylelint      theme + module CSS (stylelint.config.mjs: Tailwind v4 aware)
#   html-validate  CMS pages / blocks / blog content (htmlvalidate.json)
# Run from the shop's repo root; CI checks this repo out next to it:
#   bash .dlabsit-ci/lint/frontend.sh
# Every tracked file is checked on every run (a few hundred files, seconds), so the
# gate never depends on what a PR happened to touch.
#
# Not checked, on purpose:
#   */generated/*, web/css/styles.css   Tailwind/Hyvä build output
#   */email/*                           mail templates: split header/footer fragments
#                                       and table attributes that mail clients need
# Magento directives ({{store url="x"}}, {{widget ...}}) are blanked before
# html-validate sees a file: their nested quotes are not HTML.
set -uo pipefail

LINT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
in_ci() { [ -n "${GITHUB_ACTIONS:-}" ]; }
command -v npm >/dev/null || { echo "::error::npm not found (ci-pr: workloads-ansible runner_extra_packages)"; exit 1; }

# The tools, pinned by package-lock.json, installed once per lockfile version.
key=$(sha256sum "$LINT_DIR/package-lock.json" | cut -c1-16)
tools=${FRONTEND_LINT_CACHE:-$HOME/.cache/dlabsit-frontend-lint}/$key
if [ ! -f "$tools/.installed" ]; then
    rm -rf "$tools" && mkdir -p "$tools"
    cp "$LINT_DIR/package.json" "$LINT_DIR/package-lock.json" "$tools/"
    npm ci --prefix "$tools" --no-audit --no-fund --loglevel=error \
        || { echo "::error::npm ci of the lint tools failed"; exit 1; }
    touch "$tools/.installed"
fi
bin=$tools/node_modules/.bin

# file:line:col: message -> a GitHub annotation in CI, the plain line otherwise
annotate() {
    local line
    while IFS= read -r line; do
        if in_ci && [[ $line =~ ^([^:]+):([0-9]+):([0-9]+):\ (.*)$ ]]; then
            echo "::error file=${BASH_REMATCH[1]},line=${BASH_REMATCH[2]},col=${BASH_REMATCH[3]}::${BASH_REMATCH[4]}"
        else
            echo "$line"
        fi
    done
}

failed=()
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git ls-files -- '*.css' | grep -E '^app/(design|code)/' \
    | grep -vE '/generated/|/web/css/styles\.css$' > "$tmp/css.txt"
git ls-files -- '*.html' | grep -E '^app/' | grep -v '/email/' > "$tmp/html.txt"

# copy <list> <dir> <perl expression>: the tracked files under <dir>, same relative
# paths, rewritten in place of characters so every line and column still matches
copy() {
    local f
    while IFS= read -r f; do
        mkdir -p "$2/$(dirname "$f")"
        perl -pe "$3" "$f" > "$2/$f"
    done < "$1"
}

echo "== stylelint: $(wc -l < "$tmp/css.txt") CSS files"
if [ -s "$tmp/css.txt" ]; then
    # Tailwind v4 value functions as var() of the same length: the value check skips
    # var(), and has no option to skip --spacing(6) by name
    copy "$tmp/css.txt" "$tmp/css" 's/--spacing\(/var(--tw, /g; s/--alpha\(/var(--a,/g'
    # unix formatter: path:line:col: message (rule) [error]
    # config-basedir: the config's `extends` resolves from the tools, not from the shop
    if ! (cd "$tmp/css" && xargs -a "$tmp/css.txt" -d '\n' "$bin/stylelint" \
            --config "$LINT_DIR/stylelint.config.mjs" --config-basedir "$tools" \
            --formatter unix) > "$tmp/css.out" 2>&1; then
        sed "s#^$tmp/css/##" "$tmp/css.out" | grep -v -e '^$' -e 'problems\? (' | annotate
        failed+=("stylelint")
    fi
fi

echo "== html-validate: $(wc -l < "$tmp/html.txt") HTML files"
if [ -s "$tmp/html.txt" ]; then
    # directives blanked (line numbers kept; columns after a directive shift)
    copy "$tmp/html.txt" "$tmp/html" 's/\{\{.*?\}\}/{{}}/g'
    if ! (cd "$tmp/html" && xargs -a "$tmp/html.txt" -d '\n' "$bin/html-validate" \
            --config "$LINT_DIR/htmlvalidate.json" --formatter text) > "$tmp/html.out" 2>&1; then
        annotate < "$tmp/html.out"
        failed+=("html-validate")
    fi
fi

if [ ${#failed[@]} -gt 0 ]; then
    echo "FAILED: ${failed[*]} (config: d-labsit/.github lint/)"
    exit 1
fi
echo "Front-end lint passed."

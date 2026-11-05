#!/usr/bin/env bash
# Self-test of frontend.sh: a shop that is fine passes (Tailwind v4 syntax, Magento
# directives, mail templates, build output), real mistakes fail with the right rule.
#   bash lint/test.sh
set -uo pipefail
LINT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/frontend.sh
fails=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# shop <name>: an empty git repo; put <path> <content>: a tracked file in it
shop() { mkdir -p "$work/$1" && git -C "$work/$1" init -q && cd "$work/$1" || exit 1; }
put() { mkdir -p "$(dirname "$1")" && cat > "$1" && git add "$1"; }
expect() {   # expect <rc> <text the output must contain>...
    local want=$1; shift
    local out rc
    out=$(GITHUB_ACTIONS= bash "$LINT" 2>&1); rc=$?
    if [ "$rc" != "$want" ]; then echo "FAIL $(basename "$PWD"): rc $rc, want $want"; echo "$out"; fails=$((fails + 1)); return; fi
    for t in "$@"; do
        grep -qF -- "$t" <<<"$out" || { echo "FAIL $(basename "$PWD"): output lacks '$t'"; echo "$out"; fails=$((fails + 1)); return; }
    done
    echo "ok   $(basename "$PWD") (rc $rc)"
}

T=app/design/frontend/Shop/default/web

shop good
put $T/tailwind/components/card.css <<'CSS'
@reference "../tailwind-source.css";
.card { @apply flex gap-2 sm:max-w-[90%] [&>*]:snap-start; padding-block: --spacing(6); }
.card h2 { scroll-margin-top: --spacing(24); margin-top: calc(--spacing(2) * -1); color: --alpha(var(--color-red) / 50%); }
@utility no-scrollbar { &::-webkit-scrollbar { display: none; } }
@media print { h1 { break-after: avoid; } }
CSS
put $T/tailwind/generated/hyva-source.css <<<'@import "x" source("../../"); garbage {{{'
put $T/css/styles.css <<<'.a{colr:red}.a{colr:red}'
put app/code/Shop/Setup/content/cms/about.html <<'HTML'
<div class="prose">
  <p>See <a href="{{store url="privacy-policy"}}">our privacy policy</a>.</p>
  {{widget type="Magento\Cms\Block\Widget\Block" template="widget/static_block/default.phtml" block_id="12"}}
  <img src="{{media url="wysiwyg/a.jpg"}}" alt="A lamp" width="300" height="200">
</div>
HTML
put app/design/frontend/Shop/default/Magento_Email/email/footer.html <<'HTML'
</td></tr><tr><td align="center">Shop</td></tr></table>
HTML
expect 0 "Front-end lint passed."

shop bad-css
put $T/tailwind/theme/form.css <<'CSS'
.label { colr: red; color: #ggg; }
.box { margin: 0; margin: 0; display: flexx; }
CSS
expect 1 "property-no-unknown" 'Unknown value "#ggg"' 'Unknown value "flexx"' \
    "declaration-block-no-duplicate-properties" "$T/tailwind/theme/form.css:1:28:"

shop bad-html
put app/code/Shop/Setup/content/blog/post.html <<'HTML'
<div id="intro">
  <p>Intro <b>bold</p>
</div>
<span id="intro">again</span>
HTML
expect 1 "html-validate" "app/code/Shop/Setup/content/blog/post.html:2:" "no-dup-id"

echo "$fails failure(s)"
exit $((fails > 0))

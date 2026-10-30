#!/usr/bin/env bash
# Merge guard: runs on every push to main of a d-labsit module (module-ci.yml).
# The free GitHub plan has no branch protection for private repositories, so
# nothing stops a collaborator with write access from pushing to main or
# merging without review. This script cannot block that; it makes it visible:
# the run fails and an issue is opened and assigned to D-Labs.
#
# OK when the commit came in through a pull request that
#   - was merged by a D-Labs account, or approved by one, and
#   - had a successful "module checks" run on its head commit.
#
# Env: GH_TOKEN (GITHUB_TOKEN with contents/pull-requests/checks read and
# issues write), REPO (owner/name), SHA (pushed commit), ACTOR (github.actor).
# DRY_RUN=1 prints the verdict without opening an issue.
set -uo pipefail

# D-Labs accounts that may merge and whose approval counts.
MAINTAINERS="${MERGE_GUARD_MAINTAINERS:-dlabsnl dlabsit}"
API=https://api.github.com

api() {
    curl -fsSL -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" "$API/$1"
}
# Read one value from JSON on stdin with a PHP expression on $j (php is on every runner that runs check.sh).
json() { php -r '$j = json_decode(stream_get_contents(STDIN), true); echo '"$1"';'; }
is_maintainer() { [[ " $MAINTAINERS " == *" $1 "* ]]; }

problems=()
# A module whose ci.yml does not grant pull-requests/checks read yet (older copy
# of templates/ci.yml) gets a warning instead of a red main.
pr_json=$(api "repos/$REPO/commits/$SHA/pulls") \
    || { echo "::warning::merge guard skipped: cannot read pull requests (copy permissions from d-labsit/.github templates/ci.yml)"; exit 0; }
pr=$(json '(string) ($j[0]["number"] ?? "")' <<<"$pr_json")

if [ -z "$pr" ]; then
    is_maintainer "$ACTOR" || problems+=("pushed straight to main by @$ACTOR, without a pull request")
else
    pull=$(api "repos/$REPO/pulls/$pr") \
        || { echo "::warning::merge guard skipped: cannot read pull request #$pr (copy permissions from d-labsit/.github templates/ci.yml)"; exit 0; }
    merged_by=$(json '(string) ($j["merged_by"]["login"] ?? "")' <<<"$pull")
    head=$(json '(string) ($j["head"]["sha"] ?? "")' <<<"$pull")

    if ! is_maintainer "$merged_by"; then
        reviews=$(api "repos/$REPO/pulls/$pr/reviews?per_page=100") \
            || { echo "::warning::merge guard skipped: cannot read the reviews of #$pr"; exit 0; }
        approvers=$(json 'implode(" ", array_map(fn($r) => $r["user"]["login"], array_filter($j, fn($r) => $r["state"] === "APPROVED")))' <<<"$reviews")
        ok=0
        for a in $approvers; do is_maintainer "$a" && ok=1; done
        [ $ok = 1 ] || problems+=("#$pr merged by @${merged_by:-unknown} without an approving review by D-Labs")
    fi

    # The reusable workflow's job shows up as "module / module checks".
    if runs=$(api "repos/$REPO/commits/$head/check-runs?per_page=100"); then
        checks=$(json 'implode(" ", array_map(fn($c) => (string) $c["conclusion"], array_filter($j["check_runs"] ?? [], fn($c) => str_ends_with($c["name"], "module checks"))))' <<<"$runs")
        [[ " $checks " == *" success "* ]] || problems+=("#$pr merged without a successful \"module checks\" run on its last commit (got: ${checks:-none})")
    else
        echo "::warning::merge guard: cannot read check runs (copy permissions from d-labsit/.github templates/ci.yml); CI result not verified"
    fi
fi

if [ ${#problems[@]} -eq 0 ]; then
    echo "merge guard: ok (${pr:+PR #$pr, }commit $SHA)"
    exit 0
fi

body="Commit $SHA reached \`main\` outside the agreed flow (AGENTS.md, Workflow: green CI and a D-Labs review; only D-Labs merges):"
for p in "${problems[@]}"; do echo "::error::merge guard: $p"; body+=$'\n'"- $p"; done
body+=$'\n\n'"Check the change, then revert it or confirm it here and close this issue."

if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "DRY_RUN: would open an issue:"; echo "$body"
else
    payload=$(TITLE="Merge guard: ${pr:+#$pr }${SHA:0:7} reached main without review or green CI" BODY="$body" ASSIGNEE="${MAINTAINERS%% *}" \
        php -r 'echo json_encode(["title" => getenv("TITLE"), "body" => getenv("BODY"), "assignees" => [getenv("ASSIGNEE")]]);')
    curl -fsS -o /dev/null -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
        "$API/repos/$REPO/issues" -d "$payload" || echo "::warning::merge guard: could not open the issue (needs issues: write in the module's ci.yml)"
fi
exit 1

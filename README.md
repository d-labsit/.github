# d-labsit/.github

Shared tooling for the D-Labs IT Magento 2 modules in this organization.

| Path | What |
|---|---|
| `AGENTS.md` | The rules every module follows. Each module copies the block between the markers into its own `AGENTS.md`; `CLAUDE.md` imports it with `@AGENTS.md`. |
| `ci/check.sh` | The quality gate: composer.json, PHP syntax, phpcs (Magento2, errors), XML, i18n completeness, AGENTS.md drift, plus the module's own `dev/ci/run.sh` when present. |
| `.github/workflows/module-ci.yml` | Reusable workflow that runs `ci/check.sh` on the self-hosted `ci-pr` org runner. |
| `templates/` | The `ci.yml` and `CLAUDE.md` every module carries. |

Run the checks locally from a module root (inside a Magento dev container):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/d-labsit/.github/main/ci/check.sh)
```

Changing a rule: edit `AGENTS.md` here, then update the block in every module
(CI on each module fails until its copy matches).

The runner is managed in `dlabsnl/ansible` (`workloads-ansible`, `roles/actions_runner`,
`ci-pr-d-labsit`). This repository is public so the two public modules can call
the workflow too; it holds no secrets.

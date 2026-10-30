# d-labsit/.github

Shared tooling for the D-Labs IT Magento 2 modules in this organization.

| Path | What |
|---|---|
| `AGENTS.md` | The rules every module follows. Each module copies the block between the markers into its own `AGENTS.md`; `CLAUDE.md` imports it with `@AGENTS.md`. Below the block: maintainer conventions (versions, Core constraint, PHP, tests) that are not copied. |
| `ci/check.sh` | The quality gate: composer.json, PHP syntax, phpcs (Magento2, errors), XML, i18n completeness, AGENTS.md drift, convention checks (see below), plus phpstan/phpunit. |
| `ci/merge-guard.sh` | Runs on every push to `main`: warns (failed run + issue for D-Labs) when a commit reached `main` without a pull request, green CI or a D-Labs review. See `AGENTS.md`, Merge guard. |
| `CONTRIBUTING.md`, `pull_request_template.md` | How to contribute to a module, and the checklist every pull request shows. GitHub uses them for every module in the organization without its own. |
| `ci/module-run.sh` | Default phpstan/phpunit run for a module that ships `composer.ci.json` but no `dev/ci/run.sh`. |
| `.github/workflows/module-ci.yml` | Reusable workflow that runs `ci/check.sh` on the self-hosted `ci-pr` org runner. |
| `templates/` | The `ci.yml` and `CLAUDE.md` every module carries, and `composer-dev.json`: the `require-dev` set (the same as `dlabsit/module-core`). |
| `SECURITY.md` | Org-wide security policy; GitHub shows it for every repository without its own. |

Run the checks locally from a module root (inside a Magento dev container):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/d-labsit/.github/main/ci/check.sh)
```

Changing a rule: edit `AGENTS.md` here, then update the block in every module
(CI on each module fails until its copy matches).

## phpstan and phpunit in CI

`check.sh` runs, in this order of preference:

1. the module's own `dev/ci/run.sh` (special needs, e.g. `magento2-eu-vat-vies`);
2. `ci/module-run.sh` when the module has `composer.ci.json` and `Test/Unit` or a
   phpstan/phpunit config: `composer install` from `composer.ci.json`, then
   `vendor/bin/phpstan analyse` (when `phpstan.neon[.dist]` exists) and
   `vendor/bin/phpunit` (its config file, or `Test/Unit`). phpstan runs through
   a small wrapper config that keeps its cache inside the checkout and adds
   `bitexpert/phpstan-magento` (Magento's generated factories) when that is in
   `composer.ci.json` and the module's config does not include it yet.

`composer.ci.json` takes `magento/*` from the public Mage-OS mirror, because
repo.magento.com needs credentials the runner does not have. Copy the one from
`magento2-webp` and adjust the package list and the autoload namespace. A
module with tests but neither file gets the warning "tests not run in CI".

## Convention checks: warning now, failure later

`check.sh` also checks the conventions below. For now they only warn
(`::warning::` on the pull request), so no module goes red before it is fixed;
`DLABSIT_CI_STRICT=1` makes them fail. Switch it on in
`.github/workflows/module-ci.yml` (`env:` of the check step) once every module
passes.

- `etc/db_schema.xml` without `etc/db_schema_whitelist.json`
- a `version` field in `composer.json` (the tag `vX.Y.Z` is the version)
- `dlabsit/module-core` constraint `*`, or `>=` without an upper bound (use `^1.2`)
- an own `<tab id="...">` in `system.xml` instead of Core's `dlabsit` tab
- admin config (`system.xml`) in a module that requires Core, without a menu
  item under `Dlabsit_Core::dlabsit` in `etc/adminhtml/menu.xml`
- no menu heading `Dlabsit_<Name>::dlabsit_menu` (the module's pages and Configuration
  under one heading, see `AGENTS.md`)
- a module that requires Core but is not registered with Core's
  `ModuleRegistry`, a registration whose `composer_name` differs from
  `composer.json`, that still sets `version`, or whose `config_section` is not
  in `system.xml`
- `ObjectManager::getInstance()` outside `Test/` and `dev/`
- `setup_version` in `etc/module.xml`
- `__()` in the code but no `i18n/*.csv` besides `en_US`
- unit tests or a phpstan/phpunit config that CI does not run
- no phpstan config, or a level below 6 (language packs and modules without PHP
  are skipped)
- Magento2 coding-standard warnings of severity 7 and up outside `Test/` and
  `dev/` (escaping, discouraged functions, empty catch blocks, performance);
  docblock and line-length warnings (severity 6 and lower) are not checked
- Adobe Technical Guidelines (see `AGENTS.md`, Magento architecture): session
  or cookie injected in a block, view model, model, plugin or observer; an
  around plugin without a reason; a `Helper` class; a GET action that saves or
  deletes. A justified exception carries `// adobe-tg: <reason>` on the spot

## Pinning the workflow (proposal, not done)

`templates/ci.yml` calls `module-ci.yml@main`, and `module-ci.yml` checks out
this repository's default branch for `ci/check.sh`, so a bad push here breaks
CI in every module at once. Pinning only helps with a tag, and this repository
has none yet. When D-Labs decides to pin:

1. tag a known-good commit here (`v1`, moved forward deliberately);
2. give the checkout of `d-labsit/.github` in `module-ci.yml` the same `ref:`,
   otherwise the workflow is pinned but the script is not;
3. change `@main` to `@v1` in `templates/ci.yml` and in every module's
   `.github/workflows/ci.yml`.

Until then `@main` is a deliberate choice: one place to change. That is only
safe while every change here goes through a pull request (agreed, not enforced:
no branch protection on the current plan).

The runner is managed in `dlabsnl/ansible` (`workloads-ansible`, `roles/actions_runner`,
`ci-pr-d-labsit`). This repository is public so the two public modules can call
the workflow too; it holds no secrets.

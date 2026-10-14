# d-labsit Magento modules — rules for humans and AI agents

Every module repository in the `d-labsit` organization copies the block below
into its own `AGENTS.md` (`CLAUDE.md` imports that file). This file is the
single source: change the rules here, then update the copies — CI fails a
module whose copy has drifted.

<!-- BEGIN d-labsit shared rules -->
## Shared rules for every d-labsit module

These rules come from D-Labs IT (dlabsit.nl) and apply to every change in this
repository, whether a person or an AI agent writes it. When a rule and a request
conflict, follow the rule and say so in the pull request.

### Platform baseline
- Magento 2.4 Open Source (`magento/framework` 103+), PHP 8.3 and newer.
  Code must run on both Hyvä and Luma storefronts unless the module is
  explicitly one of the two.
- Depend on `dlabsit/module-core`. Admin pages hang under the **Dlabsit** menu
  that Core provides; never add a top-level admin menu of your own.
- Store configuration lives in `etc/adminhtml/system.xml` under the `dlabsit`
  tab, with defaults in `etc/config.xml`. Behaviour a merchant may want to
  change is a setting, not a hard-coded value.
- Every admin route and config section has an ACL resource in `etc/acl.xml`.

### Code
- `declare(strict_types=1);`, typed properties, constructor injection.
  Never use the ObjectManager directly, never edit `vendor/` or Magento core.
- Prefer plugins and observers over preferences; a preference needs a reason
  in the pull request.
- Database changes only through declarative schema (`etc/db_schema.xml` plus
  `db_schema_whitelist.json`) and data/schema patches. No install/upgrade
  scripts, no raw SQL against core tables.
- Escape all output in templates (`$escaper->escapeHtml()`, `escapeHtmlAttr()`,
  `escapeUrl()`, `escapeJs()`).
- Hyvä templates: Alpine.js components must be CSP compatible (register them
  with `Alpine.data()`, no inline expressions that need `eval`), styling with
  Tailwind utility classes. Luma: RequireJS modules, no inline `<script>` logic.
- Never commit secrets, API keys, customer data or database dumps. Credentials
  are store configuration (encrypted `backend_model`), never constants.
- Do not change the `license` in `composer.json`: it is a business decision
  (MIT for free modules, proprietary for paid ones).

### Translations
- Every text a shopper or admin can see goes through `__()` (PHP/templates) or
  `translate="..."` (XML).
- When you add or change a phrase, add it to **every** `i18n/*.csv` this module
  ships, translated into that language — never copy the English text into
  another locale's file. Phrases (the first column) are English.

### Tests and checks
- Logic you add or change gets a unit test under `Test/Unit/`.
- Before opening a pull request, run the shared checks from the module root
  inside a Magento dev container (PHP 8.3+, composer, xmllint, phpcs with the
  Magento2 standard):

  ```bash
  bash <(curl -fsSL https://raw.githubusercontent.com/d-labsit/.github/main/ci/check.sh)
  ```

  It checks `composer.json`, PHP syntax, the Magento2 coding standard (errors),
  XML well-formedness, that every locale CSV has the same phrases, and this
  file. If the module has `dev/ci/run.sh` (phpstan, phpunit), it runs that too.
  CI runs exactly the same script on every pull request.

### Workflow
- Work on a branch from `main` and open a pull request; never push to `main`.
- Never create tags, releases or version bumps — D-Labs releases modules.
- A pull request needs green CI and a review by D-Labs before it is merged.
- Code, comments, commit messages and pull requests are in English. Commit
  messages follow Conventional Commits (`feat:`, `fix:`, `docs:` …) and say
  why, not only what.
<!-- END d-labsit shared rules -->

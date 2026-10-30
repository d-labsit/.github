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
- Magento 2.4 Open Source (`magento/framework` 103+), PHP 8.4 and newer.
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
  inside a Magento dev container (PHP 8.4+, composer, xmllint, phpcs with the
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

## Maintainer conventions (not copied into modules)

These sit outside the shared block on purpose: they bind D-Labs when releasing
and setting up a module, and changing the block would turn every module's CI
red until each copy is updated. `ci/check.sh` warns on most of them; once all
modules comply, CI runs with `DLABSIT_CI_STRICT=1` and the warnings fail.

- **Versions**: a release is a git tag `vX.Y.Z` (semver) with a GitHub release
  whose notes list the changes (`gh release create vX.Y.Z --generate-notes`,
  built from the Conventional Commit titles). No `version` field in
  `composer.json`: the tag is the only truth.
- **Core dependency**: `"dlabsit/module-core": "^1.2"`. Never `*` or `>=`
  without an upper bound — that lets a breaking Core 2.0 in.
- **PHP**: 8.4 is the baseline. Add 8.5 to a module's `php` constraint only
  once CI has run that module on a PHP 8.5 image.
- **Dev tools**: `require-dev` equals `templates/composer-dev.json` (the set
  `dlabsit/module-core` uses); a module with unit tests adds `phpunit/phpunit`.
- **Tests in CI**: a module with `Test/Unit` or a phpstan/phpunit config ships
  `composer.ci.json` (Magento packages from the Mage-OS mirror, see
  `magento2-webp`); CI then runs `ci/module-run.sh`. Only a module with special
  needs carries its own `dev/ci/run.sh`.
- **Schema**: `etc/db_schema.xml` always comes with `etc/db_schema_whitelist.json`;
  no `setup_version` in `etc/module.xml`.
- **Naming**: repository `d-labsit/magento2-<name>` (lowercase, hyphens, no
  `dlabsit-` inside the name: the organization already says whose it is),
  Magento module `Dlabsit_<Name>`, namespace `Dlabsit\<Name>`. A new module's
  composer name is `dlabsit/magento2-<name>`, the same text as its repository.
  A published composer name never changes: every shop that requires it would
  break. Themes (`hyva-*`) and `magento2-language-packs` are not modules and
  skip the admin rules below.
- **Admin menu** (the Mageplaza layout): Core owns the top-level menu. Each
  module adds one heading `Dlabsit_<Name>::dlabsit_menu` (title = product
  name, no action) under `Dlabsit_Core::dlabsit`; under it the module's own
  pages and, last, **Configuration** (`Dlabsit_<Name>::dlabsit_config`), which
  opens its config section. The `dlabsit_` prefix keeps Magento's global
  `.item-<id>` icon CSS off our items (see Core's `menu.xml`). A module without
  pages still gets the heading with only Configuration. A page a merchant works
  in daily (orders, requests) may appear once more in the native Magento menu
  (Sales, Catalog); configuration never does.
- **Configuration**: one section under Core's `dlabsit` tab (never an own
  `<tab id>`), id `dlabsit_<name>`, first group `general` (an `enabled` switch
  when the module can be switched off). Never rename an existing section id:
  the stored settings live under it.
- **Carriers and payment methods: in both places, one value.** The full
  settings sit in the module's `dlabsit_<name>` section; the fields a merchant
  expects next to Magento's own methods (enabled, title, price, countries,
  sort order) also appear in `carriers/<code>` (Stores > Configuration > Sales >
  Delivery Methods) or `payment/<code>` (Payment Methods). Both fields carry the
  same `<config_path>` (`carriers/<code>/active`), so switching the method off
  in one place switches it off in the other. The native group ends with a link
  to the D-Labs IT section. Courier Center and ELTA Courier are the example.
- **Order**: one number per module, used as `sortOrder` of its menu heading,
  its config section and its `sort_order` on the dashboard, so all three list
  the modules the same way: grouped by what they do, alphabetical inside a
  group. Core's own pages are 10-30. A new module takes the free number at its
  alphabetical place in its group. A package with several modules
  (`magento2-ga4-datalayer`: DataLayer + TagManager) gives each module its own
  number, heading and registration.

  | Group | Modules (number) |
  |---|---|
  | Marketplaces | eBay 100, eMAG 110, Shopflix 120, Skroutz 130, Trendyol 140 |
  | Shipping | BOX NOW 200, Courier Center 210, ELTA Courier 220, GLS Label 230 |
  | Checkout and payment | Cash on delivery and pickup 300, Hyvä Checkout 310 |
  | Marketing and feeds | GA4 Data Layer 400, Tag Manager 410, Omnisend 420, SEO 430, XML Feed 440 |
  | Legal, tax and invoices | Cookie Consent 500, EU VAT and VIES 510, EU VIES Check 520, Invoice PDF Email 530, Withdrawal button 540 |
  | Store tools | Order Numbers 600, WebP Images 610 |

- **ACL**: one root resource per module under `Dlabsit_Core::dlabsit`, one
  child per page and one for the config section; the heading uses the root.
  Never rename an existing ACL id: admin roles store them, and a renamed id
  silently takes the module away from every restricted role.
- **Module info (Core dashboard)**: every module registers with
  `Dlabsit\Core\Model\ModuleRegistry` in `etc/di.xml`: `code`, `name`,
  `description`, `composer_name` (exactly the one in `composer.json`),
  `license_tier`, `min_php_version`, `min_magento_version`, `repository_url`,
  `documentation_url`, `config_section`, `sort_order`, `depends_on`. No
  `version`: Core reads the installed version from Composer, so the dashboard
  always shows what is really deployed. CI checks that the entry exists, that
  `composer_name` matches and that `config_section` exists. A change to the
  module's name, description, requirements or section updates this entry in
  the same pull request.
- **Documentation**: `README.md` with these headings, in this order: what it
  does, requirements, installation, configuration (the admin path), usage,
  troubleshooting, licence. Changes live in the GitHub release notes of the
  tag, not in a `CHANGELOG.md`. A `LICENSE` file that matches `composer.json`.
  Screenshots and longer how-tos go in `docs/`.
- **Translations**: a module that uses `__()` ships at least one locale besides
  `en_US` (the Greek and Dutch shops: `el_GR.csv`, `nl_NL.csv`).
- **Security policy**: the org-wide `SECURITY.md` in this repository applies to
  every module without its own.

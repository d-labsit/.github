# Contributing to a D-Labs IT Magento module

Thanks for working on one of our modules. Everyone, whether a D-Labs developer, a
partner or an AI agent, works to the same rules, so a module reads the same no
matter who wrote a part of it.

## The rules

The rules live in [`AGENTS.md`](AGENTS.md); every module carries a copy and CI
fails when that copy drifts. Read the shared block before your first change.
AI agents (Claude, Codex, …) pick the file up on their own (`CLAUDE.md` imports
it).

The short version:

- Magento 2.4 Open Source, PHP 8.4+, works on Hyvä and Luma unless the module is
  for one of the two.
- `declare(strict_types=1)`, constructor injection, no ObjectManager, no
  preferences without a reason, declarative schema, escaped output.
- Every text through `__()` and in every `i18n/*.csv` the module ships,
  translated.
- **phpstan level 6.** Errors from before a module reached level 6 sit in
  `phpstan-baseline.neon`. Your change adds nothing to it; code you fix loses
  its entries.
- Logic you add or change gets a unit test in `Test/Unit/`.
- English in code, comments, commits and pull requests; Conventional Commits
  (`feat:`, `fix:`, `docs:` …) that say why.

## Your environment

Work in a Magento 2.4 development environment with PHP 8.4 (D-Labs uses
Docker stacks; ask us for one if you have none). Never on a production shop.

## Before you open a pull request

From the module root, inside that environment:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/d-labsit/.github/main/ci/check.sh)
```

This is exactly what CI runs: composer.json, PHP syntax, the Magento2 coding
standard, XML, translations, `AGENTS.md`, phpstan and the unit tests. Fix what
it reports before you push. Warnings are conventions that will become errors.

## Pull requests

1. Branch from `main`, one topic per branch. Never push to `main`.
2. Open a pull request and fill in the checklist.
3. CI must be green and D-Labs reviews it.
4. **Only D-Labs merges**, also when GitHub would let you. A commit that
   reaches `main` without green CI or a D-Labs review is flagged automatically
   (merge guard) and reverted unless D-Labs confirms it.
5. D-Labs tags and releases; never create tags, releases or version bumps
   yourself.

## Security

Found a vulnerability? Do not open an issue or pull request: see
[`SECURITY.md`](SECURITY.md).

## What and why

<!-- What does this change do for the merchant or shopper, and why is it needed? -->

## How it was tested

<!-- Shop/environment, steps, result. Screenshots for admin or storefront changes. -->

## Checklist

- [ ] `ci/check.sh` passes locally (same script as CI)
- [ ] phpstan level 6: nothing added to `phpstan-baseline.neon` (or the reason is above)
- [ ] Unit tests for logic I added or changed
- [ ] Every new text through `__()` and translated in every `i18n/*.csv`
- [ ] Works on Hyvä and Luma (or the module is for one of them)
- [ ] New settings have a default in `etc/config.xml` and an ACL resource
- [ ] README updated when behaviour or configuration changed
- [ ] No secrets, customer data or dumps in the diff

Only D-Labs merges and releases (see `CONTRIBUTING.md`).

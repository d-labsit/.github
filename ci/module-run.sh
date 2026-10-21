#!/usr/bin/env bash
# Default module checks (phpstan, phpunit) for a module without its own
# dev/ci/run.sh. ci/check.sh calls this from the module root when the module
# ships composer.ci.json: magento/* comes from the public Mage-OS mirror listed
# there, because repo.magento.com needs credentials the runner does not have.
# A module with special needs keeps its own dev/ci/run.sh, which wins.
set -euo pipefail

[ -f composer.ci.json ] || { echo "composer.ci.json missing"; exit 1; }
COMPOSER=composer.ci.json composer install --no-interaction --no-progress --ignore-platform-req=ext-*

ran=0
any_file() { local f; for f; do [ -f "$f" ] && return 0; done; return 1; }
conf=
for f in phpstan.neon phpstan.neon.dist phpstan.dist.neon; do [ -f "$f" ] && { conf=$f; break; }; done
if [ -n "$conf" ]; then
    [ -x vendor/bin/phpstan ] || { echo "$conf found but phpstan/phpstan is not in composer.ci.json"; exit 1; }
    echo "-- phpstan ($conf)"
    # Wrapper config: the cache stays inside the checkout (the runner serves
    # several unix users; a /tmp/phpstan owned by another one kills phpstan),
    # and bitexpert/phpstan-magento, when installed, teaches phpstan Magento's
    # generated factories unless the module's config already includes it.
    {
        echo "includes:"
        echo "    - $conf"
        if [ -f vendor/bitexpert/phpstan-magento/extension.neon ] && ! grep -q bitexpert "$conf"; then
            echo "    - vendor/bitexpert/phpstan-magento/extension.neon"
        fi
        echo "parameters:"
        echo "    tmpDir: .phpstan.cache"
    } > .module-ci-phpstan.neon
    vendor/bin/phpstan analyse -c .module-ci-phpstan.neon --memory-limit=1G --no-progress
    ran=1
fi

if any_file phpunit.xml phpunit.xml.dist || [ -d Test/Unit ]; then
    [ -x vendor/bin/phpunit ] || { echo "unit tests found but phpunit/phpunit is not in composer.ci.json"; exit 1; }
    echo "-- phpunit"
    # Without a config file phpunit still autoloads the module via vendor/autoload.php.
    if any_file phpunit.xml phpunit.xml.dist; then vendor/bin/phpunit; else vendor/bin/phpunit Test/Unit; fi
    ran=1
fi

[ $ran = 1 ] || { echo "composer.ci.json present but no phpstan config, phpunit config or Test/Unit"; exit 1; }

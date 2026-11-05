// Shared stylelint config for the Hyvä (Tailwind v4) theme sources of our webshops.
// Errors only: stylelint-config-recommended = "possible errors" (CSS syntax errors, unknown
// properties and units, duplicate declarations, empty blocks, invalid hex colours, ...),
// no style opinions. The exceptions below are Tailwind v4 syntax, not mistakes.
const tailwindAtRules = [
  'tailwind', 'apply', 'layer', 'config', 'theme', 'screen', 'variant', 'variants',
  'utility', 'source', 'plugin', 'custom-variant', 'reference', 'responsive',
];

export default {
  extends: ['stylelint-config-recommended'],
  rules: {
    'at-rule-no-unknown': [true, { ignoreAtRules: tailwindAtRules }],
    'at-rule-prelude-no-invalid': [true, { ignoreAtRules: tailwindAtRules }],
    'nesting-selector-no-missing-scoping-root': [true, { ignoreAtRules: tailwindAtRules }],
    'function-no-unknown': [true, { ignoreFunctions: ['theme', 'screen', '--alpha', '--spacing', '--theme'] }],
    // declaration-property-value-no-unknown (invalid hex colours, `display: flexx`, ...)
    // stays on: frontend.sh hands Tailwind's --spacing()/--alpha() to stylelint as var()
    // Tailwind's @import "x" source(...) / layer(...) and Hyvä's generated imports
    'import-notation': null,
    'no-invalid-position-at-import-rule': null,
    // specificity order across component files is Tailwind's job (@layer), not a bug
    'no-descending-specificity': null,
  },
};

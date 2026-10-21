# Security policy

This policy covers every repository in the `d-labsit` organization that has no
`SECURITY.md` of its own.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately:

- **GitHub**: use *Report a vulnerability* on the repository's **Security** tab
  (private vulnerability reporting), so the discussion stays confidential until
  a fix ships.
- **Email**: `security@dlabsit.nl`, if the repository is not visible to you or
  the GitHub form is not available.

Include what is affected (module and version, Magento version, Hyvä or Luma),
how to reproduce it, and the impact you expect.

## Supported versions

Security fixes go into the latest minor release of each module and are released
as a patch version (`vX.Y.Z`). Reporters are credited in the release notes
unless they ask not to be.

## Out of scope

Vulnerabilities in Magento itself or in third-party modules (report those
upstream) and the configuration of individual shops or servers.

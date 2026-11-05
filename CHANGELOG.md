# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-11-04

First release on the PowerShell Gallery. No behaviour changed from the source tree that
preceded it; this release fixes the package metadata and freezes the public surface.

### Added

- Five read-only identity-hygiene checks over Microsoft Graph:
  - `Get-EhStaleAccount` — accounts with no recent sign-in.
  - `Get-EhPrivilegedWithoutMfa` — admin-role members with no strong authentication
    method registered.
  - `Get-EhRoleAssignment` — privileged role assignments, permanent versus eligible
    (PIM).
  - `Get-EhConditionalAccessGap` — report-only policies, disabled policies, and excluded
    users.
  - `Get-EhInactiveLicense` — licenses on inactive accounts, with the recoverable monthly
    cost. A SKU with no price supplied contributes zero; the module never invents a price.
- `Microsoft.Graph.Authentication` declared as a required module, so installing from the
  Gallery resolves the one dependency the module actually has.
- Release notes, discovery tags and a package description in the manifest.

### Security

- No write path exists anywhere in the module. `Tests/EntraHygiene.Tests.ps1` fails the
  build if a Graph write verb (`POST`, `PATCH`, `PUT`, `DELETE`) appears in any file, so
  "read-only" is a verified property rather than a promise.
- The module never handles credentials. It uses the caller's existing `Connect-MgGraph`
  session, which leaves the choice of identity and scopes with the operator.

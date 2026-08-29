# EntraHygiene

A read-only PowerShell module for the recurring identity-hygiene checks every Microsoft
365 administrator should run and almost none do. It **never writes** to the tenant, and a
test enforces that.

Five checks, one per thing that quietly rots in a tenant:

| Cmdlet | Finds |
|---|---|
| `Get-EhStaleAccount` | Accounts with no recent sign-in — forgotten service accounts, people who left |
| `Get-EhPrivilegedWithoutMfa` | Admin-role members with no strong authentication method |
| `Get-EhRoleAssignment` | Privileged role assignments, **permanent vs eligible (PIM)** |
| `Get-EhConditionalAccessGap` | Report-only policies left forever, disabled policies, excluded users |
| `Get-EhInactiveLicense` | Licenses on inactive accounts, with the recoverable monthly cost |

## Why these, and why read-only

Each of these is a standing risk that nobody looks at. A privileged account without strong
MFA is high privilege behind the lowest possible bar. A **permanent** role assignment is
24/7 admin access — if that account is compromised, the attacker is already an admin with
nothing to activate. A report-only Conditional Access policy that was never turned on
protects nothing. And every license on an unused account is money leaving every month.

The module only ever reads. There is no write path anywhere in it, and
`Tests/EntraHygiene.Tests.ps1` fails if a Graph write verb (`POST/PATCH/PUT/DELETE`)
appears in any file. "Read-only" is a verified property here, not a promise.

## Install and use

```powershell
# Auth is yours to control — the module never touches credentials.
Connect-MgGraph -Scopes @(
  'AuditLog.Read.All','User.Read.All','RoleManagement.Read.Directory',
  'UserAuthenticationMethod.Read.All','Policy.Read.All'
)

Import-Module ./EntraHygiene/EntraHygiene.psd1

Get-EhStaleAccount -DiasInactividad 90 | Where-Object Habilitada
Get-EhPrivilegedWithoutMfa
Get-EhRoleAssignment | Where-Object Tipo -eq 'Permanente'
```

Every cmdlet **returns objects, not text**, so they compose in the pipeline:

```
Upn                    Nombre     UltimoLogin           DiasInactiva Habilitada
---                    ------     -----------           ------------ ----------
svc-backup@contoso.com Svc Backup 2026-01-01 21:49:38            240       True
ex-becario@contoso.com Ex Becario                                          True
```

```powershell
# Cost of licenses on stale accounts, most expensive first:
Get-EhInactiveLicense -CostosPorSku @{ 'ENTERPRISEPREMIUM' = 57.0 } |
  Sort-Object CostoMensualEstimado -Descending
```

## Permissions — all read-only

The module relies on your existing `Connect-MgGraph` session, so it never handles secrets.
The minimum delegated (or application) scopes, per cmdlet, are documented in each
function's comment-based help (`Get-Help Get-EhStaleAccount -Full`). In short:
`AuditLog.Read.All`, `User.Read.All`, `RoleManagement.Read.Directory`,
`UserAuthenticationMethod.Read.All`, `Policy.Read.All`.

## Design notes

- **Objects, not formatted text** — the output is data, so `Where-Object`, `Sort-Object`,
  `Export-Csv` all work. Formatting is the caller's choice.
- **Approved verbs, comment-based help** on every function.
- **Costs are never invented.** `Get-EhInactiveLicense` only sums prices you supply in
  `-CostosPorSku`; an unpriced SKU contributes zero rather than a made-up number.
- **Testable without a tenant.** Every cmdlet takes an `-InvokeGraph` seam that the Pester
  suite fills with a mock, so tests run with no tenant, no credentials, and no network.

## Limitations

- Sign-in–activity fields require the right license/permission; where Graph returns no
  activity, an account with no data is reported as *stale* (no sign-in on record) — verify
  before acting on it.
- `Get-EhConditionalAccessGap` flags patterns worth a second look; it does not decide
  whether a given policy design is correct.
- These are point-in-time reads, not a monitor. Run them on a schedule and diff the output.

## Development

```powershell
Invoke-ScriptAnalyzer -Path ./EntraHygiene -Recurse -Severity Error,Warning
Invoke-Pester -Path ./Tests
```

CI runs both on every push.

## License

MIT — see [LICENSE](LICENSE).

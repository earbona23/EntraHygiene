function Get-EhInactiveLicense {
    <#
    .SYNOPSIS
        Reporta licencias asignadas a cuentas inactivas, con el impacto en costo.

    .DESCRIPTION
        Cada licencia sobre una cuenta que no se usa es dinero que se va todos los meses
        sin que nadie lo note. Esta función cruza las cuentas obsoletas
        (ver Get-EhStaleAccount) con sus licencias asignadas y estima el gasto
        recuperable si se liberan.

        El costo mensual por SKU no lo sabe Graph: lo pasás vos en -CostosPorSku, porque
        depende de tu contrato. Sin ese dato, la función igual lista las licencias pero
        deja el costo en cero — nunca inventa un precio.

        SOLO LECTURA. Devuelve objetos.

        Permisos de Graph mínimos: User.Read.All, AuditLog.Read.All (solo lectura).

    .PARAMETER DiasInactividad
        Umbral para considerar una cuenta obsoleta. Por defecto 90.

    .PARAMETER CostosPorSku
        Hashtable de skuPartNumber -> costo mensual. Opcional.

    .PARAMETER InvokeGraph
        Solo para pruebas: inyecta un mock de Invoke-EhGraph.

    .OUTPUTS
        PSCustomObject con: Upn, DiasInactiva, Licencias, CostoMensualEstimado
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(1, 3650)]
        [int] $DiasInactividad = 90,

        [hashtable] $CostosPorSku = @{},

        [scriptblock] $InvokeGraph
    )

    $leer = if ($InvokeGraph) { $InvokeGraph } else { { param($u) Invoke-EhGraph -Uri $u } }
    $limite = (Get-Date).ToUniversalTime().AddDays(-$DiasInactividad)

    $uri = '/users?$select=userPrincipalName,signInActivity,assignedLicenses,licenseAssignmentStates'
    $usuarios = & $leer $uri

    foreach ($u in $usuarios) {
        $licencias = @($u.licenseAssignmentStates | ForEach-Object { $_.skuId } | Where-Object { $_ })
        if ($licencias.Count -eq 0) { continue }

        $ultimo = $u.signInActivity.lastSignInDateTime
        $fecha = if ($ultimo) { [datetime]::Parse($ultimo).ToUniversalTime() } else { $null }
        $obsoleta = (-not $fecha) -or ($fecha -lt $limite)
        if (-not $obsoleta) { continue }

        $skus = @($u.licenseAssignmentStates | ForEach-Object { $_.skuId })
        $costo = 0.0
        foreach ($s in $skus) {
            if ($CostosPorSku.ContainsKey($s)) { $costo += [double]$CostosPorSku[$s] }
        }

        $dias = if ($fecha) { [int]((Get-Date).ToUniversalTime() - $fecha).TotalDays } else { $null }
        [pscustomobject]@{
            Upn                  = $u.userPrincipalName
            DiasInactiva         = $dias
            Licencias            = ($skus -join ', ')
            CostoMensualEstimado = [math]::Round($costo, 2)
        }
    }
}

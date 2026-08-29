function Get-EhStaleAccount {
    <#
    .SYNOPSIS
        Encuentra cuentas de usuario sin inicio de sesión reciente.

    .DESCRIPTION
        Cuentas sin actividad de inicio de sesión en el período indicado. Son la
        superficie de ataque que nadie vigila: cuentas de servicio olvidadas, personas
        que dejaron la organización, becarios de un proyecto que terminó. Cada una es
        una credencial válida que a nadie le importa — y por eso ideal para un atacante.

        SOLO LECTURA. Devuelve OBJETOS (no texto), para que puedas filtrarlos,
        ordenarlos o exportarlos con el pipeline de PowerShell.

        Permiso de Graph mínimo: AuditLog.Read.All y User.Read.All (solo lectura).

    .PARAMETER DiasInactividad
        Umbral de días sin inicio de sesión para considerar una cuenta obsoleta.
        Por defecto 90.

    .PARAMETER InvokeGraph
        Solo para pruebas: inyecta un mock de Invoke-EhGraph.

    .EXAMPLE
        Get-EhStaleAccount -DiasInactividad 60 | Where-Object Habilitada

    .OUTPUTS
        PSCustomObject con: Upn, Nombre, UltimoLogin, DiasInactiva, Habilitada
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(1, 3650)]
        [int] $DiasInactividad = 90,

        [scriptblock] $InvokeGraph
    )

    $leer = if ($InvokeGraph) { $InvokeGraph } else { { param($u) Invoke-EhGraph -Uri $u } }
    $limite = (Get-Date).ToUniversalTime().AddDays(-$DiasInactividad)

    $uri = '/users?$select=userPrincipalName,displayName,accountEnabled,signInActivity'
    $usuarios = & $leer $uri

    foreach ($u in $usuarios) {
        $ultimo = $u.signInActivity.lastSignInDateTime
        $fecha = $null
        if ($ultimo) { $fecha = [datetime]::Parse($ultimo).ToUniversalTime() }

        # Sin registro de sign-in O con último inicio anterior al límite.
        $obsoleta = (-not $fecha) -or ($fecha -lt $limite)
        if (-not $obsoleta) { continue }

        $dias = if ($fecha) { [int]((Get-Date).ToUniversalTime() - $fecha).TotalDays } else { $null }
        [pscustomobject]@{
            Upn          = $u.userPrincipalName
            Nombre       = $u.displayName
            UltimoLogin  = $fecha
            DiasInactiva = $dias
            Habilitada   = [bool]$u.accountEnabled
        }
    }
}

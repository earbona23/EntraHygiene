function Get-EhPrivilegedWithoutMfa {
    <#
    .SYNOPSIS
        Encuentra cuentas con roles privilegiados que no tienen métodos de
        autenticación fuertes registrados.

    .DESCRIPTION
        Una cuenta de administrador sin MFA fuerte es la combinación más peligrosa de
        un tenant: privilegio alto y la barrera de entrada más baja. Esta función cruza
        los miembros de roles de directorio con sus métodos de autenticación y marca a
        quienes solo tienen contraseña (o métodos débiles como SMS).

        SOLO LECTURA. Devuelve objetos.

        Permisos de Graph mínimos (solo lectura):
          RoleManagement.Read.Directory, UserAuthenticationMethod.Read.All

    .PARAMETER InvokeGraph
        Solo para pruebas: inyecta un mock de Invoke-EhGraph.

    .OUTPUTS
        PSCustomObject con: Upn, Roles, MetodosFuertes, MetodosDebiles
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [scriptblock] $InvokeGraph
    )

    $leer = if ($InvokeGraph) { $InvokeGraph } else { { param($u) Invoke-EhGraph -Uri $u } }

    # Métodos considerados FUERTES (resistentes a phishing o basados en app/FIDO).
    $fuertes = @(
        '#microsoft.graph.fido2AuthenticationMethod'
        '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'
        '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod'
        '#microsoft.graph.softwareOathAuthenticationMethod'
    )

    $roles = & $leer '/directoryRoles'
    # Mapa upn -> lista de roles, para no consultar dos veces al mismo usuario.
    $porUsuario = @{}
    foreach ($rol in $roles) {
        $miembros = & $leer "/directoryRoles/$($rol.id)/members?`$select=id,userPrincipalName"
        foreach ($m in $miembros) {
            if (-not $m.userPrincipalName) { continue }
            if (-not $porUsuario.ContainsKey($m.id)) {
                $porUsuario[$m.id] = [pscustomobject]@{ Upn = $m.userPrincipalName; Roles = @() }
            }
            $porUsuario[$m.id].Roles += $rol.displayName
        }
    }

    foreach ($id in $porUsuario.Keys) {
        $entrada = $porUsuario[$id]
        $metodos = & $leer "/users/$id/authentication/methods"
        $tipos = @($metodos | ForEach-Object { $_.'@odata.type' })
        $conFuerte = @($tipos | Where-Object { $fuertes -contains $_ }).Count
        $debiles = @($tipos | Where-Object { $fuertes -notcontains $_ }).Count

        if ($conFuerte -eq 0) {
            [pscustomobject]@{
                Upn            = $entrada.Upn
                Roles          = ($entrada.Roles -join ', ')
                MetodosFuertes = $conFuerte
                MetodosDebiles = $debiles
            }
        }
    }
}

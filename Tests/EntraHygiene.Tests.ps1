# Tests de EntraHygiene con Microsoft Graph MOCKEADO.
# No requieren un tenant, credenciales ni red. El parámetro -InvokeGraph de cada cmdlet
# reemplaza a Invoke-EhGraph, que ya DESENVUELVE la colección .value: por eso los mocks
# devuelven el ARREGLO de items directamente, no el sobre { value = ... } de Graph.
# La paginación y el desenvuelto los cubre aparte el bloque 'Invoke-EhGraph'.

BeforeAll {
    Import-Module "$PSScriptRoot/../EntraHygiene/EntraHygiene.psd1" -Force
}

Describe 'Get-EhStaleAccount' {
    It 'marca cuentas sin login reciente y sin registro de sign-in' {
        $mock = {
            param($u)
            , @(
                @{ userPrincipalName = 'activo@x.com'; displayName = 'Activo'; accountEnabled = $true
                    signInActivity   = @{ lastSignInDateTime = (Get-Date).ToUniversalTime().ToString('o') } }
                @{ userPrincipalName = 'viejo@x.com'; displayName = 'Viejo'; accountEnabled = $true
                    signInActivity   = @{ lastSignInDateTime = (Get-Date).AddDays(-200).ToUniversalTime().ToString('o') } }
                @{ userPrincipalName = 'nunca@x.com'; displayName = 'Nunca'; accountEnabled = $false
                    signInActivity   = @{ lastSignInDateTime = $null } }
            )
        }
        $r = Get-EhStaleAccount -DiasInactividad 90 -InvokeGraph $mock
        $upns = @($r.Upn)
        $upns | Should -Contain 'viejo@x.com'
        $upns | Should -Contain 'nunca@x.com'
        $upns | Should -Not -Contain 'activo@x.com'
    }

    It 'devuelve objetos, no texto' {
        $mock = { param($u) , @(
                @{ userPrincipalName = 'v@x.com'; displayName = 'V'; accountEnabled = $true
                    signInActivity   = @{ lastSignInDateTime = $null } }) }
        $r = Get-EhStaleAccount -InvokeGraph $mock
        $r[0] | Should -BeOfType [pscustomobject]
        $r[0].PSObject.Properties.Name | Should -Contain 'DiasInactiva'
    }
}

Describe 'Get-EhPrivilegedWithoutMfa' {
    It 'marca al admin con solo contraseña y no al que tiene un método fuerte' {
        $mock = {
            param($u)
            switch -Wildcard ($u) {
                '*/directoryRoles' {
                    , @(@{ id = 'r1'; displayName = 'Administrador Global' })
                }
                '*/directoryRoles/r1/members*' {
                    , @(
                        @{ id = 'u1'; userPrincipalName = 'sinmfa@x.com' }
                        @{ id = 'u2'; userPrincipalName = 'conmfa@x.com' }
                    )
                }
                '*/users/u1/authentication/methods' {
                    , @(@{ '@odata.type' = '#microsoft.graph.passwordAuthenticationMethod' })
                }
                '*/users/u2/authentication/methods' {
                    , @(
                        @{ '@odata.type' = '#microsoft.graph.passwordAuthenticationMethod' }
                        @{ '@odata.type' = '#microsoft.graph.fido2AuthenticationMethod' }
                    )
                }
                default { , @() }
            }
        }
        $r = Get-EhPrivilegedWithoutMfa -InvokeGraph $mock
        @($r.Upn) | Should -Be @('sinmfa@x.com')
        $r[0].Roles | Should -Be 'Administrador Global'
    }
}

Describe 'Get-EhRoleAssignment' {
    It 'distingue permanentes de elegibles' {
        $mock = {
            param($u)
            if ($u -like '*roleAssignmentScheduleInstances*') {
                , @(@{ principal = @{ displayName = 'Ana' }; roleDefinition = @{ displayName = 'Admin' } })
            }
            elseif ($u -like '*roleEligibilityScheduleInstances*') {
                , @(@{ principal = @{ displayName = 'Luis' }; roleDefinition = @{ displayName = 'Lector' } })
            }
            else { , @() }
        }
        $r = Get-EhRoleAssignment -InvokeGraph $mock
        ($r | Where-Object Tipo -EQ 'Permanente').Principal | Should -Be 'Ana'
        ($r | Where-Object Tipo -EQ 'Elegible').Principal | Should -Be 'Luis'
    }
}

Describe 'Get-EhConditionalAccessGap' {
    It 'marca solo-reporte, deshabilitada y usuarios excluidos' {
        $mock = {
            param($u)
            , @(
                @{ displayName = 'Bloqueo legado'; state = 'enabledForReportingButNotEnforced'
                    conditions = @{ users = @{ excludeUsers = @() } } }
                @{ displayName = 'MFA admins'; state = 'enabled'
                    conditions = @{ users = @{ excludeUsers = @('u1', 'u2') } } }
                @{ displayName = 'Vieja'; state = 'disabled'
                    conditions = @{ users = @{ excludeUsers = @() } } }
            )
        }
        $r = Get-EhConditionalAccessGap -InvokeGraph $mock
        @($r.Brecha) | Should -Contain 'Solo reporte'
        @($r.Brecha) | Should -Contain 'Deshabilitada'
        ($r | Where-Object Brecha -EQ 'Usuarios excluidos').Detalle | Should -Match '2 usuario'
    }
}

Describe 'Get-EhInactiveLicense' {
    It 'estima costo solo con los precios provistos y nunca inventa uno' {
        $mock = {
            param($u)
            , @(
                @{ userPrincipalName = 'viejo@x.com'
                    signInActivity          = @{ lastSignInDateTime = (Get-Date).AddDays(-200).ToUniversalTime().ToString('o') }
                    licenseAssignmentStates = @(@{ skuId = 'E5' }, @{ skuId = 'DESCONOCIDO' }) }
            )
        }
        $r = Get-EhInactiveLicense -InvokeGraph $mock -CostosPorSku @{ 'E5' = 57.0 }
        $r[0].CostoMensualEstimado | Should -Be 57.0   # solo E5; el SKU sin precio no suma
    }

    It 'sin tabla de costos deja el costo en cero, no lo inventa' {
        $mock = {
            param($u)
            , @(
                @{ userPrincipalName = 'v@x.com'
                    signInActivity          = @{ lastSignInDateTime = $null }
                    licenseAssignmentStates = @(@{ skuId = 'E3' }) }
            )
        }
        $r = Get-EhInactiveLicense -InvokeGraph $mock
        $r[0].CostoMensualEstimado | Should -Be 0
    }
}

Describe 'Invoke-EhGraph' {
    It 'sigue @odata.nextLink y concatena todas las páginas' {
        # Simula dos páginas de Graph a través del seam -InvokeCommand.
        InModuleScope EntraHygiene {
            $paginas = @{
                'https://graph.microsoft.com/v1.0/users' = @{
                    value            = @(@{ id = 1 })
                    '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?page=2'
                }
                'https://graph.microsoft.com/v1.0/users?page=2' = @{
                    value = @(@{ id = 2 }, @{ id = 3 })
                }
            }
            $fake = { param($u) $paginas[$u] }
            $r = Invoke-EhGraph -Uri '/users' -InvokeCommand $fake
            @($r).Count | Should -Be 3
            @($r.id) | Should -Be @(1, 2, 3)
        }
    }
}

Describe 'Garantía de solo lectura' {
    It 'ninguna función del módulo escribe en Graph' {
        $archivos = Get-ChildItem "$PSScriptRoot/../EntraHygiene" -Recurse -Filter *.ps1
        $ofensas = @()
        foreach ($f in $archivos) {
            $contenido = Get-Content $f.FullName -Raw
            if ($contenido -match "-Method\s+['`"]?(POST|PATCH|PUT|DELETE)") {
                $ofensas += $f.Name
            }
        }
        $ofensas | Should -BeNullOrEmpty
    }
}

function Get-EhRoleAssignment {
    <#
    .SYNOPSIS
        Lista las asignaciones de roles privilegiados, distinguiendo permanentes de
        elegibles (PIM).

    .DESCRIPTION
        En un tenant sano, el acceso privilegiado es ELEGIBLE (se activa por tiempo
        limitado vía PIM), no PERMANENTE. Una asignación permanente a un rol de alto
        privilegio es acceso de pie las 24 horas: si esa cuenta se ve comprometida, el
        atacante ya es administrador, sin activar nada. Esta función las separa para que
        veas cuáles conviene convertir a elegibles.

        SOLO LECTURA. Devuelve objetos.

        Permiso de Graph mínimo: RoleManagement.Read.Directory (solo lectura).

    .PARAMETER InvokeGraph
        Solo para pruebas: inyecta un mock de Invoke-EhGraph.

    .OUTPUTS
        PSCustomObject con: Principal, Rol, Tipo (Permanente/Elegible)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [scriptblock] $InvokeGraph
    )

    $leer = if ($InvokeGraph) { $InvokeGraph } else { { param($u) Invoke-EhGraph -Uri $u } }

    $emitir = {
        param($items, $tipo)
        foreach ($a in $items) {
            [pscustomobject]@{
                Principal = $a.principal.displayName ?? $a.principalId
                Rol       = $a.roleDefinition.displayName ?? $a.roleDefinitionId
                Tipo      = $tipo
            }
        }
    }

    $expand = '?$expand=principal,roleDefinition'
    $permanentes = & $leer "/roleManagement/directory/roleAssignmentScheduleInstances$expand"
    $elegibles = & $leer "/roleManagement/directory/roleEligibilityScheduleInstances$expand"

    & $emitir $permanentes 'Permanente'
    & $emitir $elegibles 'Elegible'
}

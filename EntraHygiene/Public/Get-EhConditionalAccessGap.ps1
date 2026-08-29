function Get-EhConditionalAccessGap {
    <#
    .SYNOPSIS
        Revisa las políticas de acceso condicional en busca de brechas comunes.

    .DESCRIPTION
        El acceso condicional es tan fuerte como sus excepciones. Esta función marca tres
        brechas que se pagan caras:
          - Políticas en modo SOLO REPORTE que quedaron ahí y nunca se activaron.
          - Políticas DESHABILITADAS (existen pero no protegen nada).
          - Usuarios EXCLUIDOS de una política: cada exclusión es un hueco deliberado que
            hay que poder justificar.

        No juzga si una política es correcta —eso depende del diseño de cada quien—; marca
        lo que merece una segunda mirada.

        SOLO LECTURA. Devuelve objetos.

        Permiso de Graph mínimo: Policy.Read.All (solo lectura).

    .PARAMETER InvokeGraph
        Solo para pruebas: inyecta un mock de Invoke-EhGraph.

    .OUTPUTS
        PSCustomObject con: Politica, Brecha, Detalle
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [scriptblock] $InvokeGraph
    )

    $leer = if ($InvokeGraph) { $InvokeGraph } else { { param($u) Invoke-EhGraph -Uri $u } }
    $politicas = & $leer '/identity/conditionalAccess/policies'

    foreach ($p in $politicas) {
        switch ($p.state) {
            'enabledForReportingButNotEnforced' {
                [pscustomobject]@{
                    Politica = $p.displayName
                    Brecha   = 'Solo reporte'
                    Detalle  = 'La política evalúa pero NO bloquea. Revisar si debería estar activa.'
                }
            }
            'disabled' {
                [pscustomobject]@{
                    Politica = $p.displayName
                    Brecha   = 'Deshabilitada'
                    Detalle  = 'La política existe pero no protege nada.'
                }
            }
        }

        $excluidos = @($p.conditions.users.excludeUsers)
        if ($excluidos.Count -gt 0) {
            [pscustomobject]@{
                Politica = $p.displayName
                Brecha   = 'Usuarios excluidos'
                Detalle  = "$($excluidos.Count) usuario(s) excluido(s) de esta política."
            }
        }
    }
}

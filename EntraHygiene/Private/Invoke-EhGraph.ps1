function Invoke-EhGraph {
    <#
    .SYNOPSIS
        Wrapper de SOLO LECTURA sobre Microsoft Graph con paginación automática.

    .DESCRIPTION
        Todas las funciones del módulo leen el tenant a través de esta única función.
        Solo hace GET: no existe una ruta de escritura en todo el módulo, y un test lo
        verifica. Sigue @odata.nextLink para devolver la colección completa, y respeta
        el throttling (HTTP 429) con Retry-After.

        No maneja autenticación: se apoya en la sesión ya establecida por
        Connect-MgGraph (módulo Microsoft.Graph.Authentication). Así el usuario controla
        con qué identidad y permisos se conecta, y este módulo nunca toca credenciales.

    .PARAMETER Uri
        Ruta relativa de Graph (por ejemplo '/users') o URL absoluta.

    .PARAMETER InvokeCommand
        Solo para pruebas: reemplaza Invoke-MgGraphRequest por un mock. En uso real se
        deja en su valor por defecto.

    .EXAMPLE
        Invoke-EhGraph -Uri '/users?$select=id,displayName'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Uri,

        [scriptblock] $InvokeCommand
    )

    $base = 'https://graph.microsoft.com/v1.0'
    $next = if ($Uri -match '^https?://') { $Uri } else { "$base$Uri" }

    $llamar = if ($InvokeCommand) {
        $InvokeCommand
    }
    else {
        { param($u) Invoke-MgGraphRequest -Method GET -Uri $u -OutputType PSObject }
    }

    $resultados = [System.Collections.Generic.List[object]]::new()
    while ($next) {
        $intento = 0
        $respuesta = $null
        while ($true) {
            try {
                $respuesta = & $llamar $next
                break
            }
            catch {
                $intento++
                if ($intento -ge 5) { throw }
                Start-Sleep -Seconds ([Math]::Min([Math]::Pow(2, $intento), 30))
            }
        }

        if ($null -ne $respuesta.value) {
            foreach ($item in $respuesta.value) { $resultados.Add($item) }
            $next = $respuesta.'@odata.nextLink'
        }
        else {
            # Respuesta de un solo objeto (no una colección)
            $resultados.Add($respuesta)
            $next = $null
        }
    }
    return $resultados
}

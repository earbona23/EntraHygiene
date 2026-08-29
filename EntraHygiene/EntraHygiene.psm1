# Cargador del módulo: importa las funciones privadas (helpers) y públicas (cmdlets),
# y exporta solo las públicas. Este patrón mantiene la superficie del módulo explícita.

$publicas = @(Get-ChildItem -Path "$PSScriptRoot/Public/*.ps1" -ErrorAction SilentlyContinue)
$privadas = @(Get-ChildItem -Path "$PSScriptRoot/Private/*.ps1" -ErrorAction SilentlyContinue)

foreach ($archivo in @($privadas + $publicas)) {
    try {
        . $archivo.FullName
    }
    catch {
        Write-Error "No se pudo cargar $($archivo.FullName): $_"
    }
}

Export-ModuleMember -Function $publicas.BaseName

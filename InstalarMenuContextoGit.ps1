param(
    [string]$ExecutablePath,
    [switch]$Uninstall
)

$verbKey = 'HKCU:\Software\Classes\Directory\shell\GerenciadorDePastasGit'
$commandKey = Join-Path $verbKey 'command'

if ($Uninstall) {
    Remove-Item -LiteralPath $verbKey -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'Context menu entry removed for the current Windows user.'
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
    throw 'Pass -ExecutablePath with the full path to GerenciadorDePastas.exe.'
}

$resolvedExe = (Resolve-Path -LiteralPath $ExecutablePath -ErrorAction Stop).Path
if ([System.IO.Path]::GetFileName($resolvedExe) -ne 'GerenciadorDePastas.exe') {
    throw 'ExecutablePath must point to GerenciadorDePastas.exe.'
}

New-Item -Path $commandKey -Force | Out-Null
Set-Item -LiteralPath $verbKey -Value 'Abrir Gerenciador de Pastas Git'
Set-ItemProperty -LiteralPath $verbKey -Name 'Icon' -Value $resolvedExe
Set-Item -LiteralPath $commandKey -Value ('"{0}" "%1"' -f $resolvedExe)

Write-Host 'Context menu entry installed for the current Windows user.'
Write-Host 'Right-click a folder to open it as the search root.'

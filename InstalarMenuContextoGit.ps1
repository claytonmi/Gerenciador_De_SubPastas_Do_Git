param(
    [string]$ExecutablePath,
    [switch]$Uninstall
)

$folderVerbKey = 'HKCU:\Software\Classes\Directory\shell\GerenciadorDePastasGit'
$backgroundVerbKey = 'HKCU:\Software\Classes\Directory\Background\shell\GerenciadorDePastasGit'

if ($Uninstall) {
    Remove-Item -LiteralPath $folderVerbKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $backgroundVerbKey -Recurse -Force -ErrorAction SilentlyContinue
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

foreach ($entry in @(
    @{ VerbKey = $folderVerbKey; Argument = '%1' },
    @{ VerbKey = $backgroundVerbKey; Argument = '%V' }
)) {
    $commandKey = Join-Path $entry.VerbKey 'command'
    New-Item -Path $commandKey -Force | Out-Null
    Set-Item -LiteralPath $entry.VerbKey -Value 'Abrir Gerenciador de Pastas Git'
    Set-ItemProperty -LiteralPath $entry.VerbKey -Name 'Icon' -Value $resolvedExe
    Set-Item -LiteralPath $commandKey -Value ('"{0}" "{1}"' -f $resolvedExe, $entry.Argument)
}

Write-Host 'Context menu entry installed for the current Windows user.'
Write-Host 'Right-click a folder or its background to open it as the search root.'

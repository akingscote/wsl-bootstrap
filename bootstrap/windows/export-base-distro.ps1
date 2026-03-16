[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)]
    [string]$SourceDistro,

    [string]$OutputTarPath = "$env:USERPROFILE\WSL\images\$SourceDistro.tar",

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-Continue {
    param([Parameter(Mandatory)][string[]]$Lines)

    foreach ($line in $Lines) {
        Write-Host $line
    }

    if ($Force -or $WhatIfPreference) {
        return
    }

    $response = Read-Host 'Continue? [y/N]'
    if ($response -notmatch '^(?i)y(?:es)?$') {
        throw 'Cancelled before making changes.'
    }
}

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputTarPath)
$parent = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $parent)) {
    if ($PSCmdlet.ShouldProcess($parent, 'Create export directory')) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

$summary = @(
    "About to export WSL distro '$SourceDistro' to '$resolvedOutput'.",
    'WARNING: exporting a live distro can take a long time and can disrupt active WSL sessions.',
    'Prefer the default fresh-rootfs bootstrap flow unless you explicitly need a clone of an existing distro.'
)
Confirm-Continue -Lines $summary

if ((Test-Path -LiteralPath $resolvedOutput) -and -not $Force) {
    throw "Output tar already exists: $resolvedOutput. Use -Force to overwrite it."
}

if ($PSCmdlet.ShouldProcess($SourceDistro, "Export WSL distro to $resolvedOutput")) {
    $output = & wsl.exe --export $SourceDistro $resolvedOutput 2>&1
    if ($output) {
        $output | Out-Host
    }
    if ($LASTEXITCODE -ne 0) {
        $text = ($output | Out-String).Trim()
        if ($text) {
            throw "WSL export failed. Busy sockets or services in the source distro can break export.`n$text"
        }
        throw 'WSL export failed.'
    }
}

if ($WhatIfPreference) {
    Write-Host "Base image plan ready: $resolvedOutput"
}
else {
    Write-Host "Base image ready: $resolvedOutput"
}

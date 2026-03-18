[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$FontFace = 'MesloLGS NF',

    [switch]$SkipWindowsTerminal,

    [switch]$SkipVSCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-Directory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($PSCmdlet.ShouldProcess($Path, $Description)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    }
}

function Read-JsonObject {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{}
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{}
    }

    return $raw | ConvertFrom-Json
}

function Ensure-ObjectProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value ([pscustomobject]@{})
        $property = $Object.PSObject.Properties[$Name]
    }

    return $property.Value
}

function Set-ScalarProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
    else {
        $property.Value = $Value
    }
}

function Backup-File {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $Path -Destination "$Path.$stamp.bak" -Force
}

function Save-JsonObject {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Object
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Backup-File -Path $Path
    ($Object | ConvertTo-Json -Depth 20) + "`n" | Set-Content -LiteralPath $Path -NoNewline
}

function Install-MesloFonts {
    $fontCacheRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\assets\fonts\meslo-lgs-nf'))
    $userFontRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $fontRegistryPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

    Ensure-Directory -Path $fontCacheRoot -Description 'Create packaged font cache directory'
    Ensure-Directory -Path $userFontRoot -Description 'Create per-user Windows font directory'

    $fontDefinitions = @(
        [pscustomobject]@{
            FileName = 'MesloLGS NF Regular.ttf'
            RegistryName = 'MesloLGS NF Regular (TrueType)'
            Url = 'https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf'
        },
        [pscustomobject]@{
            FileName = 'MesloLGS NF Bold.ttf'
            RegistryName = 'MesloLGS NF Bold (TrueType)'
            Url = 'https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf'
        },
        [pscustomobject]@{
            FileName = 'MesloLGS NF Italic.ttf'
            RegistryName = 'MesloLGS NF Italic (TrueType)'
            Url = 'https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf'
        },
        [pscustomobject]@{
            FileName = 'MesloLGS NF Bold Italic.ttf'
            RegistryName = 'MesloLGS NF Bold Italic (TrueType)'
            Url = 'https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf'
        }
    )

    foreach ($font in $fontDefinitions) {
        $cachePath = Join-Path $fontCacheRoot $font.FileName
        $installedPath = Join-Path $userFontRoot $font.FileName

        if (-not (Test-Path -LiteralPath $cachePath)) {
            if ($PSCmdlet.ShouldProcess($cachePath, "Download $($font.FileName) into the package font cache")) {
                Invoke-WebRequest -UseBasicParsing -Uri $font.Url -OutFile $cachePath
            }
        }

        $alreadyInstalled = (Test-Path -LiteralPath $installedPath) -and
            (Test-Path -LiteralPath $fontRegistryPath) -and
            ((Get-ItemProperty -LiteralPath $fontRegistryPath -Name $font.RegistryName -ErrorAction SilentlyContinue) -ne $null)

        if ($alreadyInstalled) {
            Write-Host "$($font.FileName) is already installed - skipping."
        }
        elseif ($PSCmdlet.ShouldProcess($installedPath, "Install $($font.FileName) for the current Windows user")) {
            try {
                Copy-Item -LiteralPath $cachePath -Destination $installedPath -Force
            }
            catch [System.IO.IOException] {
                Write-Warning "$($font.FileName) is locked by another process (probably already in use). Skipping copy."
            }
            if (-not (Test-Path -LiteralPath $fontRegistryPath)) {
                New-Item -Path $fontRegistryPath -Force | Out-Null
            }
            New-ItemProperty -Path $fontRegistryPath -Name $font.RegistryName -Value $installedPath -PropertyType String -Force | Out-Null
        }
    }
}

Install-MesloFonts

if (-not $SkipWindowsTerminal) {
    $terminalCandidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
    )

    foreach ($candidate in $terminalCandidates) {
        if (-not (Test-Path -LiteralPath $candidate)) {
            continue
        }

        $json = Read-JsonObject -Path $candidate
        $profiles = Ensure-ObjectProperty -Object $json -Name 'profiles'
        $defaults = Ensure-ObjectProperty -Object $profiles -Name 'defaults'
        $font = Ensure-ObjectProperty -Object $defaults -Name 'font'
        Set-ScalarProperty -Object $font -Name 'face' -Value $FontFace

        if ($PSCmdlet.ShouldProcess($candidate, "Set Windows Terminal font to $FontFace")) {
            Save-JsonObject -Path $candidate -Object $json
        }
    }
}

if (-not $SkipVSCode) {
    $vsCodeCandidates = @(
        @(
            "$env:APPDATA\Code\User\settings.json",
            "$env:APPDATA\Code - Insiders\User\settings.json"
        ) | Where-Object { Test-Path -LiteralPath $_ }
    )

    if ($vsCodeCandidates.Count -eq 0) {
        Write-Host 'No VS Code settings found - skipping VS Code font configuration.'
    }

    foreach ($candidate in $vsCodeCandidates) {
        $json = Read-JsonObject -Path $candidate
        Set-ScalarProperty -Object $json -Name 'terminal.integrated.fontFamily' -Value $FontFace

        if ($PSCmdlet.ShouldProcess($candidate, "Set VS Code terminal font to $FontFace")) {
            Save-JsonObject -Path $candidate -Object $json
        }
    }
}

if ($WhatIfPreference) {
    Write-Host "Font installation and terminal configuration plan ready for $FontFace."
}
else {
    Write-Host "Installed $FontFace into the current Windows user profile and configured Windows Terminal and VS Code to use it. Restart open terminals/editors if they were already running."
}

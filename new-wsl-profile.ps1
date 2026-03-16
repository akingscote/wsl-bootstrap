[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)]
    [string]$ProfileName,

    [Alias('SourceDistro')]
    [string]$CloneFromDistro,

    [string]$BaseTarPath,

    [string]$RootfsUrl = 'https://cdimages.ubuntu.com/ubuntu-wsl/noble/daily-live/current/noble-wsl-amd64.wsl',

    [string]$LinuxUser,

    [System.Security.SecureString]$LinuxPassword,

    [string]$InstallRoot = "$env:USERPROFILE\WSL",

    [string]$FontFace = 'MesloLGS NF',

    [switch]$Replace,

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

function ConvertTo-PlainText {
    param([Parameter(Mandatory)][System.Security.SecureString]$SecureString)

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Read-NonEmptyText {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$DefaultValue
    )

    while ($true) {
        $value = Read-Host $Prompt
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }
        if ($DefaultValue) {
            return $DefaultValue
        }
        Write-Warning 'Value cannot be empty.'
    }
}

function Read-ConfirmedPassword {
    while ($true) {
        $first = Read-Host 'Password for the new Linux user' -AsSecureString
        $second = Read-Host 'Confirm the Linux user password' -AsSecureString

        $firstPlain = ConvertTo-PlainText -SecureString $first
        $secondPlain = ConvertTo-PlainText -SecureString $second
        try {
            if ([string]::IsNullOrEmpty($firstPlain)) {
                Write-Warning 'Password cannot be empty.'
                continue
            }
            if ($firstPlain -ne $secondPlain) {
                Write-Warning 'Passwords did not match. Try again.'
                continue
            }
            return $first
        }
        finally {
            $firstPlain = $null
            $secondPlain = $null
        }
    }
}

$repoRoot = $PSScriptRoot
$fontScript = Join-Path $repoRoot 'bootstrap\windows\configure-host-fonts.ps1'
$createScript = Join-Path $repoRoot 'bootstrap\windows\create-wsl-distro.ps1'

if (-not (Test-Path -LiteralPath $fontScript)) {
    throw "Missing helper script: $fontScript"
}
if (-not (Test-Path -LiteralPath $createScript)) {
    throw "Missing helper script: $createScript"
}

if ([string]::IsNullOrWhiteSpace($LinuxUser)) {
    if ($WhatIfPreference) {
        $LinuxUser = 'ashley'
    }
    else {
        $LinuxUser = Read-NonEmptyText -Prompt 'Linux username for the new distro (default: ashley)' -DefaultValue 'ashley'
    }
}

if (($null -eq $LinuxPassword) -and (-not $WhatIfPreference)) {
    $LinuxPassword = Read-ConfirmedPassword
}

$modeDescription = if ($BaseTarPath) {
    "import from the provided archive: $BaseTarPath"
}
elseif ($CloneFromDistro) {
    "clone from the existing distro '$CloneFromDistro' by exporting it first"
}
else {
    "download a fresh Ubuntu 24.04 rootfs from $RootfsUrl and bootstrap it"
}

$summary = @(
    "About to create WSL profile '$ProfileName'.",
    "Linux user: $LinuxUser.",
    "Mode: $modeDescription.",
    "The script will install/configure the mandatory $FontFace font on Windows before provisioning the distro.",
    'Provisioning can take several minutes depending on network speed and package installation time.'
)

if ($CloneFromDistro) {
    $summary += 'WARNING: clone-from-distro mode exports an existing distro and can disrupt active WSL sessions. Save work and shut that distro down cleanly first.'
}
else {
    $summary += 'This default path does not export or modify any existing distro.'
}

Confirm-Continue -Lines $summary

$commonArgs = @{}
if ($WhatIfPreference) {
    $commonArgs['WhatIf'] = $true
}
& $fontScript -FontFace $FontFace @commonArgs

$createArgs = @{
    DistroName = $ProfileName
    BootstrapRepoPath = $repoRoot
    InstallRoot = $InstallRoot
    LinuxUser = $LinuxUser
    RootfsUrl = $RootfsUrl
    Force = $true
}
if ($LinuxPassword) {
    $createArgs['LinuxPassword'] = $LinuxPassword
}
if ($BaseTarPath) {
    $createArgs['BaseTarPath'] = $BaseTarPath
}
elseif ($CloneFromDistro) {
    $createArgs['CloneFromDistro'] = $CloneFromDistro
}
if ($WhatIfPreference) {
    $createArgs['WhatIf'] = $true
}
if ($Replace) {
    $createArgs['Replace'] = $true
}

& $createScript @createArgs

if ($WhatIfPreference) {
    Write-Host "WSL profile plan ready: $ProfileName"
}
else {
    Write-Host "WSL profile ready: $ProfileName"
}

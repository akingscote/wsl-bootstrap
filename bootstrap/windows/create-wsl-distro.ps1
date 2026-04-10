[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)]
    [string]$DistroName,

    [string]$InstallRoot = "$env:USERPROFILE\WSL",

    [string]$BootstrapRepoPath = "$env:USERPROFILE\wsl-bootstrap",

    [Alias('SourceDistro')]
    [string]$CloneFromDistro,

    [string]$BaseTarPath,

    [string]$RootfsUrl = 'https://cdimages.ubuntu.com/ubuntu-wsl/noble/daily-live/current/noble-wsl-amd64.wsl',

    [string]$LinuxUser,

    [System.Security.SecureString]$LinuxPassword,

    [switch]$SkipBootstrap,

    [switch]$Replace,

    [string]$FontFace = 'MesloLGS NF',

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Convert-ToWslPath {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = [System.IO.Path]::GetFullPath($Path)
    if ($resolved -match '^(?<Drive>[A-Za-z]):\\(?<Rest>.*)$') {
        $drive = $Matches['Drive'].ToLowerInvariant()
        $rest = $Matches['Rest'] -replace '\\', '/'
        return "/mnt/$drive/$rest"
    }

    throw "Cannot convert Windows path to WSL path: $Path"
}

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

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "`n>> $Message" -ForegroundColor Cyan
}

function Invoke-Wsl {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$FailureMessage
    )

    $stderrFile = [System.IO.Path]::GetTempFileName()
    $prevPref = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        $stdout = & wsl.exe @Arguments 2>$stderrFile
        $ErrorActionPreference = $prevPref
        $stdoutLines = @($stdout | ForEach-Object { "$_" -replace "`0", '' -replace "`r", '' } | Where-Object { $_.Trim() -ne '' })
        $stderrLines = @()
        if (Test-Path -LiteralPath $stderrFile) {
            $stderrLines = @((Get-Content -LiteralPath $stderrFile) | ForEach-Object { $_ -replace "`0", '' -replace "`r", '' } | Where-Object { $_.Trim() -ne '' })
        }
    }
    finally {
        $ErrorActionPreference = $prevPref
        Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
    }

    $lines = @($stdoutLines) + @($stderrLines) | Where-Object { $_ }
    foreach ($line in $lines) {
        Write-Host "   $line"
    }

    if ($LASTEXITCODE -ne 0) {
        $text = ($lines -join "`n").Trim()
        if ($text) {
            throw "$FailureMessage`n$text"
        }
        throw $FailureMessage
    }
}

function Set-LinuxPassword {
    param(
        [Parameter(Mandatory)][string]$TargetDistro,
        [Parameter(Mandatory)][string]$TargetUser,
        [Parameter(Mandatory)][System.Security.SecureString]$Password
    )

    $plainPassword = ConvertTo-PlainText -SecureString $Password
    try {
        $payload = "{0}:{1}" -f $TargetUser, $plainPassword
        $prevPref = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = $payload | & wsl.exe -d $TargetDistro --user root -- bash -lc "tr -d '\r' | chpasswd" 2>&1
        }
        finally {
            $ErrorActionPreference = $prevPref
        }
        $lines = ($output | Out-String) -replace "`0", '' -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
        foreach ($line in $lines) {
            Write-Host "   $line"
        }
        if ($LASTEXITCODE -ne 0) {
            $text = ($lines -join "`n").Trim()
            if ($text) {
                throw "Failed to set the Linux password.`n$text"
            }
            throw 'Failed to set the Linux password.'
        }
    }
    finally {
        $plainPassword = $null
        $payload = $null
    }
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

$resolvedRepoPath = (Resolve-Path -LiteralPath $BootstrapRepoPath).Path
$resolvedInstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$imagesRoot = Join-Path $resolvedInstallRoot 'images'
$distroRoot = Join-Path $resolvedInstallRoot $DistroName

Ensure-Directory -Path $resolvedInstallRoot -Description 'Create WSL install root'
Ensure-Directory -Path $imagesRoot -Description 'Create WSL image cache directory'

if ($CloneFromDistro -and $BaseTarPath) {
    throw 'Choose either -CloneFromDistro or -BaseTarPath, not both.'
}

if ($CloneFromDistro -and ($CloneFromDistro -eq $DistroName)) {
    throw 'The new distro name must differ from the source distro name.'
}

$existingDistros = @(wsl.exe --list --quiet 2>$null | ForEach-Object { $_ -replace "`0", '' } | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
if ($existingDistros -contains $DistroName) {
    if ($Replace) {
        Write-Step "Replacing existing distro '$DistroName'..."
        if ($PSCmdlet.ShouldProcess($DistroName, 'Unregister existing distro')) {
            Invoke-Wsl -Arguments @('--unregister', $DistroName) -FailureMessage "Failed to unregister existing distro '$DistroName'."
        }
    }
    else {
        throw "Distro '$DistroName' already exists. Use -Replace to remove it first, or choose a different name."
    }
}

if (Test-Path -LiteralPath $distroRoot) {
    if ($Replace) {
        if ($PSCmdlet.ShouldProcess($distroRoot, 'Remove existing install directory')) {
            Remove-Item -LiteralPath $distroRoot -Recurse -Force
        }
    }
    else {
        throw "Target install directory already exists: $distroRoot"
    }
}

$modeSummary = if ($BaseTarPath) {
    "import from the provided archive: $BaseTarPath"
}
elseif ($CloneFromDistro) {
    "clone from existing distro '$CloneFromDistro' by exporting it first"
}
else {
    "download a fresh Ubuntu rootfs from $RootfsUrl and bootstrap it"
}

$summary = @(
    "About to create WSL distro '$DistroName'.",
    "Linux user: $LinuxUser.",
    "Mode: $modeSummary.",
    "Install directory: $distroRoot.",
    'This can take several minutes.'
)
if ($CloneFromDistro) {
    $summary += 'WARNING: clone-from-distro mode can disrupt active WSL sessions in the source distro. Save work and shut it down cleanly first.'
}
else {
    $summary += 'This mode does not export or modify any existing distro.'
}
Confirm-Continue -Lines $summary

if ($BaseTarPath) {
    Write-Step "Using provided base tar: $BaseTarPath"
    $resolvedBaseTarPath = [System.IO.Path]::GetFullPath($BaseTarPath)
    if ((-not (Test-Path -LiteralPath $resolvedBaseTarPath)) -and (-not $WhatIfPreference)) {
        throw "Base tar does not exist: $resolvedBaseTarPath"
    }
}
elseif ($CloneFromDistro) {
    Write-Step "Exporting live distro '$CloneFromDistro' (this can take a while)..."
    $exportRoot = Join-Path $imagesRoot 'live-exports'
    Ensure-Directory -Path $exportRoot -Description 'Create live export cache directory'
    $resolvedBaseTarPath = Join-Path $exportRoot ("{0}.tar" -f $CloneFromDistro)

    if ((Test-Path -LiteralPath $resolvedBaseTarPath) -and $PSCmdlet.ShouldProcess($resolvedBaseTarPath, 'Remove previous live export archive')) {
        Remove-Item -LiteralPath $resolvedBaseTarPath -Force
    }

    if ($PSCmdlet.ShouldProcess($CloneFromDistro, "Export source distro to $resolvedBaseTarPath")) {
        Invoke-Wsl -Arguments @('--export', $CloneFromDistro, $resolvedBaseTarPath) -FailureMessage "WSL export failed. Busy sockets or services in the source distro can break export. Use the default fresh-rootfs mode unless you explicitly need a clone."
    }
}
else {
    $rootfsRoot = Join-Path $imagesRoot 'rootfs'
    Ensure-Directory -Path $rootfsRoot -Description 'Create rootfs cache directory'
    $fileName = [System.IO.Path]::GetFileName(([System.Uri]$RootfsUrl).LocalPath)
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = 'ubuntu-rootfs.tar.gz'
    }
    $resolvedBaseTarPath = Join-Path $rootfsRoot $fileName

    if (-not (Test-Path -LiteralPath $resolvedBaseTarPath)) {
        Write-Step "Downloading fresh Ubuntu rootfs (~374MB)..."
        if ($PSCmdlet.ShouldProcess($resolvedBaseTarPath, "Download clean Ubuntu rootfs from $RootfsUrl")) {
            Invoke-WebRequest -UseBasicParsing -Uri $RootfsUrl -OutFile $resolvedBaseTarPath
        }
    }
    else {
        Write-Step "Using cached rootfs: $resolvedBaseTarPath"
    }
}

Write-Step "Importing distro '$DistroName' into $distroRoot..."
if ($PSCmdlet.ShouldProcess($DistroName, "Import distro into $distroRoot")) {
    Invoke-Wsl -Arguments @('--import', $DistroName, $distroRoot, $resolvedBaseTarPath, '--version', '2') -FailureMessage 'WSL import failed.'
}

Write-Step "Creating Linux user '$LinuxUser' and setting as default..."
$userSetupCommand = "id -u $LinuxUser >/dev/null 2>&1 || useradd -m -s /bin/bash $LinuxUser; getent group sudo >/dev/null 2>&1 && usermod -aG sudo $LinuxUser || true; printf '[user]\ndefault=$LinuxUser\n\n[interop]\nappendWindowsPath=false\n\n[boot]\ncommand=install -d -o $LinuxUser -g $LinuxUser -m 0700 /run/user/1000\n' > /etc/wsl.conf"
if ($PSCmdlet.ShouldProcess($DistroName, "Ensure Linux user $LinuxUser exists and set it as default")) {
    Invoke-Wsl -Arguments @('-d', $DistroName, '--', 'bash', '-lc', $userSetupCommand) -FailureMessage 'Failed to configure the default Linux user.'
}

Write-Step "Setting password for '$LinuxUser'..."
if ($PSCmdlet.ShouldProcess($DistroName, "Set password for Linux user $LinuxUser")) {
    Set-LinuxPassword -TargetDistro $DistroName -TargetUser $LinuxUser -Password $LinuxPassword
}

Write-Step "Restarting distro to apply user config..."
if ($PSCmdlet.ShouldProcess($DistroName, 'Restart the new distro to apply /etc/wsl.conf')) {
    Invoke-Wsl -Arguments @('--terminate', $DistroName) -FailureMessage 'Failed to restart the new distro.'
}

if (-not $SkipBootstrap) {
    Write-Step "Running Linux bootstrap (installing packages and tools - this takes several minutes)..."
    $repoWslPath = Convert-ToWslPath -Path $resolvedRepoPath
    $bootstrapWslPath = "$repoWslPath/bootstrap/linux/bootstrap.sh"
    $bootstrapCommand = "cd / && '$bootstrapWslPath' --apply --repo-root '$repoWslPath' --home '/home/$LinuxUser' --owner '$LinuxUser'"

    if ($PSCmdlet.ShouldProcess($DistroName, 'Run Linux bootstrap')) {
        Invoke-Wsl -Arguments @('-d', $DistroName, '--user', 'root', '--', 'bash', '-lc', $bootstrapCommand) -FailureMessage 'Linux bootstrap failed inside the new distro.'
    }

    Write-Step "Restarting distro to apply shell and config changes..."
    if ($PSCmdlet.ShouldProcess($DistroName, 'Restart distro after bootstrap')) {
        Invoke-Wsl -Arguments @('--terminate', $DistroName) -FailureMessage 'Failed to restart the distro after bootstrap.'
    }
}

Write-Step "Configuring Windows Terminal profile for '$DistroName'..."
$terminalSettingsPaths = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
) | Where-Object { Test-Path -LiteralPath $_ }

$builtInSchemes = @(
    'Campbell', 'Campbell Powershell',
    'One Half Dark', 'One Half Light',
    'Solarized Dark', 'Solarized Light',
    'Tango Dark', 'Tango Light',
    'Vintage'
)

$tabColors = @(
    '#E06C75', '#E5C07B', '#98C379', '#56B6C2', '#61AFEF', '#C678DD',
    '#D19A66', '#BE5046', '#7EC8E3', '#C3E88D', '#F78C6C', '#FFCB6B',
    '#89DDFF', '#BB80B3', '#A3BE8C', '#EBCB8B', '#BF616A', '#D08770'
)

# Windows Terminal generates deterministic GUIDs for WSL profiles using UUIDv5.
# We must use the same GUID so Terminal recognises our entry and does not create
# a duplicate.  The namespace is TERMINAL_PROFILE_NAMESPACE_GUID from the
# Windows Terminal source and the name is the UTF-16LE distro name.
function New-GuidV5 {
    param(
        [Parameter(Mandatory)][guid]$Namespace,
        [Parameter(Mandatory)][byte[]]$NameBytes
    )

    $nsBytes = $Namespace.ToByteArray()
    [Array]::Reverse($nsBytes, 0, 4)
    [Array]::Reverse($nsBytes, 4, 2)
    [Array]::Reverse($nsBytes, 6, 2)

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $toHash = [byte[]]::new($nsBytes.Length + $NameBytes.Length)
        [Array]::Copy($nsBytes, 0, $toHash, 0, $nsBytes.Length)
        [Array]::Copy($NameBytes, 0, $toHash, $nsBytes.Length, $NameBytes.Length)
        $hash = $sha1.ComputeHash($toHash)
    }
    finally { $sha1.Dispose() }

    $result = [byte[]]::new(16)
    [Array]::Copy($hash, $result, 16)
    $result[6] = ($result[6] -band 0x0F) -bor 0x50
    $result[8] = ($result[8] -band 0x3F) -bor 0x80

    [Array]::Reverse($result, 0, 4)
    [Array]::Reverse($result, 4, 2)
    [Array]::Reverse($result, 6, 2)
    return [guid]::new($result)
}

$terminalProfileNamespace = [guid]'2bde4a90-d05f-401c-9492-e40884ead1d8'
$expectedGuid = '{' + (New-GuidV5 -Namespace $terminalProfileNamespace -NameBytes ([System.Text.Encoding]::Unicode.GetBytes($DistroName))).ToString() + '}'

foreach ($settingsPath in $terminalSettingsPaths) {
    if ($PSCmdlet.ShouldProcess($settingsPath, "Configure profile for $DistroName")) {
        $raw = Get-Content -LiteralPath $settingsPath -Raw
        $json = $raw | ConvertFrom-Json

        $profiles = $json.profiles
        if ($null -eq $profiles) { continue }

        $list = $profiles.list
        if ($null -eq $list) { continue }

        # Collect custom scheme names if any
        $customSchemes = @()
        if ($json.schemes) {
            $customSchemes = @($json.schemes | ForEach-Object { $_.name })
        }
        $allSchemes = $builtInSchemes + $customSchemes

        # Pick a scheme not already used by other WSL profiles
        $usedSchemes = @($list | Where-Object {
            ($_ | Get-Member -Name 'colorScheme') -and
            ($_ | Get-Member -Name 'commandline') -and $_.commandline -match 'wsl\.exe' -and
            $_.name -ne $DistroName
        } | ForEach-Object { $_.colorScheme })
        $available = @($allSchemes | Where-Object { $_ -notin $usedSchemes })
        if (-not $available) { $available = $allSchemes }
        $chosenScheme = $available | Get-Random

        # Pick a tab color not already used by other WSL profiles
        $usedColors = @($list | Where-Object {
            ($_ | Get-Member -Name 'tabColor') -and
            ($_ | Get-Member -Name 'commandline') -and $_.commandline -match 'wsl\.exe' -and
            $_.name -ne $DistroName
        } | ForEach-Object { $_.tabColor })
        $availableColors = @($tabColors | Where-Object { $_ -notin $usedColors })
        if (-not $availableColors) { $availableColors = $tabColors }
        $chosenTabColor = $availableColors | Get-Random

        # Find all profiles that belong to this distro (by name or GUID).
        # Terminal and the WSL app each auto-generate a profile for every
        # registered distro.  We keep the one whose GUID matches the
        # deterministic value Terminal would compute and hide the rest so that
        # their generators do not recreate them.
        $distroProfiles = @($list | Where-Object { $_.name -eq $DistroName })
        $primary = $distroProfiles | Where-Object {
            ($_ | Get-Member -Name 'guid') -and $_.guid -eq $expectedGuid
        } | Select-Object -First 1

        # If no profile with the expected GUID exists yet, prefer the first
        # match so we can update it in place.
        if (-not $primary -and $distroProfiles) {
            $primary = $distroProfiles | Select-Object -First 1
        }

        if ($primary) {
            # Ensure the GUID matches what Terminal expects
            if ($primary | Get-Member -Name 'guid') { $primary.guid = $expectedGuid } else { $primary | Add-Member -NotePropertyName 'guid' -NotePropertyValue $expectedGuid }
            if ($primary | Get-Member -Name 'colorScheme') { $primary.colorScheme = $chosenScheme } else { $primary | Add-Member -NotePropertyName 'colorScheme' -NotePropertyValue $chosenScheme }
            if ($primary | Get-Member -Name 'tabColor') { $primary.tabColor = $chosenTabColor } else { $primary | Add-Member -NotePropertyName 'tabColor' -NotePropertyValue $chosenTabColor }
            if (-not ($primary | Get-Member -Name 'font')) { $primary | Add-Member -NotePropertyName 'font' -NotePropertyValue ([pscustomobject]@{ face = $FontFace }) }
            if (-not ($primary | Get-Member -Name 'commandline')) { $primary | Add-Member -NotePropertyName 'commandline' -NotePropertyValue "wsl.exe -d $DistroName" }
            # Remove the source property so Terminal treats this as a
            # user-defined profile and does not overwrite our customisations.
            if ($primary | Get-Member -Name 'source') { $primary.PSObject.Properties.Remove('source') }
            # Ensure the primary profile is visible (it may have been hidden
            # by a previous run or by Terminal itself).
            if ($primary | Get-Member -Name 'hidden') { $primary.hidden = $false }
            Write-Host "   Updated profile '$DistroName' with scheme '$chosenScheme' and tab color $chosenTabColor"
        }
        else {
            $primary = [pscustomobject]@{
                guid             = $expectedGuid
                name             = $DistroName
                commandline      = "wsl.exe -d $DistroName"
                icon             = 'ms-appx:///ProfileIcons/{9acb9455-ca41-5af7-950f-6bca1bc9722f}.png'
                font             = [pscustomobject]@{ face = $FontFace }
                startingDirectory = "//wsl.localhost/$DistroName/home/$LinuxUser"
                colorScheme      = $chosenScheme
                tabColor         = $chosenTabColor
                tabTitle         = $DistroName
                suppressApplicationTitle = $true
            }
            $list = @($list) + @($primary)
            Write-Host "   Added profile '$DistroName' with scheme '$chosenScheme' and tab color $chosenTabColor"
        }

        # Hide any other profiles for the same distro so only one entry
        # appears in the Terminal dropdown.  Setting hidden keeps them in
        # settings.json which prevents their generators from recreating them.
        foreach ($dup in $distroProfiles) {
            if ([object]::ReferenceEquals($dup, $primary)) { continue }
            if ($dup | Get-Member -Name 'hidden') { $dup.hidden = $true } else { $dup | Add-Member -NotePropertyName 'hidden' -NotePropertyValue $true }
        }

        $profiles.list = $list
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item -LiteralPath $settingsPath -Destination "$settingsPath.$stamp.bak" -Force
        ($json | ConvertTo-Json -Depth 20) + "`n" | Set-Content -LiteralPath $settingsPath -NoNewline
    }
}

if ($WhatIfPreference) {
    Write-Host "WSL distro plan ready: $DistroName"
}
else {
    Write-Host ''
    Write-Host '========================================' -ForegroundColor Green
    Write-Host "  Setup complete: $DistroName" -ForegroundColor Green
    Write-Host '========================================' -ForegroundColor Green
    Write-Host ''
    Write-Host "Open Windows Terminal and select the '$DistroName' profile."
    Write-Host 'Next steps inside the distro:'
    Write-Host '  gh auth login'
    Write-Host '  az login'
}

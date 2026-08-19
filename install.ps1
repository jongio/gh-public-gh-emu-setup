& {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$EmuHost,
        [Parameter(Mandatory)][string]$ConfigRoot,
        [Parameter(Mandatory)][string]$FragmentRoot,
        [switch]$Authenticate,
        [switch]$SkipAuthentication,
        [switch]$SkipPrerequisiteCheck
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

function Test-Truthy {
    param([AllowNull()][string]$Value)

    return $Value -match '^(1|true|yes|y)$'
}

function Assert-ValidHostName {
    param([Parameter(Mandatory)][string]$HostName)

    $hostKind = [Uri]::CheckHostName($HostName)
    if ($hostKind -notin @([UriHostNameType]::Dns, [UriHostNameType]::IPv4, [UriHostNameType]::IPv6)) {
        throw "Invalid EMU hostname '$HostName'. Provide a hostname without a scheme or path."
    }
}

function Get-TerminalCommandLine {
    param(
        [Parameter(Mandatory)][string]$ConfigDirectory,
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Color
    )

    $escapedConfigDirectory = $ConfigDirectory.Replace("'", "''")
    $escapedHostName = $HostName.Replace("'", "''")
    $escapedLabel = $Label.Replace("'", "''")

    $commands = @(
        'Remove-Item Env:GH_TOKEN, Env:GITHUB_TOKEN, Env:GH_ENTERPRISE_TOKEN, Env:GITHUB_ENTERPRISE_TOKEN -ErrorAction SilentlyContinue'
        "`$env:GH_CONFIG_DIR = '$escapedConfigDirectory'"
        "`$env:GH_HOST = '$escapedHostName'"
        "Write-Host 'gh auth: $escapedLabel (isolated)' -ForegroundColor $Color"
    )

    return 'pwsh.exe -NoLogo -NoExit -Command "& { ' + ($commands -join '; ') + ' }"'
}

function Invoke-IsolatedAuthentication {
    param(
        [Parameter(Mandatory)][string]$GhPath,
        [Parameter(Mandatory)][string]$ConfigDirectory,
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][string]$Label
    )

    $managedVariables = @(
        'GH_CONFIG_DIR'
        'GH_HOST'
        'GH_TOKEN'
        'GITHUB_TOKEN'
        'GH_ENTERPRISE_TOKEN'
        'GITHUB_ENTERPRISE_TOKEN'
    )
    $previousValues = @{}

    foreach ($name in $managedVariables) {
        $previousValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }

    try {
        $env:GH_CONFIG_DIR = $ConfigDirectory
        $env:GH_HOST = $HostName

        & $GhPath auth status --hostname $HostName *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Information "Authenticate the $Label account on $HostName." -InformationAction Continue
            & $GhPath auth login --hostname $HostName --web
            if ($LASTEXITCODE -ne 0) {
                throw "GitHub CLI authentication failed for $Label."
            }
        }

        $statusJson = & $GhPath auth status --hostname $HostName --json hosts
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($statusJson)) {
            throw "Unable to verify the authenticated $Label account."
        }

        $status = $statusJson | ConvertFrom-Json -ErrorAction Stop
        $hostProperty = $status.hosts.PSObject.Properties[$HostName]
        $activeAccount = if ($hostProperty) {
            $hostProperty.Value |
                Where-Object { $_.active -and $_.state -eq 'success' } |
                Select-Object -First 1
        }
        $login = $activeAccount.login
        if ([string]::IsNullOrWhiteSpace($login)) {
            throw "Unable to find the active authenticated $Label account."
        }

        Write-Information "$Label verified as $login." -InformationAction Continue
        return $login.Trim()
    }
    finally {
        foreach ($name in $managedVariables) {
            [Environment]::SetEnvironmentVariable($name, $previousValues[$name], 'Process')
        }
    }
}

if ($Authenticate -and $SkipAuthentication) {
    throw 'Use either -Authenticate or -SkipAuthentication, not both.'
}

Assert-ValidHostName -HostName $EmuHost

$ghPath = $null
if (-not $SkipPrerequisiteCheck) {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw 'PowerShell 7 or later is required. Run this command from pwsh.'
    }
    if (-not $IsWindows) {
        throw 'This installer supports Windows only.'
    }

    $ghCommand = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $ghCommand) {
        throw 'GitHub CLI is required. Install it from https://cli.github.com/.'
    }
    if (-not (Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'PowerShell 7 or later is required. Install it from https://aka.ms/powershell-release?tag=stable.'
    }
    if (-not (Get-Command wt.exe -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'Windows Terminal is required. Install it from https://aka.ms/terminal.'
    }

    $ghPath = $ghCommand.Source
}

$emuConfigDirectory = Join-Path $ConfigRoot 'gh-emu'
$publicConfigDirectory = Join-Path $ConfigRoot 'gh-public'
$fragmentPath = Join-Path $FragmentRoot 'profiles.json'

foreach ($directory in @($emuConfigDirectory, $publicConfigDirectory, $FragmentRoot)) {
    if ($PSCmdlet.ShouldProcess($directory, 'Create directory')) {
        $null = New-Item -ItemType Directory -Force -Path $directory
    }
}

$fragment = [ordered]@{
    profiles = @(
        [ordered]@{
            guid              = '{b15899db-9fc0-5198-bf81-c6fbb0bce60b}'
            name              = 'GitHub EMU'
            commandline       = Get-TerminalCommandLine `
                -ConfigDirectory $emuConfigDirectory `
                -HostName $EmuHost `
                -Label 'EMU' `
                -Color 'Cyan'
            startingDirectory = '%USERPROFILE%'
            tabTitle          = 'GitHub EMU'
        }
        [ordered]@{
            guid              = '{215245a6-0807-5a62-8cbf-557a62e5d67f}'
            name              = 'GitHub Public'
            commandline       = Get-TerminalCommandLine `
                -ConfigDirectory $publicConfigDirectory `
                -HostName 'github.com' `
                -Label 'Public' `
                -Color 'Green'
            startingDirectory = '%USERPROFILE%'
            tabTitle          = 'GitHub Public'
        }
    )
}

$shouldAuthenticate = $Authenticate
if (-not $Authenticate -and -not $SkipAuthentication -and -not $WhatIfPreference) {
    if ($null -ne $env:GH_SETUP_AUTHENTICATE) {
        $shouldAuthenticate = Test-Truthy -Value $env:GH_SETUP_AUTHENTICATE
    }
    else {
        $answer = Read-Host 'Authenticate both GitHub accounts now? [Y/n]'
        $shouldAuthenticate = [string]::IsNullOrWhiteSpace($answer) -or (Test-Truthy -Value $answer)
    }
}

if ($shouldAuthenticate -and $PSCmdlet.ShouldProcess('GitHub EMU and Public accounts', 'Authenticate')) {
    if (-not $ghPath) {
        $ghPath = (Get-Command gh -CommandType Application -ErrorAction Stop |
            Select-Object -First 1).Source
    }

    $emuLogin = Invoke-IsolatedAuthentication `
        -GhPath $ghPath `
        -ConfigDirectory $emuConfigDirectory `
        -HostName $EmuHost `
        -Label 'GitHub EMU'
    $publicLogin = Invoke-IsolatedAuthentication `
        -GhPath $ghPath `
        -ConfigDirectory $publicConfigDirectory `
        -HostName 'github.com' `
        -Label 'GitHub Public'

    if ($EmuHost -eq 'github.com' -and $emuLogin -eq $publicLogin) {
        throw "Both profiles authenticated as '$emuLogin'. Re-authenticate one profile with the other account."
    }
}

if ($PSCmdlet.ShouldProcess($fragmentPath, 'Install Windows Terminal profile fragment')) {
    $temporaryFragmentPath = Join-Path $FragmentRoot ".$([guid]::NewGuid()).tmp"
    try {
        $fragment | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporaryFragmentPath -Encoding utf8NoBOM
        $null = Get-Content -LiteralPath $temporaryFragmentPath -Raw | ConvertFrom-Json -ErrorAction Stop

        [IO.File]::Move($temporaryFragmentPath, $fragmentPath, $true)
        Write-Information "Installed Windows Terminal profiles at $fragmentPath." -InformationAction Continue
    }
    finally {
        Remove-Item -LiteralPath $temporaryFragmentPath -Force -ErrorAction SilentlyContinue
    }
}

    if ($WhatIfPreference) {
        Write-Information 'Dry run complete. No files or authentication settings were changed.' -InformationAction Continue
    }
    else {
        Write-Information 'Setup complete. Restart Windows Terminal, then open GitHub EMU or GitHub Public.' -InformationAction Continue
    }
} `
    -EmuHost $(if ($env:GH_EMU_HOST) { $env:GH_EMU_HOST } else { 'github.com' }) `
    -ConfigRoot $(if ($env:GH_SETUP_CONFIG_ROOT) {
        $env:GH_SETUP_CONFIG_ROOT
    } else {
        Join-Path $HOME '.config'
    }) `
    -FragmentRoot $(if ($env:GH_SETUP_FRAGMENT_ROOT) {
        $env:GH_SETUP_FRAGMENT_ROOT
    } else {
        Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\gh-public-gh-emu-setup'
    }) `
    -Authenticate:($env:GH_SETUP_AUTHENTICATE -match '^(1|true|yes|y)$') `
    -SkipAuthentication:(
        $null -ne $env:GH_SETUP_AUTHENTICATE -and
        $env:GH_SETUP_AUTHENTICATE -notmatch '^(1|true|yes|y)$'
    ) `
    -SkipPrerequisiteCheck:($env:GH_SETUP_SKIP_PREREQUISITE_CHECK -match '^(1|true|yes|y)$') `
    -WhatIf:($env:GH_SETUP_DRY_RUN -match '^(1|true|yes|y)$')

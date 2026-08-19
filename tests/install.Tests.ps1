[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingInvokeExpression',
    '',
    Justification = 'The supported Invoke-RestMethod pipeline entry point must be tested directly.'
)]
param()

$installerPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'

Describe 'install.ps1' {
    $installerInputNames = @(
        'GH_EMU_HOST'
        'GH_SETUP_AUTHENTICATE'
        'GH_SETUP_CONFIG_ROOT'
        'GH_SETUP_FRAGMENT_ROOT'
        'GH_SETUP_SKIP_PREREQUISITE_CHECK'
        'GH_SETUP_DRY_RUN'
        'GH_SETUP_TEST_FAIL_LOGIN'
        'GH_SETUP_TEST_SAME_ACCOUNT'
    )

    BeforeEach {
        $script:previousInstallerInputs = @{}
        foreach ($name in $installerInputNames) {
            $script:previousInstallerInputs[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
            [Environment]::SetEnvironmentVariable($name, $null, 'Process')
        }
    }

    AfterEach {
        foreach ($name in $installerInputNames) {
            [Environment]::SetEnvironmentVariable(
                $name,
                $script:previousInstallerInputs[$name],
                'Process'
            )
        }
    }

    It 'installs isolated profiles idempotently' {
        $configRoot = Join-Path $TestDrive 'config'
        $fragmentRoot = Join-Path $TestDrive 'fragments'
        $previousAuthenticate = $env:GH_SETUP_AUTHENTICATE
        $previousConfigRoot = $env:GH_SETUP_CONFIG_ROOT
        $previousFragmentRoot = $env:GH_SETUP_FRAGMENT_ROOT
        $previousPrerequisiteCheck = $env:GH_SETUP_SKIP_PREREQUISITE_CHECK

        try {
            $env:GH_SETUP_AUTHENTICATE = 'false'
            $env:GH_SETUP_CONFIG_ROOT = $configRoot
            $env:GH_SETUP_FRAGMENT_ROOT = $fragmentRoot
            $env:GH_SETUP_SKIP_PREREQUISITE_CHECK = 'true'

            & $installerPath
            & $installerPath

            Test-Path (Join-Path $configRoot 'gh-emu') | Should Be $true
            Test-Path (Join-Path $configRoot 'gh-public') | Should Be $true

            $fragment = Get-Content (Join-Path $fragmentRoot 'profiles.json') -Raw | ConvertFrom-Json
            $fragment.profiles.Count | Should Be 2
            $fragment.profiles[0].name | Should Be 'GitHub EMU'
            $fragment.profiles[1].name | Should Be 'GitHub Public'
            $fragment.profiles[0].guid | Should Be '{b15899db-9fc0-5198-bf81-c6fbb0bce60b}'
            $fragment.profiles[1].guid | Should Be '{215245a6-0807-5a62-8cbf-557a62e5d67f}'
            $fragment.profiles[0].commandline | Should Match 'GH_CONFIG_DIR'
            $fragment.profiles[0].commandline | Should Match 'gh-emu'
            $fragment.profiles[1].commandline | Should Match 'gh-public'
            $fragment.profiles[0].commandline | Should Match 'Remove-Item Env:GH_TOKEN'
        }
        finally {
            $env:GH_SETUP_AUTHENTICATE = $previousAuthenticate
            $env:GH_SETUP_CONFIG_ROOT = $previousConfigRoot
            $env:GH_SETUP_FRAGMENT_ROOT = $previousFragmentRoot
            $env:GH_SETUP_SKIP_PREREQUISITE_CHECK = $previousPrerequisiteCheck
        }
    }

    It 'supports Invoke-RestMethod pipeline execution' {
        $configRoot = Join-Path $TestDrive 'pipeline-config'
        $fragmentRoot = Join-Path $TestDrive 'pipeline-fragments'
        $previousAuthenticate = $env:GH_SETUP_AUTHENTICATE
        $previousConfigRoot = $env:GH_SETUP_CONFIG_ROOT
        $previousFragmentRoot = $env:GH_SETUP_FRAGMENT_ROOT
        $previousPrerequisiteCheck = $env:GH_SETUP_SKIP_PREREQUISITE_CHECK

        try {
            $env:GH_SETUP_AUTHENTICATE = 'false'
            $env:GH_SETUP_CONFIG_ROOT = $configRoot
            $env:GH_SETUP_FRAGMENT_ROOT = $fragmentRoot
            $env:GH_SETUP_SKIP_PREREQUISITE_CHECK = 'true'

            Get-Content $installerPath -Raw | Invoke-Expression

            Test-Path (Join-Path $fragmentRoot 'profiles.json') | Should Be $true
            Test-Path (Join-Path $configRoot 'gh-emu') | Should Be $true
            Test-Path (Join-Path $configRoot 'gh-public') | Should Be $true
        }
        finally {
            $env:GH_SETUP_AUTHENTICATE = $previousAuthenticate
            $env:GH_SETUP_CONFIG_ROOT = $previousConfigRoot
            $env:GH_SETUP_FRAGMENT_ROOT = $previousFragmentRoot
            $env:GH_SETUP_SKIP_PREREQUISITE_CHECK = $previousPrerequisiteCheck
        }
    }

    It 'isolates authentication and restores token variables' {
        $configRoot = Join-Path $TestDrive 'auth-config'
        $fragmentRoot = Join-Path $TestDrive 'auth-fragments'
        $fakeGhScriptPath = Join-Path $TestDrive 'fake-gh.ps1'
        $fakeGhCommandPath = Join-Path $TestDrive 'gh.cmd'
        $logPath = Join-Path $TestDrive 'gh-log.jsonl'
        $fakeGh = @'
$record = [ordered]@{
    arguments = @($args)
    config = $env:GH_CONFIG_DIR
    host = $env:GH_HOST
    ghToken = $env:GH_TOKEN
    githubToken = $env:GITHUB_TOKEN
    enterpriseToken = $env:GH_ENTERPRISE_TOKEN
    githubEnterpriseToken = $env:GITHUB_ENTERPRISE_TOKEN
}
$record | ConvertTo-Json -Compress | Add-Content $env:GH_SETUP_TEST_LOG
if ($args[0] -eq 'auth' -and $args[1] -eq 'status') {
    $markerPath = Join-Path $env:GH_CONFIG_DIR '.fake-authenticated'
    if (-not $env:GH_SETUP_TEST_FAIL_LOGIN -and (Test-Path -LiteralPath $markerPath)) {
        $login = if ($env:GH_SETUP_TEST_SAME_ACCOUNT) {
            'same-user'
        } elseif ($env:GH_CONFIG_DIR -like '*gh-emu') {
            'emu-user'
        } else {
            'public-user'
        }
        $login
        exit 0
    }
    exit 1
}
if ($args[0] -eq 'auth' -and $args[1] -eq 'login') {
    if ($env:GH_SETUP_TEST_FAIL_LOGIN) { exit 1 }
    Set-Content -LiteralPath (Join-Path $env:GH_CONFIG_DIR '.fake-authenticated') -Value 'true'
    exit 0
}
exit 2
'@
        Set-Content -LiteralPath $fakeGhScriptPath -Value $fakeGh -Encoding utf8
        Set-Content -LiteralPath $fakeGhCommandPath -Value @'
@echo off
pwsh.exe -NoProfile -NonInteractive -File "%GH_SETUP_TEST_FAKE_GH_SCRIPT%" %*
exit /b %ERRORLEVEL%
'@ -Encoding ascii

        $managedVariables = @(
            'GH_SETUP_AUTHENTICATE'
            'GH_SETUP_CONFIG_ROOT'
            'GH_SETUP_FRAGMENT_ROOT'
            'GH_SETUP_SKIP_PREREQUISITE_CHECK'
            'GH_SETUP_TEST_FAKE_GH_SCRIPT'
            'GH_SETUP_TEST_LOG'
            'GH_TOKEN'
            'GITHUB_TOKEN'
            'GH_ENTERPRISE_TOKEN'
            'GITHUB_ENTERPRISE_TOKEN'
            'GH_CONFIG_DIR'
            'GH_HOST'
            'PATH'
        )
        $previousValues = @{}
        foreach ($name in $managedVariables) {
            $previousValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }

        try {
            $env:GH_SETUP_AUTHENTICATE = 'true'
            $env:GH_SETUP_CONFIG_ROOT = $configRoot
            $env:GH_SETUP_FRAGMENT_ROOT = $fragmentRoot
            $env:GH_SETUP_SKIP_PREREQUISITE_CHECK = 'true'
            $env:GH_SETUP_TEST_FAKE_GH_SCRIPT = $fakeGhScriptPath
            $env:GH_SETUP_TEST_LOG = $logPath
            $env:PATH = "$TestDrive;$env:PATH"
            $env:GH_TOKEN = 'original-gh-token'
            $env:GITHUB_TOKEN = 'original-github-token'
            $env:GH_ENTERPRISE_TOKEN = 'original-enterprise-token'
            $env:GITHUB_ENTERPRISE_TOKEN = 'original-github-enterprise-token'
            $env:GH_CONFIG_DIR = 'original-config'
            $env:GH_HOST = 'original-host'

            & $installerPath

            $env:GH_TOKEN | Should Be 'original-gh-token'
            $env:GITHUB_TOKEN | Should Be 'original-github-token'
            $env:GH_ENTERPRISE_TOKEN | Should Be 'original-enterprise-token'
            $env:GITHUB_ENTERPRISE_TOKEN | Should Be 'original-github-enterprise-token'
            $env:GH_CONFIG_DIR | Should Be 'original-config'
            $env:GH_HOST | Should Be 'original-host'

            $records = Get-Content $logPath | ForEach-Object { $_ | ConvertFrom-Json }
            ($records | Where-Object { $_.arguments[0] -eq 'auth' -and $_.arguments[1] -eq 'login' }).Count | Should Be 2
            ($records | Where-Object { $_.config -like '*gh-emu' }).Count | Should BeGreaterThan 0
            ($records | Where-Object { $_.config -like '*gh-public' }).Count | Should BeGreaterThan 0
            ($records | Where-Object {
                $_.ghToken -or
                $_.githubToken -or
                $_.enterpriseToken -or
                $_.githubEnterpriseToken
            }).Count | Should Be 0

            $fragmentPath = Join-Path $fragmentRoot 'profiles.json'
            $fragmentHash = (Get-FileHash $fragmentPath).Hash

            $env:GH_SETUP_TEST_SAME_ACCOUNT = 'true'
            $sameAccountRejected = $false
            try {
                & $installerPath
            }
            catch {
                $sameAccountRejected = $true
            }
            $sameAccountRejected | Should Be $true
            (Get-FileHash $fragmentPath).Hash | Should Be $fragmentHash
            $env:GH_CONFIG_DIR | Should Be 'original-config'
            $env:GH_HOST | Should Be 'original-host'
            $env:GH_SETUP_TEST_SAME_ACCOUNT = $null

            $env:GH_SETUP_TEST_FAIL_LOGIN = 'true'
            $failedLoginRejected = $false
            try {
                & $installerPath
            }
            catch {
                $failedLoginRejected = $true
            }
            $failedLoginRejected | Should Be $true
            (Get-FileHash $fragmentPath).Hash | Should Be $fragmentHash
            $env:GH_CONFIG_DIR | Should Be 'original-config'
            $env:GH_HOST | Should Be 'original-host'
        }
        finally {
            foreach ($name in $managedVariables) {
                [Environment]::SetEnvironmentVariable($name, $previousValues[$name], 'Process')
            }
        }
    }

    It 'does not claim installation during a dry run' {
        $configRoot = Join-Path $TestDrive 'dry-run-config'
        $fragmentRoot = Join-Path $TestDrive 'dry-run-fragments'
        $previousAuthenticate = $env:GH_SETUP_AUTHENTICATE
        $previousConfigRoot = $env:GH_SETUP_CONFIG_ROOT
        $previousFragmentRoot = $env:GH_SETUP_FRAGMENT_ROOT
        $previousPrerequisiteCheck = $env:GH_SETUP_SKIP_PREREQUISITE_CHECK
        $previousDryRun = $env:GH_SETUP_DRY_RUN

        try {
            $env:GH_SETUP_AUTHENTICATE = 'false'
            $env:GH_SETUP_CONFIG_ROOT = $configRoot
            $env:GH_SETUP_FRAGMENT_ROOT = $fragmentRoot
            $env:GH_SETUP_SKIP_PREREQUISITE_CHECK = 'true'
            $env:GH_SETUP_DRY_RUN = 'true'

            $messages = & $installerPath 6>&1 | Out-String

            Test-Path $configRoot | Should Be $false
            Test-Path $fragmentRoot | Should Be $false
            $messages | Should Match 'Dry run complete'
            $messages | Should Not Match 'Setup complete'
        }
        finally {
            $env:GH_SETUP_AUTHENTICATE = $previousAuthenticate
            $env:GH_SETUP_CONFIG_ROOT = $previousConfigRoot
            $env:GH_SETUP_FRAGMENT_ROOT = $previousFragmentRoot
            $env:GH_SETUP_SKIP_PREREQUISITE_CHECK = $previousPrerequisiteCheck
            $env:GH_SETUP_DRY_RUN = $previousDryRun
        }
    }

    It 'rejects an invalid managed-account hostname before writing files' {
        $configRoot = Join-Path $TestDrive 'invalid-host-config'
        $fragmentRoot = Join-Path $TestDrive 'invalid-host-fragments'
        $env:GH_EMU_HOST = 'https://github.com/path'
        $env:GH_SETUP_AUTHENTICATE = 'false'
        $env:GH_SETUP_CONFIG_ROOT = $configRoot
        $env:GH_SETUP_FRAGMENT_ROOT = $fragmentRoot
        $env:GH_SETUP_SKIP_PREREQUISITE_CHECK = 'true'

        $invalidHostRejected = $false
        try {
            & $installerPath
        }
        catch {
            $invalidHostRejected = $true
        }
        $invalidHostRejected | Should Be $true
        Test-Path $configRoot | Should Be $false
        Test-Path $fragmentRoot | Should Be $false
    }
}

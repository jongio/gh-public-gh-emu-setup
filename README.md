# Isolated GitHub CLI Authentication for Multiple Accounts

When terminals share GitHub CLI's default configuration, `gh auth switch` changes the active account for that shared configuration. One terminal can therefore change the account used by another terminal.

The fix is `GH_CONFIG_DIR`, an environment variable that tells `gh` where to store and read its configuration. By pointing each terminal at a separate config directory, each session gets fully isolated auth with zero cross-talk.

## How It Works

By default, `gh` uses one configuration directory for account state, preferences, and host settings. Authentication tokens are normally held by the operating system credential store. The `GH_CONFIG_DIR` environment variable overrides the configuration location, allowing each terminal to select its account independently.

This approach is:

- **Parallel-safe**: multiple terminals can run `gh` commands simultaneously without conflicts
- **Simpler than `gh auth switch`**: no global state to manage or forget about
- **Secure**: tokens are managed by GitHub CLI rather than exposed through `GH_TOKEN`

## Quick Setup

Open PowerShell 7 and run:

```powershell
irm https://raw.githubusercontent.com/jongio/gh-public-gh-emu-setup/main/install.ps1 | iex
```

The installer:

- Checks for GitHub CLI, PowerShell 7, and Windows Terminal
- Creates isolated `gh-emu` and `gh-public` configuration directories
- Installs both profiles through a Windows Terminal JSON fragment
- Prompts to authenticate and verifies the account used by each profile
- Can be run repeatedly without duplicating profiles

GitHub Enterprise Managed Users commonly use `github.com`, which is the default. If your managed account uses another GitHub hostname, set it before running the installer:

```powershell
$env:GH_EMU_HOST = 'octocorp.ghe.com'
irm https://raw.githubusercontent.com/jongio/gh-public-gh-emu-setup/main/install.ps1 | iex
```

To install the profiles without authenticating:

```powershell
$env:GH_SETUP_AUTHENTICATE = 'false'
irm https://raw.githubusercontent.com/jongio/gh-public-gh-emu-setup/main/install.ps1 | iex
```

The command downloads executable code from this repository's mutable `main` branch. Run it only if you trust this repository and its maintainers. Inspection and execution are separate downloads, so inspecting first does not guarantee that `main` remains unchanged:

```powershell
irm https://raw.githubusercontent.com/jongio/gh-public-gh-emu-setup/main/install.ps1
```

The remaining sections document the equivalent manual setup.

## Prerequisites

- [GitHub CLI (`gh`)](https://cli.github.com/) installed
- [PowerShell 7+](https://github.com/PowerShell/PowerShell/releases) installed
- [Windows Terminal](https://aka.ms/terminal) installed
- Windows 10 or later
- Two GitHub accounts, normally one EMU and one public account

## Step 1: Create Isolated Config Directories

Open any terminal and run:

```powershell
New-Item -ItemType Directory -Force -Path "$HOME\.config\gh-emu"
New-Item -ItemType Directory -Force -Path "$HOME\.config\gh-public"
```

## Step 2: Authenticate Each Account

Log in to your EMU account:

```powershell
$emuHost = if ($env:GH_EMU_HOST) { $env:GH_EMU_HOST } else { 'github.com' }
Remove-Item Env:GH_TOKEN, Env:GITHUB_TOKEN, Env:GH_ENTERPRISE_TOKEN, Env:GITHUB_ENTERPRISE_TOKEN -ErrorAction SilentlyContinue
$env:GH_CONFIG_DIR = "$HOME\.config\gh-emu"
$env:GH_HOST = $emuHost
gh auth login --hostname $emuHost --web
```

Complete the browser flow with your managed account.

Then, in the same terminal (or a new one), log in to your public account:

```powershell
Remove-Item Env:GH_TOKEN, Env:GITHUB_TOKEN, Env:GH_ENTERPRISE_TOKEN, Env:GITHUB_ENTERPRISE_TOKEN -ErrorAction SilentlyContinue
$env:GH_CONFIG_DIR = "$HOME\.config\gh-public"
$env:GH_HOST = 'github.com'
gh auth login --hostname github.com --web
```

Complete the browser flow with your public account. These commands intentionally change the GitHub CLI context in the current PowerShell process.

Each directory now holds independent GitHub CLI account and host configuration. GitHub CLI normally keeps the corresponding token in the operating system credential store.

## Step 3: Add Windows Terminal Profiles

Open your Windows Terminal `settings.json` (Settings > Open JSON file), and add these two entries to the `profiles.list` array:

```json
{
    "guid": "{generate-a-new-guid-1}",
    "name": "GitHub EMU",
    "commandline": "pwsh.exe -NoLogo -NoExit -Command \"& { Remove-Item Env:GH_TOKEN,Env:GITHUB_TOKEN,Env:GH_ENTERPRISE_TOKEN,Env:GITHUB_ENTERPRISE_TOKEN -ErrorAction SilentlyContinue; $env:GH_CONFIG_DIR='C:\\Users\\YOUR_USERNAME\\.config\\gh-emu'; $env:GH_HOST='YOUR_EMU_HOST'; Write-Host 'gh auth: EMU (isolated)' -ForegroundColor Cyan }\"",
    "icon": "ms-appx:///ProfileIcons/pwsh.png",
    "startingDirectory": "%USERPROFILE%",
    "tabTitle": "GitHub EMU"
},
{
    "guid": "{generate-a-new-guid-2}",
    "name": "GitHub Public",
    "commandline": "pwsh.exe -NoLogo -NoExit -Command \"& { Remove-Item Env:GH_TOKEN,Env:GITHUB_TOKEN,Env:GH_ENTERPRISE_TOKEN,Env:GITHUB_ENTERPRISE_TOKEN -ErrorAction SilentlyContinue; $env:GH_CONFIG_DIR='C:\\Users\\YOUR_USERNAME\\.config\\gh-public'; $env:GH_HOST='github.com'; Write-Host 'gh auth: Public (isolated)' -ForegroundColor Green }\"",
    "icon": "ms-appx:///ProfileIcons/pwsh.png",
    "startingDirectory": "%USERPROFILE%",
    "tabTitle": "GitHub Public"
}
```

Replace `YOUR_USERNAME` with your Windows username and `YOUR_EMU_HOST` with the managed account hostname, normally `github.com`. To generate GUIDs, run `[guid]::NewGuid()` in PowerShell.

After saving, the two profiles appear in the Windows Terminal dropdown menu. Each one opens a pwsh session with `GH_CONFIG_DIR` pre-set.

## Step 4: Verify

Open each profile from the Windows Terminal dropdown and confirm:

```powershell
gh auth status
```

Each should show the correct account without any manual switching.

## Alternative: PowerShell Functions

If you prefer not to create separate terminal profiles, add these functions to your PowerShell profile (`code $PROFILE`):

```powershell
function Invoke-IsolatedGh {
    param([string]$ConfigDirectory, [string]$HostName, [object[]]$GhArguments)

    $names = 'GH_CONFIG_DIR', 'GH_HOST', 'GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN', 'GITHUB_ENTERPRISE_TOKEN'
    $previous = @{}
    foreach ($name in $names) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }

    try {
        $env:GH_CONFIG_DIR = $ConfigDirectory
        $env:GH_HOST = $HostName
        gh @GhArguments
    }
    finally {
        foreach ($name in $names) {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
        }
    }
}

function gh-emu {
    $hostName = if ($env:GH_EMU_HOST) { $env:GH_EMU_HOST } else { 'github.com' }
    Invoke-IsolatedGh "$HOME\.config\gh-emu" $hostName $args
}
function gh-pub { Invoke-IsolatedGh "$HOME\.config\gh-public" 'github.com' $args }
```

Then use them inline:

```powershell
gh-emu pr list --repo my-org/my-repo
gh-pub pr list --repo my-user/my-repo
```

## Alternative: Per-Directory Activation

If your repos are organized by account, you can set `GH_CONFIG_DIR` automatically based on the current directory. Add this to your PowerShell profile:

```powershell
function Set-GhContext {
    Remove-Item Env:GH_TOKEN, Env:GITHUB_TOKEN, Env:GH_ENTERPRISE_TOKEN, Env:GITHUB_ENTERPRISE_TOKEN -ErrorAction SilentlyContinue
    $dir = (Get-Location).Path
    if ($dir -like "*\emu-repos\*" -or $dir -like "*\work\*") {
        $env:GH_CONFIG_DIR = "$HOME\.config\gh-emu"
        $env:GH_HOST = if ($env:GH_EMU_HOST) { $env:GH_EMU_HOST } else { 'github.com' }
    } else {
        $env:GH_CONFIG_DIR = "$HOME\.config\gh-public"
        $env:GH_HOST = 'github.com'
    }
}

# Hook into directory changes (add to prompt function)
function prompt {
    Set-GhContext
    "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
}
```

Adjust the path patterns to match your directory structure.

This prompt hook owns the GitHub CLI context for the current PowerShell process. It removes inherited token overrides whenever the prompt runs. Use the wrapper functions instead if other commands in the same process need those variables.

## Troubleshooting

**`gh` still uses the wrong account:**
Check for token variables that override stored authentication, then inspect the active context:

```powershell
Get-ChildItem Env:GH_TOKEN, Env:GITHUB_TOKEN, Env:GH_ENTERPRISE_TOKEN, Env:GITHUB_ENTERPRISE_TOKEN -ErrorAction SilentlyContinue
Write-Host "Config: $env:GH_CONFIG_DIR"
Write-Host "Host: $env:GH_HOST"
gh auth status --hostname $env:GH_HOST
```

**Token expired:**
Re-authenticate in the correct context:

```powershell
$emuHost = if ($env:GH_EMU_HOST) { $env:GH_EMU_HOST } else { 'github.com' }
Remove-Item Env:GH_TOKEN, Env:GITHUB_TOKEN, Env:GH_ENTERPRISE_TOKEN, Env:GITHUB_ENTERPRISE_TOKEN -ErrorAction SilentlyContinue
$env:GH_CONFIG_DIR = "$HOME\.config\gh-emu"
$env:GH_HOST = $emuHost
gh auth login --hostname $emuHost --web
```

For the public account, use `"$HOME\.config\gh-public"` and `github.com`.

**Want to check both accounts at once:**

```powershell
gh-emu auth status
gh-pub auth status
```

The last example uses the wrapper functions from the preceding section, which restore the caller's environment after each command.

## References

- [GitHub CLI: Environment Variables](https://cli.github.com/manual/gh_help_environment)
- [GitHub Docs: Using Multiple Accounts](https://docs.github.com/en/github-cli/github-cli/using-multiple-accounts)

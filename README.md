# Isolated GitHub CLI Authentication for Multiple Accounts

When you work with both a GitHub EMU (Enterprise Managed User) account and a public GitHub account, `gh auth switch` changes auth globally. This means one terminal can interfere with another, and you can't have both accounts active at the same time.

The fix is `GH_CONFIG_DIR` -- an environment variable that tells `gh` where to store and read its configuration. By pointing each terminal at a separate config directory, each session gets fully isolated auth with zero cross-talk.

## How It Works

By default, `gh` stores all configuration (auth tokens, preferences, host settings) in a single directory (`~/.config/gh` on Linux/macOS, `%APPDATA%\GitHub CLI` on Windows). The `GH_CONFIG_DIR` environment variable overrides this location. When two terminals point to different config directories, they operate with completely independent credentials.

This approach is:

- **Parallel-safe** -- multiple terminals can run `gh` commands simultaneously without conflicts
- **Simpler than `gh auth switch`** -- no global state to manage or forget about
- **Secure** -- tokens stay in config files, not exposed as environment variables (unlike `GH_TOKEN`)

## Prerequisites

- [GitHub CLI (`gh`)](https://cli.github.com/) installed
- [PowerShell 7+](https://github.com/PowerShell/PowerShell/releases) installed
- [Windows Terminal](https://aka.ms/terminal) installed
- Two GitHub accounts (one EMU, one public -- or any two accounts)

## Step 1: Create Isolated Config Directories

Open any terminal and run:

```powershell
New-Item -ItemType Directory -Force -Path "$HOME\.config\gh-emu"
New-Item -ItemType Directory -Force -Path "$HOME\.config\gh-public"
```

## Step 2: Authenticate Each Account

Log in to your EMU account:

```powershell
$env:GH_CONFIG_DIR = "$HOME\.config\gh-emu"
gh auth login
```

Follow the prompts, selecting your EMU GitHub Enterprise host.

Then, in the same terminal (or a new one), log in to your public account:

```powershell
$env:GH_CONFIG_DIR = "$HOME\.config\gh-public"
gh auth login
```

Follow the prompts, selecting `github.com`.

Each directory now holds its own independent auth token and configuration.

## Step 3: Add Windows Terminal Profiles

Open your Windows Terminal `settings.json` (Settings > Open JSON file), and add these two entries to the `profiles.list` array:

```json
{
    "guid": "{generate-a-new-guid-1}",
    "name": "GitHub EMU",
    "commandline": "pwsh.exe -NoLogo -NoExit -Command \"& { $env:GH_CONFIG_DIR='C:\\Users\\YOUR_USERNAME\\.config\\gh-emu'; Write-Host 'gh auth: EMU (isolated)' -ForegroundColor Cyan }\"",
    "icon": "ms-appx:///ProfileIcons/pwsh.png",
    "startingDirectory": "%USERPROFILE%",
    "tabTitle": "GitHub EMU"
},
{
    "guid": "{generate-a-new-guid-2}",
    "name": "GitHub Public",
    "commandline": "pwsh.exe -NoLogo -NoExit -Command \"& { $env:GH_CONFIG_DIR='C:\\Users\\YOUR_USERNAME\\.config\\gh-public'; Write-Host 'gh auth: Public (isolated)' -ForegroundColor Green }\"",
    "icon": "ms-appx:///ProfileIcons/pwsh.png",
    "startingDirectory": "%USERPROFILE%",
    "tabTitle": "GitHub Public"
}
```

Replace `YOUR_USERNAME` with your Windows username. To generate GUIDs, run `[guid]::NewGuid()` in PowerShell.

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
function gh-emu { $env:GH_CONFIG_DIR = "$HOME\.config\gh-emu"; gh @args }
function gh-pub { $env:GH_CONFIG_DIR = "$HOME\.config\gh-public"; gh @args }
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
    $dir = (Get-Location).Path
    if ($dir -like "*\emu-repos\*" -or $dir -like "*\work\*") {
        $env:GH_CONFIG_DIR = "$HOME\.config\gh-emu"
    } else {
        $env:GH_CONFIG_DIR = "$HOME\.config\gh-public"
    }
}

# Hook into directory changes (add to prompt function)
function prompt {
    Set-GhContext
    "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
}
```

Adjust the path patterns to match your directory structure.

## Troubleshooting

**`gh` still uses the wrong account:**
Check which config directory is active:

```powershell
echo $env:GH_CONFIG_DIR
gh auth status
```

**Token expired:**
Re-authenticate in the correct context:

```powershell
$env:GH_CONFIG_DIR = "$HOME\.config\gh-emu"  # or gh-public
gh auth login
```

**Want to check both accounts at once:**

```powershell
Write-Host "--- EMU ---"; $env:GH_CONFIG_DIR="$HOME\.config\gh-emu"; gh auth status
Write-Host "--- Public ---"; $env:GH_CONFIG_DIR="$HOME\.config\gh-public"; gh auth status
```

## References

- [GitHub CLI: Environment Variables](https://cli.github.com/manual/gh_help_environment)
- [GitHub Docs: Using Multiple Accounts](https://docs.github.com/en/github-cli/github-cli/using-multiple-accounts)

# Git Submodules Upstream Remote Configuration

This repository contains scripts to automatically configure upstream remotes for git submodules based on an extended `.gitmodules` file format.

## Overview

When working with forked repositories as submodules, you often want to track both:
- **origin**: Your fork (for pushing changes)
- **upstream**: The original repository (for pulling updates)

These scripts automate the process of adding upstream remotes to all submodules by reading an extended `.gitmodules` file that includes `upstream` URL entries.

## Extended .gitmodules Format

The scripts expect a `.gitmodules` file with the standard format plus an additional `upstream` key:

```ini
[submodule "submodule-name"]
    path = path/to/submodule
    url = https://github.com/yourfork/repo.git
    upstream = https://github.com/original/repo.git
```

## Usage

### PowerShell (Windows/.NET)

```powershell
# Basic usage - process all submodules
.\setup-upstream-remotes.ps1

# With custom .gitmodules path
.\setup-upstream-remotes.ps1 -GitmodulesPath ".\path\to\.gitmodules"

# Dry run - preview changes without applying them
.\setup-upstream-remotes.ps1 -DryRun

# Combine options
.\setup-upstream-remotes.ps1 -GitmodulesPath ".\path\to\.gitmodules" -DryRun
```

### Bash (Linux/macOS)

```bash
# Basic usage - process all submodules
./setup-upstream-remotes.sh

# With custom .gitmodules path
./setup-upstream-remotes.sh ./path/to/.gitmodules

# Dry run - preview changes without applying them
./setup-upstream-remotes.sh --dry-run

# Combine options
./setup-upstream-remotes.sh ./path/to/.gitmodules --dry-run
```

## Features

### Both Scripts Provide

- **Parsing**: Correctly parses the extended `.gitmodules` file format
- **Validation**: 
  - Checks if `.gitmodules` file exists
  - Verifies submodule paths exist on disk
  - Confirms `.git` directory is present (submodule initialized)
  - Validates upstream URL is defined for each module
- **Smart Updates**:
  - Detects existing upstream remotes
  - Updates URLs if they've changed
  - Skips if already correctly configured
- **Dry Run Mode**: Preview all changes before applying
- **Comprehensive Reporting**:
  - Success count
  - Skip count (with reasons)
  - Error count
  - Per-module status indicators
- **Error Handling**: Graceful handling of missing paths or uninitialized submodules

### PowerShell Specific

- Uses native PowerShell error handling
- Color-coded output for better readability
- Detailed help via `Get-Help` command
- Proper exit codes for scripting integration

### Bash Specific

- Portable POSIX-compatible parsing
- Color-coded output with ANSI escape sequences
- Works across Linux, macOS, and WSL
- Proper error propagation with `set -o pipefail`

## Script Output Example

```
Reading .gitmodules from: .\.gitmodules

Processing: BlockChainExample
  Path:     BlockChainExample
  Upstream: https://github.com/mcbethr/BlockChainExample.git
  Status:   ✓ Upstream remote added

Processing: MSBuild.Sdk.SqlProj
  Path:     MSBuild.Sdk.SqlProj
  Upstream: https://github.com/rr-wfm/MSBuild.Sdk.SqlProj.git
  Status:   ✓ Upstream remote added

...

======================================
Summary:
  Processed: 28
  Skipped:   2
  Errors:    0
```

## Common Workflows

### Initial Setup

1. Add submodules with fork URLs and upstream entries to `.gitmodules`
2. Run `git submodule update --init --recursive` to clone submodules
3. Run the setup script to configure upstream remotes:

```powershell
.\setup-upstream-remotes.ps1
```

### Updating from Upstream

After setup, to fetch updates from the original repository:

```bash
cd path/to/submodule
git fetch upstream
git merge upstream/main  # or your target branch
```

### Verifying Configuration

Check that upstream remotes are correctly configured:

```bash
git -C path/to/submodule remote -v
# Should show:
# origin    https://github.com/yourfork/repo.git (fetch)
# origin    https://github.com/yourfork/repo.git (push)
# upstream  https://github.com/original/repo.git (fetch)
# upstream  https://github.com/original/repo.git (push)
```

## Requirements

### PowerShell Version
- PowerShell 3.0+ (Windows PowerShell) or
- PowerShell 7.0+ (PowerShell Core)
- Git for Windows installed and in PATH

### Bash Version
- Bash 4.0+ or compatible shell
- Git installed and in PATH
- Standard Unix utilities: `sed`, `grep`, etc.

## Error Handling

### Skip Reasons

The scripts will skip submodules in these cases:

| Condition | Reason |
|-----------|--------|
| No `path` defined | Submodule configuration incomplete |
| No `upstream` defined | No upstream URL provided |
| Path doesn't exist | Submodule not cloned or path incorrect |
| `.git` not found | Submodule not initialized |

### Error Cases

Errors are reported with details but don't stop processing other submodules.

## Integration with CI/CD

### GitHub Actions Example

```yaml
- name: Configure upstream remotes
  run: |
    if [[ "${{ runner.os }}" == "Windows" ]]; then
      pwsh ./setup-upstream-remotes.ps1
    else
      bash ./setup-upstream-remotes.sh
    fi
```

### Pre-commit Hook

Add to `.git/hooks/post-checkout`:

```bash
#!/bin/bash
# Update submodules and configure upstreams after checkout
if [[ -f .gitmodules ]]; then
  git submodule update --init --recursive
  bash ./setup-upstream-remotes.sh
fi
```

## Troubleshooting

### "No upstream defined" warnings

Some submodules may not have an upstream. This is normal if:
- The submodule is not a fork
- You maintain the original repository
- You want to track the fork only

These can be safely ignored or removed from the extended `.gitmodules` entries.

### ".git directory not found"

The submodule hasn't been initialized. Run first:

```bash
git submodule update --init --recursive
```

### URL Update Failed

Check that:
- Git has permission to modify the submodule
- The URL is valid and accessible
- The `.git/config` file isn't read-only

## Notes on .gitmodules

The `upstream` key is a custom extension not recognized by standard git. Standard git operations won't be affected by its presence, but:
- Don't commit changes made by these scripts to `.gitmodules`
- The `upstream` entries are informational only
- Standard `git submodule` commands ignore the `upstream` key

## Performance

- Scripts process 20-30 submodules in ~2-5 seconds
- Each submodule requires one git command
- Network checks are minimal (only git command overhead)

## Security Considerations

- Verify upstream URLs before running scripts
- Use HTTPS URLs to avoid potential MitM attacks
- Consider using SSH keys with `git@github.com:owner/repo.git` format
- Review the `.gitmodules` file contents before executing

## License

These scripts are provided as-is for managing submodule configurations.

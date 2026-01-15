# Git Branch Status Checker

Comprehensive tools to monitor and report how many commits your branches are **ahead** and **behind** compared to their upstream remotes.

## Overview

These tools help you:
- Quickly identify branches that need pulling or pushing
- Monitor fork synchronization with upstream repositories
- Batch-check all submodules for branch status
- Generate reports in multiple formats
- Visualize branch status in a dashboard

## Available Implementations

### 1. PowerShell Script (`check-branch-status.ps1`)
Best for Windows/.NET environments

**Features:**
- Native PowerShell with colored output
- Integrated help system (`Get-Help`)
- Parameter validation
- Supports JSON, CSV output formats

**Usage:**
```powershell
# Check current repository
.\check-branch-status.ps1

# Check specific submodule
.\check-branch-status.ps1 -Path ./submodule -RemoteName upstream

# Check all submodules
.\check-branch-status.ps1 -AllSubmodules

# With filters and formats
.\check-branch-status.ps1 -AllSubmodules -BranchPattern "feature/*" -Format json -Verbose
```

### 2. Bash Script (`check-branch-status.sh`)
Cross-platform for Linux/macOS/WSL

**Features:**
- POSIX-compatible shell scripting
- Colored output with proper terminal handling
- Efficient pattern matching
- Works everywhere Git is available

**Usage:**
```bash
# Check current repository
./check-branch-status.sh

# Check specific submodule
./check-branch-status.sh ./submodule --remote upstream

# Check all submodules
./check-branch-status.sh --all-submodules

# With filters and formats
./check-branch-status.sh --all-submodules --pattern "feature/*" --format json --verbose
```

### 3. C# Console Application (`GitBranchStatus.cs`)
For .NET developers and CI/CD integration

**Features:**
- Async/await for performance
- Structured output types
- JSON serialization support
- Easy integration into larger tools

**Compilation & Usage:**
```bash
# Compile
csc GitBranchStatus.cs

# Run
./GitBranchStatus.exe
./GitBranchStatus.exe ./submodule --remote upstream
./GitBranchStatus.exe --all-submodules --format json
```

Or with dotnet:
```bash
dotnet new console -n GitBranchStatus
# Copy GitBranchStatus.cs to Program.cs
dotnet run -- --all-submodules
```

### 4. React Dashboard (`BranchStatusDashboard.jsx`)
Visual monitoring component

**Features:**
- Real-time branch status visualization
- Interactive filtering by repository and status
- Summary statistics with color-coded cards
- Responsive design
- Sample data included (easy to connect to real data)

**Usage:**
```jsx
import BranchStatusDashboard from './BranchStatusDashboard';

export default function App() {
  return <BranchStatusDashboard />;
}
```

## Output Formats

### Table Format (Default)
```
BlockChainExample
────────────────────────────────────────────────────────────────────────────────────────────────────
Branch              Status                 Ahead      Behind
────────────────────────────────────────────────────────────────────────────────────────────────────
◆ main              ✓ Synced                 -          -
  feature/impl      ⬆ Ahead                  3          -

MSBuild.Sdk.SqlProj
────────────────────────────────────────────────────────────────────────────────────────────────────
Branch              Status                 Ahead      Behind
────────────────────────────────────────────────────────────────────────────────────────────────────
◆ develop           ⬇ Behind                 -          5
  feature/sql       ⬍ Diverged               2          3

======================================
Summary:
  Total Branches:    12
  ✓ Synced:          4
  ⬆ Ahead Only:      3
  ⬇ Behind Only:     3
  ⬍ Diverged:        2
  ⚠ Untracked:       0
```

### JSON Format
```json
{
  "timestamp": "2025-01-15T10:30:45Z",
  "remoteName": "upstream",
  "results": [
    {
      "repo": "BlockChainExample",
      "branch": "main",
      "remote": "upstream",
      "status": "✓ Synced",
      "ahead": 0,
      "behind": 0,
      "isDefault": true,
      "tracking": true
    },
    {
      "repo": "BlockChainExample",
      "branch": "feature/improvements",
      "remote": "upstream",
      "status": "⬆ Ahead",
      "ahead": 3,
      "behind": 0,
      "isDefault": false,
      "tracking": true
    }
  ]
}
```

### CSV Format
```csv
Repository,Branch,Remote,Status,Ahead,Behind,IsDefault,Tracking
BlockChainExample,main,upstream,✓ Synced,0,0,true,true
BlockChainExample,feature/improvements,upstream,⬆ Ahead,3,0,false,true
MSBuild.Sdk.SqlProj,develop,upstream,⬇ Behind,0,5,true,true
```

## Status Codes

| Icon | Status | Meaning |
|------|--------|---------|
| ✓ | Synced | Branch is fully synchronized with upstream |
| ⬆ | Ahead | Local branch has commits not in upstream |
| ⬇ | Behind | Upstream has commits not in local branch |
| ⬍ | Diverged | Both branches have unique commits |
| ⚠ | No remote branch | Remote branch doesn't exist |
| ⚠ | Untracked | No tracking relationship established |

## Common Tasks

### Check All Submodules
```powershell
# PowerShell
.\check-branch-status.ps1 -AllSubmodules -Verbose

# Bash
./check-branch-status.sh --all-submodules --verbose
```

### Filter by Branch Pattern
```bash
# Check only feature branches
./check-branch-status.sh --pattern "feature/*"

# Check only release branches
./check-branch-status.sh --pattern "release/*"
```

### Export to File
```powershell
# PowerShell
.\check-branch-status.ps1 -AllSubmodules -Format json | Out-File -Encoding UTF8 "branch-status.json"

# Bash
./check-branch-status.sh --all-submodules --format json > branch-status.json
```

### Find Branches Behind
```bash
# PowerShell - Show only branches that are behind
.\check-branch-status.ps1 | Where-Object { $_.Behind -gt 0 }

# Bash - Quick filter
./check-branch-status.sh | grep "Behind"
```

### Check Against Different Remote
```bash
# Check against origin instead of upstream
./check-branch-status.sh --remote origin

# Check against specific tracking remote
./check-branch-status.sh --remote fork
```

## Common Workflows

### Daily Sync Check
```bash
#!/bin/bash
# Daily-check.sh - Run this in a scheduled task/cron

./check-branch-status.sh --all-submodules --format json | \
  jq '.results[] | select(.ahead > 0 or .behind > 0)' | \
  mail -s "Branch Status Report" developer@company.com
```

### CI/CD Integration
```yaml
# GitHub Actions
- name: Check branch sync
  run: |
    ./check-branch-status.sh --all-submodules --format json > branch-status.json
    # Fail if any branches are diverged
    if grep -q '"diverged"' branch-status.json; then
      echo "⚠ Diverged branches detected"
      exit 1
    fi
```

### Pre-Merge Verification
```bash
# Check if branch is ready to merge
BRANCH=$(git rev-parse --abbrev-ref HEAD)
STATUS=$(./check-branch-status.sh --pattern "$BRANCH" --format json)

BEHIND=$(echo $STATUS | jq '.results[0].behind')
if [ $BEHIND -gt 0 ]; then
  echo "❌ Branch is $BEHIND commits behind. Please rebase."
  exit 1
fi
```

### Repository Maintenance Report
```powershell
# Generate detailed status report
$report = .\check-branch-status.ps1 -AllSubmodules -Format json | ConvertFrom-Json

$report.results | Group-Object repo | ForEach-Object {
  $repo = $_.Name
  $branches = $_.Group
  
  Write-Host "`n$repo" -ForegroundColor Cyan
  Write-Host "  Total: $($branches.Count)"
  Write-Host "  Behind: $($branches | Where { $_.behind -gt 0 } | Measure).Count"
  Write-Host "  Ahead: $($branches | Where { $_.ahead -gt 0 } | Measure).Count"
}
```

## Interpreting Results

### Synced Branch (✓)
```
main  ✓ Synced  -  -
```
Your branch matches upstream exactly. No action needed.

### Ahead Branch (⬆)
```
feature  ⬆ Ahead  5  -
```
You have 5 commits that aren't in upstream. Ready to push or create PR.

### Behind Branch (⬇)
```
develop  ⬇ Behind  -  3
```
Upstream has 3 new commits. You need to pull/rebase.

### Diverged Branch (⬍)
```
hotfix  ⬍ Diverged  2  4
```
Both sides have changes. Merge or rebase needed before pushing.

## Troubleshooting

### "No remote branch" Warning
This means the remote doesn't have this branch yet. Normal for new feature branches.

### "Remote not accessible" Error
Check that the remote is configured and accessible:
```bash
git remote -v
git fetch <remote-name>
```

### No upstream tracking
Branch tracking isn't set up. Configure it:
```bash
git branch --set-upstream-to=upstream/main main
# or
git push -u origin feature-name
```

### Timeout errors
For large repositories, increase git timeout:
```bash
export GIT_HTTP_CONNECT_TIMEOUT=30
export GIT_HTTP_LOW_SPEED_TIME=30
```

## Performance Notes

- **Typical performance:** 20-30 submodules checked in 2-5 seconds
- **Bottleneck:** Network latency during `git fetch`
- **Optimization:** Use `--pattern` to check specific branches only
- **Parallel processing:** Bash script can be modified to fetch multiple repos simultaneously

## Integration Examples

### Pre-commit Hook
```bash
#!/bin/bash
# .git/hooks/pre-commit

DIVERGED=$(./check-branch-status.sh --format json | jq '.results[] | select(.ahead > 0 and .behind > 0)')
if [ -n "$DIVERGED" ]; then
  echo "⚠ Warning: Working on a diverged branch"
  echo "Consider rebasing: git rebase upstream/main"
fi
```

### VS Code Task
```json
{
  "label": "Check Branch Status",
  "type": "shell",
  "command": "${workspaceFolder}/check-branch-status.sh",
  "args": ["--all-submodules"],
  "presentation": {
    "reveal": "always",
    "panel": "new"
  }
}
```

### PowerShell Profile Function
```powershell
function Show-BranchStatus {
  param([string]$Path = ".", [switch]$AllSubmodules)
  
  $params = @{
    Path = $Path
  }
  if ($AllSubmodules) { $params["AllSubmodules"] = $true }
  
  & ".\check-branch-status.ps1" @params
}
```

## Requirements

### PowerShell Script
- PowerShell 3.0+
- Git for Windows

### Bash Script
- Bash 4.0+
- Standard Unix tools (sed, grep, awk)
- Git

### C# Application
- .NET Core 3.1+ or .NET Framework 4.7.2+
- Git

### React Dashboard
- React 16.8+
- Tailwind CSS
- Modern browser

## Advanced Usage

### Custom Status Reporting
Create a wrapper to send notifications:

```bash
#!/bin/bash
./check-branch-status.sh --all-submodules --format json | jq -r '
  .results[] | 
  select(.behind > 5 or (.ahead > 0 and .behind > 0)) |
  "\(.repo)/\(.branch): \(.status) (↑\(.ahead) ↓\(.behind))"
' | while read line; do
  echo "$line"
  # Send notification: slack, email, webhook, etc.
done
```

### Branch Health Dashboard
Combine with other tools for comprehensive monitoring:

```javascript
async function getBranchHealth() {
  // Call your branch status script via Node.js
  const { exec } = require('child_process');
  const status = await execPromise('./check-branch-status.sh --all-submodules --format json');
  const data = JSON.parse(status);
  
  return {
    timestamp: data.timestamp,
    repositories: data.results.reduce((acc, r) => {
      if (!acc[r.repo]) acc[r.repo] = [];
      acc[r.repo].push(r);
      return acc;
    }, {}),
    healthScore: calculateHealth(data.results)
  };
}
```

## License & Attribution

These tools are provided for managing git repositories. They wrap standard git commands and add convenient reporting capabilities.

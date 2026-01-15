#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Shows how many commits each branch is ahead/behind compared to upstream
.DESCRIPTION
    Displays branch comparison status across all repositories or specific submodules
    Supports both local repositories and git submodules
.PARAMETER Path
    Path to repository or submodule (default: current directory)
.PARAMETER AllSubmodules
    Process all submodules in the repository
.PARAMETER GitmodulesPath
    Path to .gitmodules file when using -AllSubmodules
.PARAMETER RemoteName
    Remote name to compare against (default: upstream)
.PARAMETER BranchPattern
    Only show branches matching pattern (e.g., "feature/*", "main")
.PARAMETER Verbose
    Show detailed output including commit hashes
.PARAMETER Format
    Output format: "table", "json", "csv" (default: "table")
.EXAMPLE
    .\check-branch-status.ps1
    .\check-branch-status.ps1 -AllSubmodules
    .\check-branch-status.ps1 -Path ./MySubmodule -RemoteName upstream
    .\check-branch-status.ps1 -AllSubmodules -Format json
#>

param(
    [string]$Path = ".",
    [switch]$AllSubmodules,
    [string]$GitmodulesPath = ".\.gitmodules",
    [string]$RemoteName = "upstream",
    [string]$BranchPattern = "*",
    [switch]$Verbose,
    [ValidateSet("table", "json", "csv")]
    [string]$Format = "table"
)

$ErrorActionPreference = "Stop"

class BranchStatus {
    [string]$Repository
    [string]$Branch
    [string]$Remote
    [string]$RemoteBranch
    [int]$Ahead
    [int]$Behind
    [string]$Status
    [string]$LocalHash
    [string]$RemoteHash
    [bool]$IsDefault
    [bool]$TrackingOk
}

function Get-BranchComparison {
    param(
        [string]$RepoPath,
        [string]$RemoteName
    )
    
    $repoName = Split-Path $RepoPath -Leaf
    $results = @()
    
    try {
        # Verify git repository
        if (-not (Test-Path (Join-Path $RepoPath ".git"))) {
            Write-Warning "Not a git repository: $RepoPath"
            return $results
        }
        
        # Get all local branches
        $branches = & git -C $RepoPath branch --format='%(refname:short)' 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        
        if (-not $branches) {
            return $results
        }
        
        # Get default branch
        $defaultBranch = & git -C $RepoPath rev-parse --abbrev-ref origin/HEAD 2>$null | ForEach-Object { $_.Split('/')[-1] }
        if (-not $defaultBranch) {
            $defaultBranch = & git -C $RepoPath symbolic-ref refs/remotes/origin/HEAD 2>$null | ForEach-Object { $_.Split('/')[-1] }
        }
        
        # Fetch latest from remote
        & git -C $RepoPath fetch $RemoteName --quiet 2>$null
        
        foreach ($branch in $branches) {
            # Check if this branch matches the pattern
            if (-not (Test-Pattern $branch $BranchPattern)) {
                continue
            }
            
            # Get local branch commit hash
            $localHash = & git -C $RepoPath rev-parse $branch 2>$null
            if (-not $localHash) { continue }
            
            # Check for tracking branch
            $trackingBranch = & git -C $RepoPath rev-parse --abbrev-ref "${branch}@{u}" 2>$null
            
            if ([string]::IsNullOrWhiteSpace($trackingBranch) -or $trackingBranch -eq "${branch}@{u}") {
                # No upstream tracking - try remote branch
                $remoteBranchRef = "${RemoteName}/${branch}"
                
                # Check if remote branch exists
                $remoteExists = & git -C $RepoPath rev-parse --verify "${remoteBranchRef}" 2>$null
                if (-not $remoteExists) {
                    $status = [BranchStatus]@{
                        Repository = $repoName
                        Branch = $branch
                        Remote = $RemoteName
                        RemoteBranch = "N/A"
                        Ahead = 0
                        Behind = 0
                        Status = "⚠ No remote branch"
                        LocalHash = $localHash.Substring(0, [Math]::Min(7, $localHash.Length))
                        RemoteHash = "N/A"
                        IsDefault = $branch -eq $defaultBranch
                        TrackingOk = $false
                    }
                    $results += $status
                    continue
                }
                
                $trackingBranch = $remoteBranchRef
            }
            
            # Get remote branch commit hash
            $remoteHash = & git -C $RepoPath rev-parse $trackingBranch 2>$null
            if (-not $remoteHash) {
                $status = [BranchStatus]@{
                    Repository = $repoName
                    Branch = $branch
                    Remote = $RemoteName
                    RemoteBranch = $trackingBranch
                    Ahead = 0
                    Behind = 0
                    Status = "⚠ Remote not accessible"
                    LocalHash = $localHash.Substring(0, [Math]::Min(7, $localHash.Length))
                    RemoteHash = "N/A"
                    IsDefault = $branch -eq $defaultBranch
                    TrackingOk = $false
                }
                $results += $status
                continue
            }
            
            # Calculate ahead/behind
            $aheadBehind = & git -C $RepoPath rev-list --count --left-right "${trackingBranch}...${branch}" 2>$null
            
            if ($aheadBehind -match '^(\d+)\s+(\d+)$') {
                $behind = [int]$matches[1]
                $ahead = [int]$matches[2]
            } else {
                $ahead = 0
                $behind = 0
            }
            
            # Determine status
            $statusStr = switch -Exact ($ahead, $behind) {
                { $ahead -eq 0 -and $_ -eq 0 } { "✓ Synced" }
                { $ahead -gt 0 -and $_ -eq 0 } { "⬆ Ahead" }
                { $ahead -eq 0 -and $_ -gt 0 } { "⬇ Behind" }
                default { "⬍ Diverged" }
            }
            
            $status = [BranchStatus]@{
                Repository = $repoName
                Branch = $branch
                Remote = $RemoteName
                RemoteBranch = $trackingBranch
                Ahead = $ahead
                Behind = $behind
                Status = $statusStr
                LocalHash = $localHash.Substring(0, [Math]::Min(7, $localHash.Length))
                RemoteHash = $remoteHash.Substring(0, [Math]::Min(7, $remoteHash.Length))
                IsDefault = $branch -eq $defaultBranch
                TrackingOk = $true
            }
            
            $results += $status
        }
    }
    catch {
        Write-Error "Error processing repository at $RepoPath : $_"
    }
    
    return $results
}

function Test-Pattern {
    param([string]$Branch, [string]$Pattern)
    
    if ($Pattern -eq "*") { return $true }
    
    # Simple wildcard matching
    $regex = $Pattern.Replace(".", "\.").Replace("*", ".*")
    return $Branch -match "^$regex$"
}

function Format-TableOutput {
    param([array]$Results)
    
    if (-not $Results) {
        Write-Host "No branches found"
        return
    }
    
    # Group by repository
    $grouped = $Results | Group-Object -Property Repository
    
    foreach ($group in $grouped) {
        Write-Host "`n$($group.Name)" -ForegroundColor Cyan
        Write-Host (new-object string @('-', 100)) -ForegroundColor DarkGray
        
        $table = $group.Group | Select-Object @(
            @{ Label = "Branch"; Expression = { 
                $marker = if ($_.IsDefault) { "◆ " } else { "  " }
                $marker + $_.Branch 
            } }
            @{ Label = "Status"; Expression = { $_.Status } }
            @{ Label = "Ahead"; Expression = { if ($_.Ahead -gt 0) { 
                Write-Host $_.Ahead -ForegroundColor Green -NoNewline; "" 
            } else { "-" } } }
            @{ Label = "Behind"; Expression = { if ($_.Behind -gt 0) { 
                Write-Host $_.Behind -ForegroundColor Yellow -NoNewline; "" 
            } else { "-" } } }
        )
        
        $table | Format-Table -AutoSize
        
        if ($Verbose) {
            Write-Host "Detailed Info:" -ForegroundColor Gray
            foreach ($result in $group.Group) {
                $hashInfo = "$($result.LocalHash)...$($result.RemoteHash)"
                if ($result.TrackingOk) {
                    Write-Host "  $($result.Branch): Local=$($result.LocalHash) Remote=$($result.RemoteHash)" -ForegroundColor Gray
                } else {
                    Write-Host "  $($result.Branch): ⚠ $($result.Status)" -ForegroundColor Yellow
                }
            }
        }
    }
    
    # Print summary
    Print-Summary $Results
}

function Format-JsonOutput {
    param([array]$Results)
    
    $output = @{
        timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        remoteName = $RemoteName
        results = @()
    }
    
    foreach ($result in $Results) {
        $output.results += @{
            repository = $result.Repository
            branch = $result.Branch
            remote = $result.Remote
            remoteBranch = $result.RemoteBranch
            ahead = $result.Ahead
            behind = $result.Behind
            status = $result.Status
            tracking = $result.TrackingOk
            isDefault = $result.IsDefault
        }
    }
    
    $output | ConvertTo-Json | Write-Host
}

function Format-CsvOutput {
    param([array]$Results)
    
    Write-Host "Repository,Branch,Remote,Status,Ahead,Behind,IsDefault,Tracking"
    
    foreach ($result in $Results) {
        $line = @(
            $result.Repository,
            $result.Branch,
            $result.Remote,
            $result.Status,
            $result.Ahead,
            $result.Behind,
            $result.IsDefault,
            $result.TrackingOk
        ) -join ","
        
        Write-Host $line
    }
}

function Print-Summary {
    param([array]$Results)
    
    Write-Host "`n" + (new-object string @('=', 100)) -ForegroundColor DarkGray
    
    $synced = @($Results | Where-Object { $_.Ahead -eq 0 -and $_.Behind -eq 0 }).Count
    $ahead = @($Results | Where-Object { $_.Ahead -gt 0 }).Count
    $behind = @($Results | Where-Object { $_.Behind -gt 0 }).Count
    $diverged = @($Results | Where-Object { $_.Ahead -gt 0 -and $_.Behind -gt 0 }).Count
    $untracked = @($Results | Where-Object { -not $_.TrackingOk }).Count
    
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  Total Branches:    $($Results.Count)"
    Write-Host "  ✓ Synced:          $synced" -ForegroundColor Green
    Write-Host "  ⬆ Ahead Only:      $ahead" -ForegroundColor Cyan
    Write-Host "  ⬇ Behind Only:     $behind" -ForegroundColor Yellow
    Write-Host "  ⬍ Diverged:        $diverged" -ForegroundColor Red
    Write-Host "  ⚠ Untracked:       $untracked" -ForegroundColor Yellow
}

function Get-Submodules {
    param([string]$GitmodulesPath)
    
    if (-not (Test-Path $GitmodulesPath)) {
        return @()
    }
    
    $submodules = @()
    $content = Get-Content $GitmodulesPath -Raw
    $currentModule = $null
    $path = $null
    
    foreach ($line in $content -split "`n") {
        $line = $line.Trim()
        
        if ($line -match '^\[submodule "([^"]+)"\]') {
            $currentModule = $matches[1]
        }
        elseif ($line -match '^path\s*=\s*(.+)$' -and $currentModule) {
            $path = $matches[1]
            $submodules += @{ Name = $currentModule; Path = $path }
        }
    }
    
    return $submodules
}

# Main execution
try {
    $allResults = @()
    
    if ($AllSubmodules) {
        Write-Host "Processing all submodules...`n"
        
        $submodules = Get-Submodules $GitmodulesPath
        
        foreach ($submodule in $submodules) {
            if (Test-Path $submodule.Path -PathType Container) {
                Write-Host "Checking: $($submodule.Name)..."
                $results = Get-BranchComparison $submodule.Path $RemoteName
                $allResults += $results
            } else {
                Write-Warning "Submodule path not found: $($submodule.Path)"
            }
        }
    } else {
        $results = Get-BranchComparison $Path $RemoteName
        $allResults = $results
    }
    
    # Format output
    switch ($Format) {
        "json" { Format-JsonOutput $allResults }
        "csv" { Format-CsvOutput $allResults }
        default { Format-TableOutput $allResults }
    }
    
    # Return appropriate exit code
    $untracked = @($allResults | Where-Object { -not $_.TrackingOk }).Count
    exit $(if ($untracked -gt 0) { 1 } else { 0 })
}
catch {
    Write-Error "Fatal error: $_"
    if ($Verbose) {
        Write-Error $_.ScriptStackTrace
    }
    exit 1
}

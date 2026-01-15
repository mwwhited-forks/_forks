#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Configures upstream remotes for git submodules based on extended .gitmodules file
.DESCRIPTION
    Parses .gitmodules file entries containing upstream URL and adds them as git remotes
    to each submodule directory with the name 'upstream'
.PARAMETER GitmodulesPath
    Path to the .gitmodules file (default: ./.gitmodules in current directory)
.PARAMETER DryRun
    If specified, shows what would be done without actually running git commands
.EXAMPLE
    .\setup-upstream-remotes.ps1
    .\setup-upstream-remotes.ps1 -GitmodulesPath ".\path\to\.gitmodules" -DryRun
#>

param(
    [string]$GitmodulesPath = ".\.gitmodules",
    [switch]$DryRun
)

# Validate .gitmodules file exists
if (-not (Test-Path $GitmodulesPath)) {
    Write-Error "Error: .gitmodules file not found at: $GitmodulesPath"
    exit 1
}

Write-Host "Reading .gitmodules from: $GitmodulesPath`n"

# Parse .gitmodules file
$content = Get-Content $GitmodulesPath -Raw
$submodules = @{}
$currentModule = $null

foreach ($line in $content -split "`n") {
    $line = $line.Trim()
    
    # Match [submodule "name"] sections
    if ($line -match '^\[submodule "([^"]+)"\]') {
        $currentModule = $matches[1]
        if (-not $submodules.ContainsKey($currentModule)) {
            $submodules[$currentModule] = @{}
        }
    }
    # Match key = value pairs
    elseif ($line -match '^(\w+)\s*=\s*(.+)$' -and $currentModule) {
        $key = $matches[1]
        $value = $matches[2].Trim()
        $submodules[$currentModule][$key] = $value
    }
}

# Process each submodule
$successCount = 0
$skipCount = 0
$errorCount = 0

foreach ($moduleName in $submodules.Keys | Sort-Object) {
    $module = $submodules[$moduleName]
    
    if (-not $module.ContainsKey('path')) {
        Write-Warning "Skipping '$moduleName': no path defined"
        $skipCount++
        continue
    }
    
    if (-not $module.ContainsKey('upstream')) {
        Write-Warning "Skipping '$moduleName': no upstream URL defined"
        $skipCount++
        continue
    }
    
    $modulePath = $module['path']
    $upstreamUrl = $module['upstream']
    
    # Validate submodule directory exists
    if (-not (Test-Path $modulePath -PathType Container)) {
        Write-Warning "Skipping '$moduleName': path not found '$modulePath'"
        $skipCount++
        continue
    }
    
    Write-Host "Processing: $moduleName" -ForegroundColor Cyan
    Write-Host "  Path:     $modulePath"
    Write-Host "  Upstream: $upstreamUrl"
    
    try {
        # Check if upstream remote already exists
        $gitDir = Join-Path $modulePath ".git"
        
        if (-not (Test-Path $gitDir)) {
            Write-Warning "  Skipping: .git directory not found (submodule may not be initialized)"
            $skipCount++
            continue
        }
        
        # Get current remotes
        $remotes = & git -C $modulePath remote
        
        if ($remotes -contains 'upstream') {
            $currentUpstreamUrl = & git -C $modulePath remote get-url upstream
            
            if ($currentUpstreamUrl -eq $upstreamUrl) {
                Write-Host "  Status:   ✓ Upstream already configured correctly" -ForegroundColor Green
                $successCount++
            }
            else {
                Write-Host "  Warning:  Upstream remote exists with different URL" -ForegroundColor Yellow
                Write-Host "    Current: $currentUpstreamUrl"
                Write-Host "    Expected: $upstreamUrl"
                
                if ($DryRun) {
                    Write-Host "    [DRY RUN] Would update remote" -ForegroundColor Gray
                }
                else {
                    & git -C $modulePath remote set-url upstream $upstreamUrl
                    Write-Host "  Status:   ✓ Upstream remote updated" -ForegroundColor Green
                }
                $successCount++
            }
        }
        else {
            if ($DryRun) {
                Write-Host "  [DRY RUN] Would add upstream remote" -ForegroundColor Gray
            }
            else {
                & git -C $modulePath remote add upstream $upstreamUrl
                Write-Host "  Status:   ✓ Upstream remote added" -ForegroundColor Green
            }
            $successCount++
        }
    }
    catch {
        Write-Error "  Error processing module: $_"
        $errorCount++
    }
    
    Write-Host ""
}

# Summary
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Processed: $successCount"
Write-Host "  Skipped:   $skipCount"
Write-Host "  Errors:    $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { 'Yellow' } else { 'Green' })

if ($DryRun) {
    Write-Host "`n[DRY RUN MODE] No changes were made. Run without -DryRun to apply changes." -ForegroundColor Yellow
}

exit $(if ($errorCount -gt 0) { 1 } else { 0 })

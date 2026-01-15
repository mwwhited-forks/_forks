#!/bin/bash

# Script to check branch ahead/behind status compared to upstream remote
#
# Usage:
#   ./check-branch-status.sh [path] [--remote <name>] [--pattern <glob>] [--all-submodules]
#
# Examples:
#   ./check-branch-status.sh
#   ./check-branch-status.sh ./submodule --remote upstream
#   ./check-branch-status.sh --all-submodules --pattern "feature/*"
#   ./check-branch-status.sh --format json

set -o pipefail

# Default values
REPO_PATH="."
REMOTE_NAME="upstream"
BRANCH_PATTERN="*"
ALL_SUBMODULES=0
GITMODULES_PATH=".gitmodules"
VERBOSE=0
FORMAT="table"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --remote)
            REMOTE_NAME="$2"
            shift 2
            ;;
        --pattern)
            BRANCH_PATTERN="$2"
            shift 2
            ;;
        --all-submodules)
            ALL_SUBMODULES=1
            shift
            ;;
        --gitmodules)
            GITMODULES_PATH="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=1
            shift
            ;;
        --format)
            FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            REPO_PATH="$1"
            shift
            ;;
    esac
done

show_help() {
    cat << EOF
Check git branch ahead/behind status against upstream remote

Usage: $0 [path] [options]

Options:
  --remote <name>           Remote name to compare (default: upstream)
  --pattern <glob>          Branch pattern filter (default: *)
  --all-submodules          Check all submodules from .gitmodules
  --gitmodules <path>       Path to .gitmodules file
  --format <fmt>            Output format: table, json, csv (default: table)
  --verbose                 Show detailed information
  -h, --help               Show this help message

Examples:
  $0
  $0 ./submodule --remote upstream
  $0 --all-submodules --pattern "feature/*"
  $0 --format json
EOF
}

# Check if path is a git repository
is_git_repo() {
    local path=$1
    [[ -d "$path/.git" ]]
}

# Match branch name against pattern
match_pattern() {
    local branch=$1
    local pattern=$2
    
    if [[ "$pattern" == "*" ]]; then
        return 0
    fi
    
    # Convert glob pattern to regex
    local regex="^${pattern//./\\.}$"
    regex="${regex//\*/.\\*}"
    
    [[ $branch =~ $regex ]]
}

# Get branch comparison for a repository
get_branch_comparison() {
    local repo_path=$1
    local remote_name=$2
    local repo_name=$(basename "$repo_path")
    
    if ! is_git_repo "$repo_path"; then
        echo "Error: Not a git repository: $repo_path" >&2
        return 1
    fi
    
    # Fetch from remote (silent)
    git -C "$repo_path" fetch "$remote_name" --quiet 2>/dev/null || true
    
    # Get default branch
    local default_branch=$(git -C "$repo_path" rev-parse --abbrev-ref origin/HEAD 2>/dev/null | awk -F'/' '{print $NF}')
    
    # Get all branches
    local branches=$(git -C "$repo_path" branch --format='%(refname:short)' 2>/dev/null)
    
    while IFS= read -r branch; do
        [[ -z "$branch" ]] && continue
        
        # Match pattern
        if ! match_pattern "$branch" "$BRANCH_PATTERN"; then
            continue
        fi
        
        # Get local hash
        local local_hash=$(git -C "$repo_path" rev-parse "$branch" 2>/dev/null)
        [[ -z "$local_hash" ]] && continue
        
        local short_hash="${local_hash:0:7}"
        
        # Check for tracking branch
        local tracking=$(git -C "$repo_path" rev-parse --abbrev-ref "${branch}@{u}" 2>/dev/null)
        
        local remote_branch="$remote_name/$branch"
        
        if [[ -z "$tracking" ]] || [[ "$tracking" == "${branch}@{u}" ]]; then
            # Try remote branch
            if ! git -C "$repo_path" rev-parse --verify "$remote_branch" &>/dev/null; then
                # Remote branch doesn't exist
                output_result "$repo_name" "$branch" "$remote_name" "N/A" "0" "0" "⚠ No remote branch" "$short_hash" "N/A" "false" "false"
                continue
            fi
            tracking="$remote_branch"
        fi
        
        # Get remote hash
        local remote_hash=$(git -C "$repo_path" rev-parse "$tracking" 2>/dev/null)
        if [[ -z "$remote_hash" ]]; then
            output_result "$repo_name" "$branch" "$remote_name" "$tracking" "0" "0" "⚠ Remote not accessible" "$short_hash" "N/A" "false" "false"
            continue
        fi
        
        local remote_short="${remote_hash:0:7}"
        
        # Calculate ahead/behind
        local ahead_behind=$(git -C "$repo_path" rev-list --count --left-right "${tracking}...${branch}" 2>/dev/null)
        
        local behind=0
        local ahead=0
        if [[ "$ahead_behind" =~ ^([0-9]+)\ +([0-9]+)$ ]]; then
            behind="${BASH_REMATCH[1]}"
            ahead="${BASH_REMATCH[2]}"
        fi
        
        # Determine status
        local status="✓ Synced"
        if [[ $ahead -gt 0 && $behind -eq 0 ]]; then
            status="⬆ Ahead"
        elif [[ $ahead -eq 0 && $behind -gt 0 ]]; then
            status="⬇ Behind"
        elif [[ $ahead -gt 0 && $behind -gt 0 ]]; then
            status="⬍ Diverged"
        fi
        
        local is_default="false"
        [[ "$branch" == "$default_branch" ]] && is_default="true"
        
        output_result "$repo_name" "$branch" "$remote_name" "$tracking" "$ahead" "$behind" "$status" "$short_hash" "$remote_short" "$is_default" "true"
        
    done <<< "$branches"
}

output_result() {
    local repo=$1 branch=$2 remote=$3 remote_branch=$4 ahead=$5 behind=$6 status=$7 local_hash=$8 remote_hash=$9 is_default=${10} tracking_ok=${11}
    
    if [[ "$FORMAT" == "csv" ]]; then
        echo "$repo,$branch,$remote,$status,$ahead,$behind,$is_default,$tracking_ok"
    elif [[ "$FORMAT" == "json" ]]; then
        # Build JSON object (will be aggregated later)
        printf '{"repo":"%s","branch":"%s","remote":"%s","ahead":%d,"behind":%d,"status":"%s","isDefault":%s,"tracking":%s}\n' \
            "$repo" "$branch" "$remote" "$ahead" "$behind" "$status" "$is_default" "$tracking_ok"
    else
        # Store for table format
        echo "$repo|$branch|$status|$ahead|$behind|$is_default|$tracking_ok|$local_hash|$remote_hash"
    fi
}

# Parse submodules from .gitmodules
get_submodules() {
    local gitmodules_path=$1
    
    if [[ ! -f "$gitmodules_path" ]]; then
        return
    fi
    
    # Parse .gitmodules for submodule paths
    grep '^\[submodule' "$gitmodules_path" | sed 's/.*"\(.*\)".*/\1/' | while read -r submodule_name; do
        local path=$(grep -A 5 "\[submodule \"$submodule_name\"\]" "$gitmodules_path" | grep '^\s*path' | head -1 | sed 's/.*=\s*//')
        echo "$path"
    done
}

# Format table output
format_table() {
    local output=$1
    
    if [[ -z "$output" ]]; then
        echo "No branches found"
        return
    fi
    
    # Group by repository and display
    echo "$output" | while IFS='|' read -r repo branch status ahead behind is_default tracking_ok local_hash remote_hash; do
        if [[ -z "$current_repo" ]] || [[ "$current_repo" != "$repo" ]]; then
            if [[ -n "$current_repo" ]]; then
                echo ""
            fi
            current_repo="$repo"
            echo -e "${CYAN}${repo}${NC}"
            echo -e "${GRAY}$(printf '%.100s' $(printf '%0.s-' {1..100}))${NC}"
            echo -e "Branch${1:40}Status${1:50}Ahead  Behind"
            echo -e "${GRAY}$(printf '%.100s' $(printf '%0.s-' {1..100}))${NC}"
        fi
        
        local marker=" "
        [[ "$is_default" == "true" ]] && marker="◆"
        
        local color="$GREEN"
        [[ "$status" == "⬆"* ]] && color="$CYAN"
        [[ "$status" == "⬇"* ]] && color="$YELLOW"
        [[ "$status" == "⬍"* ]] && color="$RED"
        [[ "$status" == "⚠"* ]] && color="$YELLOW"
        
        local ahead_display="-"
        [[ $ahead -gt 0 ]] && ahead_display="$ahead"
        
        local behind_display="-"
        [[ $behind -gt 0 ]] && behind_display="$behind"
        
        printf "%s %-30s %b%-20s${NC} %6s  %6s\n" "$marker" "$branch" "$color" "$status" "$ahead_display" "$behind_display"
        
        if [[ $VERBOSE -eq 1 ]]; then
            echo -e "${GRAY}    Local: $local_hash  Remote: $remote_hash${NC}"
        fi
    done
}

# Format JSON output
format_json() {
    local output=$1
    
    echo "{"
    echo '  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",'
    echo '  "remoteName": "'$REMOTE_NAME'",'
    echo '  "results": ['
    
    local first=true
    echo "$output" | while IFS='|' read -r repo branch status ahead behind is_default tracking_ok local_hash remote_hash; do
        [[ -z "$repo" ]] && continue
        
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        
        printf '    {"repo":"%s","branch":"%s","status":"%s","ahead":%d,"behind":%d,"isDefault":%s,"tracking":%s}' \
            "$repo" "$branch" "$status" "$ahead" "$behind" "$is_default" "$tracking_ok"
    done
    
    echo ""
    echo "  ]"
    echo "}"
}

# Format CSV output
format_csv() {
    local output=$1
    
    echo "Repository,Branch,Status,Ahead,Behind,IsDefault,Tracking"
    echo "$output" | while IFS='|' read -r repo branch status ahead behind is_default tracking_ok local_hash remote_hash; do
        [[ -z "$repo" ]] && continue
        echo "$repo,$branch,$status,$ahead,$behind,$is_default,$tracking_ok"
    done
}

# Print summary statistics
print_summary() {
    local output=$1
    
    local total=0
    local synced=0
    local ahead_only=0
    local behind_only=0
    local diverged=0
    local untracked=0
    
    echo "$output" | while IFS='|' read -r repo branch status ahead behind is_default tracking_ok local_hash remote_hash; do
        [[ -z "$repo" ]] && continue
        
        ((total++))
        
        if [[ "$tracking_ok" != "true" ]]; then
            ((untracked++))
        elif [[ $ahead -eq 0 && $behind -eq 0 ]]; then
            ((synced++))
        elif [[ $ahead -gt 0 && $behind -eq 0 ]]; then
            ((ahead_only++))
        elif [[ $ahead -eq 0 && $behind -gt 0 ]]; then
            ((behind_only++))
        else
            ((diverged++))
        fi
    done
    
    echo -e "\n${GRAY}$(printf '%.100s' $(printf '%0.s=' {1..100}))${NC}"
    echo -e "${CYAN}Summary:${NC}"
    echo "  Total Branches:    $total"
    echo -e "  ${GREEN}✓ Synced:          $synced${NC}"
    echo -e "  ${CYAN}⬆ Ahead Only:      $ahead_only${NC}"
    echo -e "  ${YELLOW}⬇ Behind Only:     $behind_only${NC}"
    echo -e "  ${RED}⬍ Diverged:        $diverged${NC}"
    echo -e "  ${YELLOW}⚠ Untracked:       $untracked${NC}"
}

# Main execution
main() {
    local all_output=""
    
    if [[ $ALL_SUBMODULES -eq 1 ]]; then
        echo "Processing all submodules..."
        
        while IFS= read -r submodule_path; do
            [[ -z "$submodule_path" ]] && continue
            
            if [[ -d "$submodule_path" ]]; then
                echo "Checking: $submodule_path..."
                output=$(get_branch_comparison "$submodule_path" "$REMOTE_NAME")
                all_output="${all_output}${output}"$'\n'
            else
                echo -e "${YELLOW}⚠ Submodule path not found: $submodule_path${NC}" >&2
            fi
        done < <(get_submodules "$GITMODULES_PATH")
        
        echo ""
    else
        all_output=$(get_branch_comparison "$REPO_PATH" "$REMOTE_NAME")
    fi
    
    # Format and display output
    case "$FORMAT" in
        json)
            format_json "$all_output"
            ;;
        csv)
            format_csv "$all_output"
            ;;
        *)
            format_table "$all_output"
            echo ""
            print_summary "$all_output"
            ;;
    esac
}

main

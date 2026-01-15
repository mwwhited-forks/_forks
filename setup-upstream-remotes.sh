#!/bin/bash

# Script to configure upstream remotes for git submodules based on extended .gitmodules file
#
# Usage:
#   ./setup-upstream-remotes.sh [.gitmodules_path] [--dry-run]
#
# Example:
#   ./setup-upstream-remotes.sh
#   ./setup-upstream-remotes.sh ./.gitmodules --dry-run

set -o pipefail

GITMODULES_PATH="${1:-./.gitmodules}"
DRY_RUN=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        *)
            GITMODULES_PATH="$1"
            shift
            ;;
    esac
done

# Validate .gitmodules file exists
if [[ ! -f "$GITMODULES_PATH" ]]; then
    echo "Error: .gitmodules file not found at: $GITMODULES_PATH"
    exit 1
fi

echo "Reading .gitmodules from: $GITMODULES_PATH"
echo ""

# Counters
success_count=0
skip_count=0
error_count=0

# Parse .gitmodules and process each submodule
declare -A current_module
module_name=""
module_path=""
module_upstream=""

while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Match [submodule "name"] sections
    if [[ $line =~ ^\[submodule\ \"([^\"]+)\"\] ]]; then
        # Process previous module if exists
        if [[ -n "$module_name" && -n "$module_path" && -n "$module_upstream" ]]; then
            process_module "$module_name" "$module_path" "$module_upstream"
        fi
        
        module_name="${BASH_REMATCH[1]}"
        module_path=""
        module_upstream=""
    fi
    
    # Match path = value
    if [[ $line =~ ^path\ *=\ *(.+)$ ]]; then
        module_path="${BASH_REMATCH[1]}"
    fi
    
    # Match upstream = value
    if [[ $line =~ ^upstream\ *=\ *(.+)$ ]]; then
        module_upstream="${BASH_REMATCH[1]}"
    fi
done < "$GITMODULES_PATH"

# Process the last module if exists
if [[ -n "$module_name" && -n "$module_path" && -n "$module_upstream" ]]; then
    process_module "$module_name" "$module_path" "$module_upstream"
fi

# Function to process a single module (must be defined before use)
process_module() {
    local name=$1
    local path=$2
    local upstream=$3
    
    echo -e "\033[0;36mProcessing: $name\033[0m"
    echo "  Path:     $path"
    echo "  Upstream: $upstream"
    
    # Validate submodule directory exists
    if [[ ! -d "$path" ]]; then
        echo "  Skipping: path not found '$path'"
        ((skip_count++))
        echo ""
        return
    fi
    
    # Validate .git directory exists
    if [[ ! -d "$path/.git" ]]; then
        echo "  Skipping: .git directory not found (submodule may not be initialized)"
        ((skip_count++))
        echo ""
        return
    fi
    
    # Check if upstream remote already exists
    if git -C "$path" remote get-url upstream &>/dev/null; then
        current_upstream=$(git -C "$path" remote get-url upstream)
        
        if [[ "$current_upstream" == "$upstream" ]]; then
            echo "  Status:   ✓ Upstream already configured correctly"
            ((success_count++))
        else
            echo "  Warning:  Upstream remote exists with different URL"
            echo "    Current: $current_upstream"
            echo "    Expected: $upstream"
            
            if [[ $DRY_RUN -eq 1 ]]; then
                echo "    [DRY RUN] Would update remote"
            else
                if git -C "$path" remote set-url upstream "$upstream" 2>/dev/null; then
                    echo "  Status:   ✓ Upstream remote updated"
                    ((success_count++))
                else
                    echo "  Error:    Failed to update upstream remote"
                    ((error_count++))
                fi
            fi
        fi
    else
        if [[ $DRY_RUN -eq 1 ]]; then
            echo "  [DRY RUN] Would add upstream remote"
        else
            if git -C "$path" remote add upstream "$upstream" 2>/dev/null; then
                echo "  Status:   ✓ Upstream remote added"
                ((success_count++))
            else
                echo "  Error:    Failed to add upstream remote"
                ((error_count++))
            fi
        fi
    fi
    
    echo ""
}

# Print summary
echo "======================================"
echo -e "\033[0;36mSummary:\033[0m"
echo "  Processed: $success_count"
echo "  Skipped:   $skip_count"

if [[ $error_count -gt 0 ]]; then
    echo -e "  Errors:    \033[0;33m$error_count\033[0m"
else
    echo -e "  Errors:    \033[0;32m$error_count\033[0m"
fi

if [[ $DRY_RUN -eq 1 ]]; then
    echo ""
    echo -e "\033[0;33m[DRY RUN MODE] No changes were made. Run without --dry-run to apply changes.\033[0m"
fi

exit $([ $error_count -eq 0 ] && echo 0 || echo 1)

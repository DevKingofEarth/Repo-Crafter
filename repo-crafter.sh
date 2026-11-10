#!/usr/bin/env bash

# repo-crafter - A safe, interactive shell script for managing Git repositories across multiple platforms.

# Copyright (C) 2026 Dharrun Singh .M
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# For support, contact: dharrunsingh@gmail.com


# ===========================================================================================================
# repo-crafter.sh - A safe, interactive shell script for managing Git repositories across multiple platforms|
# ===========================================================================================================

set -euo pipefail

# ======================= CONFIGURATION & GLOBALS =============================
# Restricted directories
FORBIDDEN_DIRS=("/etc" "/root" "/bin" "/sbin" "/usr")

# Single source of truth for the reported version
SCRIPT_VERSION="1.1.2-beta"

# Path variables
PROJECT_ROOT="$HOME/Projects"
LOCAL_ROOT="$PROJECT_ROOT/Local_Projects"
REMOTE_ROOT="$PROJECT_ROOT/Remote_Projects"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\e[0;36m'
NC='\033[0m' # No Color

# Config file is in the SAME directory as this script
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/repo-crafterFiles"
CONFIG_FILE="$CONFIG_DIR/platforms.conf"

# Global associative arrays
declare -A PLATFORM_ENABLED
declare -A PLATFORM_API_BASE
declare -A PLATFORM_SSH_HOST
declare -A PLATFORM_REPO_DOMAIN
declare -A PLATFORM_TOKEN_VAR
declare -A PLATFORM_REPO_CHECK_ENDPOINT
declare -A PLATFORM_REPO_CHECK_METHOD
declare -A PLATFORM_REPO_CHECK_SUCCESS_KEY
declare -A PLATFORM_REPO_CREATE_ENDPOINT
declare -A PLATFORM_REPO_CREATE_METHOD
declare -A PLATFORM_REPO_LIST_ENDPOINT
declare -A PLATFORM_REPO_LIST_SUCCESS_KEY
declare -A PLATFORM_WORK_DIR
declare -A PLATFORM_PAYLOAD_TEMPLATE
declare -A PLATFORM_SSH_URL_TEMPLATE
declare -A PLATFORM_DISPLAY_FORMAT
declare -A PLATFORM_AUTH_HEADER
declare -A PLATFORM_AUTH_HEADER_NAME
declare -A PLATFORM_AUTH_QUERY_PARAM
declare -A PLATFORM_OWNER_NOT_FOUND_PATTERNS
declare -A PLATFORM_SSH_URL_FIELDS
declare -A PLATFORM_VISIBILITY_MAP
declare -A PLATFORM_AUTHENTICATED_USER_ENDPOINT
declare -A PLATFORM_AUTHENTICATED_USER_KEY
declare -A PLATFORM_ACCEPT_HEADER
declare -A PLATFORM_REPO_DELETE_ENDPOINT
declare -A PLATFORM_REPO_DELETE_METHOD
# declare -A PLATFORM_AUTH_HEADER_OVERRIDES
AVAILABLE_PLATFORMS=()
DRY_RUN_ACTIONS=()

# ======================= PLATFORM CONFIGURATION ===========================
# uses the platform.conf file to load available platforms
load_platform_config() {
    local current_section=""
    # Check if config file exists in script directory
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}❌ Configuration file 'platforms.conf' not found.${NC}"
        echo ""
        echo "Please create a 'platforms.conf' file in the same directory as this script:"
        echo -e "${YELLOW}  $CONFIG_DIR/platforms.conf${NC}"
        echo ""
        echo "With content like this example:"
        cat << 'EOF'
[github]
enabled = true
api_base = https://api.github.com
ssh_host = github.com
repo_domain = github.com
token_var = GITHUB_API_TOKEN
work_dir = github.com
repo_check_endpoint = /repos/{owner}/{repo}
repo_check_method = GET
repo_check_success_key = id
[gitlab]
enabled = true
api_base = https://gitlab.com/api/v4
ssh_host = gitlab.com
repo_domain = gitlab.com
token_var = GITLAB_API_TOKEN
work_dir = gitlab.com
repo_check_endpoint = /projects/{owner}%2F{repo}
repo_check_method = GET
repo_check_success_key = id
# You can add other platforms similarly
EOF
        echo ""
        echo -e "${YELLOW}Then set the environment variables mentioned above (GITHUB_API_TOKEN, etc.).${NC}"
        exit 1
    fi
    echo -n "Loading platform configuration... "
    # Reset arrays
    AVAILABLE_PLATFORMS=()
    for array_name in PLATFORM_ENABLED PLATFORM_API_BASE PLATFORM_SSH_HOST \
        PLATFORM_REPO_DOMAIN PLATFORM_TOKEN_VAR \
        PLATFORM_REPO_CHECK_ENDPOINT PLATFORM_REPO_CHECK_METHOD \
        PLATFORM_REPO_CHECK_SUCCESS_KEY PLATFORM_AUTH_HEADER PLATFORM_AUTH_HEADER_NAME \
        PLATFORM_PAYLOAD_TEMPLATE PLATFORM_SSH_URL_TEMPLATE \
        PLATFORM_DISPLAY_FORMAT \
        PLATFORM_OWNER_NOT_FOUND_PATTERNS \
        PLATFORM_AUTH_QUERY_PARAM \
        PLATFORM_SSH_URL_FIELDS \
        PLATFORM_VISIBILITY_MAP \
        PLATFORM_AUTHENTICATED_USER_ENDPOINT \
        PLATFORM_AUTHENTICATED_USER_KEY \
        PLATFORM_WORK_DIR ; do
        declare -gA "$array_name"
    done
    # Parse the INI file
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Remove comments and trim whitespace
        line=$(echo "$line" | sed 's/#.*$//;s/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$line" ]] && continue
        # Detect section header [platform]
        if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            PLATFORM_ENABLED["$current_section"]=false
            continue
        fi
        # Parse key = value pairs
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            case "$key" in
                enabled)
                    [[ "$value" == "true" ]] && PLATFORM_ENABLED["$current_section"]=true
                    ;;
                work_dir)
                    if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ || "$value" == "." || "$value" == ".." ]]; then
                        echo -e "${RED}❌ Invalid work_dir '$value' for [$current_section] in $CONFIG_FILE${NC}" >&2
                        echo -e "${YELLOW}   work_dir must be a single directory name: no '/', not '.' or '..'.${NC}" >&2
                        return 1
                    fi
                    PLATFORM_WORK_DIR["$current_section"]="$value"
                    ;;
                api_base|ssh_host|repo_domain|token_var|auth_header|auth_query_param|owner_not_found_patterns|ssh_url_fields|visibility_map|auth_header_name|authenticated_user_endpoint|authenticated_user_key|accept_header)
                    declare -g "PLATFORM_${key^^}"["$current_section"]="$value"
                    ;;
                repo_check_endpoint|repo_check_method|repo_check_success_key|repo_create_endpoint|repo_create_method|repo_list_endpoint|repo_list_success_key|repo_delete_endpoint|repo_delete_method|payload_template|ssh_url_template|display_format)
                    local array_key="${key^^}"
                    declare -g "PLATFORM_${array_key}"["$current_section"]="$value"
                    ;;
            esac
        fi
    done < "$CONFIG_FILE"
    # Default a missing work_dir to repo_domain, then to the platform name
    local fallback
    for platform in "${!PLATFORM_ENABLED[@]}"; do
        [[ -n "${PLATFORM_WORK_DIR[$platform]:-}" ]] && continue
        fallback="${PLATFORM_REPO_DOMAIN[$platform]:-}"
        if [[ ! "$fallback" =~ ^[A-Za-z0-9._-]+$ || "$fallback" == "." || "$fallback" == ".." ]]; then
            fallback="$platform"
        fi
        PLATFORM_WORK_DIR["$platform"]="$fallback"
    done
    # Build list of ENABLED platforms
    for platform in "${!PLATFORM_ENABLED[@]}"; do
        if [[ "${PLATFORM_ENABLED[$platform]}" == "true" ]] && \
           [[ -n "${PLATFORM_API_BASE[$platform]:-}" ]] && \
           [[ -n "${PLATFORM_TOKEN_VAR[$platform]:-}" ]]; then
            AVAILABLE_PLATFORMS+=("$platform")
        fi
    done
    if [[ ${#AVAILABLE_PLATFORMS[@]} -eq 0 ]]; then
        echo -e "${RED}❌ No properly configured platforms found in config.${NC}"
        echo -e "${YELLOW}   Check $CONFIG_FILE - ensure sections have enabled=true${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ Loaded ${#AVAILABLE_PLATFORMS[@]} platform(s): ${AVAILABLE_PLATFORMS[*]}${NC}"
    return 0
}

# Reliable platform selection function
# Menu goes to stderr (so user sees it), result to stdout (for capture)
select_platforms() {
    local prompt="$1"
    local allow_multiple="$2"
    local choices=()

    # Display menu to stderr (user will see it)
    {
        echo ""
        echo -e "${BLUE}$prompt${NC}"
        for i in "${!AVAILABLE_PLATFORMS[@]}"; do
            echo "  $((i+1))) ${AVAILABLE_PLATFORMS[i]}"
        done
        if [[ "$allow_multiple" == "true" ]]; then
            echo "  a) All platforms"
            echo "  m) Multiple selection (e.g., 1,3,5)"
        fi
        echo "  x) Cancel"
        echo ""
    } >&2

    # Read from stdin, fallback to /dev/tty if stdin is not a terminal
    # This handles cases where function is called within command substitution
    if [[ -t 0 ]]; then
        read -rp "Enter your choice: " input
    else
        read -rp "Enter your choice: " input </dev/tty
    fi

    [[ "$input" == "x" ]] && return 1

    if [[ "$allow_multiple" == "true" ]]; then
        if [[ "$input" == "a" ]]; then
            choices=("${AVAILABLE_PLATFORMS[@]}")
        elif [[ "$input" == "m" ]]; then
            echo "Enter platform numbers separated by commas (e.g., 1,3,5):" >&2
            if [[ -t 0 ]]; then
                read -rp "Selection: " multi_input
            else
                read -rp "Selection: " multi_input </dev/tty
            fi
            IFS=',' read -ra selected_indices <<< "$multi_input"
            for idx in "${selected_indices[@]}"; do
                if [[ ! "$idx" =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}Invalid selection. Enter a number.${NC}" >&2
                    continue
                fi
                local valid_idx=$((idx-1))
                if [[ $valid_idx -lt 0 || $valid_idx -ge ${#AVAILABLE_PLATFORMS[@]} ]]; then
                    echo -e "${RED}Invalid selection. Choose 1-${#AVAILABLE_PLATFORMS[@]}.${NC}" >&2
                    continue
                fi
                choices+=("${AVAILABLE_PLATFORMS[$valid_idx]}")
            done
        elif [[ "$input" =~ ^[0-9]+$ ]]; then
            # Single number selection
            idx=$((input-1))
            [[ $idx -ge 0 && $idx -lt ${#AVAILABLE_PLATFORMS[@]} ]] && choices+=("${AVAILABLE_PLATFORMS[$idx]}")
        else
            # Assume comma-separated list directly
            IFS=',' read -ra selected_indices <<< "$input"
            for idx in "${selected_indices[@]}"; do
                idx=$((idx-1))
                if [[ ! "$idx" =~ ^[0-9]+$ ]] || [[ $idx -lt 0 ]] || [[ $idx -ge ${#AVAILABLE_PLATFORMS[@]} ]]; then
                    continue
                fi
                choices+=("${AVAILABLE_PLATFORMS[$idx]}")
            done
        fi
    else
        # Single selection mode
        if [[ ! "$input" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid selection. Enter a number.${NC}" >&2
            return 1
        fi
        idx=$((input-1))
        if [[ $idx -ge 0 && $idx -lt ${#AVAILABLE_PLATFORMS[@]} ]]; then
            choices+=("${AVAILABLE_PLATFORMS[$idx]}")
        fi
    fi

    [[ ${#choices[@]} -eq 0 ]] && return 1

    # Output only the selected platforms (for command substitution)
    printf '%s\n' "${choices[@]}"
}

# Cleaner test function
test_platform_config() {
    echo -e "\n${BLUE}=== TESTING PLATFORM CONFIGURATION ===${NC}"

    # Skip option upfront
    if ! confirm_action "Run platform configuration tests?" "y" "Test config"; then
        echo -e "${YELLOW}Skipping tests.${NC}"
        return 0
    fi

    # Show loaded platforms
    echo "Available platforms: ${AVAILABLE_PLATFORMS[*]}"

    # Quick token check
    echo -e "\nToken status:"
    for platform in "${AVAILABLE_PLATFORMS[@]}"; do
        local token_var="${PLATFORM_TOKEN_VAR[$platform]}"
        local token_value="${!token_var:-}"
        if [[ -n "$token_value" ]]; then
            echo -e "  ${platform}: ${GREEN}✓ Token set${NC}"
        else
            echo -e "  ${platform}: ${RED}✗ Token NOT set${NC}"
        fi
        check_ssh_auth "${PLATFORM_SSH_HOST[$platform]}" "$platform" || echo -e "${YELLOW}⚠️  SSH test failed but continuing...${NC}"
    done

    echo ""
    read -rp "Press Enter to continue..." -n 1 || true
    echo ""
    warn_duplicate_remote_connections
    sleep 5
}

# ======================= CORE VALIDATION FUNCTIONS ===========================
# Check if a local Git repo exists (works for worktrees and submodules too)
check_local_exists() {
    local dir="${1:-}"
    [[ -n "$dir" ]] && git -C "$dir" rev-parse --git-dir >/dev/null 2>&1
}

# Ensure we're not in a system directory
is_safe_directory() {
    local target_dir="${1:-$(pwd)}"
    local canon
    canon=$(realpath -m -- "$target_dir" 2>/dev/null) || canon="$target_dir"

    # First check for root directory
    if [[ "$canon" == "/" ]]; then
        echo -e "${RED}❌ ERROR: Cannot operate in root directory '/'.${NC}"
        echo "Please run from a safe directory (e.g., ~/Projects)."
        return 1
    fi

    # Then check other forbidden prefixes (boundary-aware, so /etcetera is allowed)
    local dir dir_canon
    for dir in "${FORBIDDEN_DIRS[@]}"; do
        dir_canon=$(realpath -m -- "$dir" 2>/dev/null) || dir_canon="$dir"
        if [[ "$canon" == "$dir_canon" || "$canon" == "$dir_canon/"* ]]; then
            echo -e "${RED}❌ ERROR: Cannot operate in system directory '$dir'.${NC}"
            return 1
        fi
    done
    return 0
}

# True when a path resolves to a strict child of PROJECT_ROOT
_is_under_project_root() {
    local target="$1"
    [[ -n "$target" ]] || return 1

    local target_canon root_canon
    target_canon=$(realpath -m -- "$target" 2>/dev/null) || return 1
    root_canon=$(realpath -m -- "$PROJECT_ROOT" 2>/dev/null) || return 1

    [[ "$target_canon" == "$root_canon/"* ]]
}

# Check SSH authentication for a given host
check_ssh_auth() {
    local host="$1"
    local platform_name="$2"
    echo -n "Testing SSH connection to ${platform_name:-$host}... "

    # The host comes from platforms.conf; keep it to a DNS-name shape so it
    # cannot smuggle shell syntax or extra ssh arguments.
    if [[ ! "$host" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo -e "${RED}❌ Invalid SSH host in configuration: '$host'${NC}"
        return 1
    fi

    local -a ssh_cmd=(ssh -T -o ConnectTimeout=10 -o BatchMode=yes "git@$host")
    local ssh_output=""
    local exit_code=0

    # Execute SSH command and capture ALL output
    ssh_output=$(timeout 15 "${ssh_cmd[@]}" 2>&1) || exit_code=$?

    # SUCCESS if exit code is 0 OR 1 (GitHub returns 1 for "no shell access")
    if [[ $exit_code -eq 0 || $exit_code -eq 1 ]]; then
        echo -e "${GREEN}✅ Connected${NC}"
        echo -e "${BLUE}Output: ${ssh_output:0:80}...${NC}" >&2
        return 0
    else
        echo -e "${RED}❌ Failed (exit code: $exit_code)${NC}"
        echo -e "${YELLOW}Manual test command: ssh -T -o ConnectTimeout=10 -o BatchMode=yes git@$host${NC}" >&2
        echo -e "${YELLOW}Output: ${ssh_output:0:100}...${NC}" >&2
        return 1
    fi
}

# Validate a git remote URL or path: only https://, git@host:…, or local
# filesystem paths are accepted. This closes option-injection primitives
# (e.g. --upload-pack=…) and prevents other transports (ext::, file://,
# ssh:// with options) from reaching git clone / git ls-remote /
# git remote add.
# Returns: 0 valid, 1 invalid.
_validate_git_url() {
  local url="$1"
  [[ -n "$url" ]] || return 1
  # Reject anything starting with '-' (option injection) outright.
  [[ "$url" == -* ]] && return 1
  case "$url" in
    https://*|git@*:*|/*|./*|../*) return 0 ;;
  esac
  return 1
}

# Validate and sanitize project names to prevent injection attacks
validate_project_name() {
    local name="$1"
    local purpose="${2:-project name}"

    # Check if empty
    if [[ -z "$name" ]]; then
        echo -e "${RED}❌ $purpose cannot be empty${NC}" >&2
        return 1
    fi

    # Reject leading dashes and dots: the name may reach git as an argument
    # and could be parsed as a flag (e.g. `-rf`, `--help`).
    if [[ "$name" == -* || "$name" == .* ]]; then
        echo -e "${RED}❌ $purpose cannot start with '-' or '.'${NC}" >&2
        echo -e "${YELLOW}Only use: a-z, A-Z, 0-9, -, _ (must not start with - or .)${NC}" >&2
        return 1
    fi

    # Check for dangerous characters (command injection)
    if [[ "$name" =~ [\;\&\|\'\"\$\`\\\(\)\{\}\[\]\<\>] ]]; then
        echo -e "${RED}❌ $purpose contains invalid characters${NC}" >&2
        echo -e "${YELLOW}Only use: a-z, A-Z, 0-9, -, _${NC}"
        return 1
    fi

    # Check for path traversal attempts
    if [[ "$name" =~ \.\./|\.\.|/|\.\.\/ ]]; then
        echo -e "${RED}❌ $purpose contains path traversal attempts${NC}" >&2
        return 1
    fi

    # Validate against whitelist (a-z, A-Z, 0-9, -, _)
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}❌ $purpose contains invalid characters${NC}" >&2
        echo -e "${YELLOW}Only use: a-z, A-Z, 0-9, -, _${NC}"
        return 1
    fi

    # Check length (prevent buffer overflow issues)
    if [[ ${#name} -gt 100 ]]; then
        echo -e "${RED}❌ $purpose too long (max 100 characters)${NC}" >&2
        return 1
    fi

    return 0
}

# Sanitize a URL-derived repo name into one safe path component
# Dots become underscores so the result also passes validate_project_name
safe_dir_name() {
    local n="${1##*/}"
    n="${n%.git}"
    n="${n//[^A-Za-z0-9_-]/_}"
    n="${n#-}"
    [[ -z "$n" ]] && n="repo"
    printf '%s' "${n:0:100}"
}

# Check for existing Git repos with the same name in other directories
warn_duplicate_repo_name() {
    local project_name="$1"
    local parent_dir="$2"
    local existing_repos=()

    # Search the managed root only
    local search_dirs=("$PROJECT_ROOT")

    # Get the absolute path of the parent directory for accurate comparison
    local abs_parent_dir
    abs_parent_dir=$(realpath -s "$parent_dir" 2>/dev/null || echo "$parent_dir")

    echo -n "Scanning for existing repos named '$project_name'... "

    # Search only in our specified project directories
    while IFS= read -r git_dir; do

        local repo_dir=$(dirname "$git_dir")
        local dir_name=$(basename "$repo_dir")

        # Get the absolute path of the found repo
        local abs_repo_dir
        abs_repo_dir=$(realpath -s "$repo_dir" 2>/dev/null || echo "$repo_dir")

        # Check if: 1) names match, AND 2) it's NOT within our target parent directory
        if [[ "$dir_name" == "$project_name" ]] && \
           [[ "$abs_repo_dir" != "$abs_parent_dir"* ]]; then
            existing_repos+=("$repo_dir")
        fi
    done < <(find "${search_dirs[@]}" -type d -name ".git" 2>/dev/null)

    if [[ ${#existing_repos[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  FOUND${NC}"
        echo -e "${YELLOW}Found ${#existing_repos[@]} existing repository(ies) with the same name:${NC}"
        for repo in "${existing_repos[@]}"; do
            echo -e "  - ${YELLOW}$repo${NC}"
        done
        echo -e "${YELLOW}You might want to use a different name to avoid confusion.${NC}"
        confirm_action "Continue creating a NEW repository with this name?" || return 1
    else
        echo -e "${GREEN}✅ Clear${NC}"
    fi
    return 0
}

# Warn about existing remote repos with similar names
# Uses the platform's API to list user repos and warn of similar names
warn_similar_remote_repos() {
    local platform="$1"
    local new_name="$2"
    local user_name="$3"

    echo -n "Checking for similar repositories on $platform... "

    local endpoint="${PLATFORM_REPO_LIST_ENDPOINT[$platform]}"
    if [[ -z "$endpoint" ]]; then
        echo -e "${YELLOW}⚠️  Skipped (list not configured).${NC}"
        return 0
    fi

    local response
    response=$(platform_api_call "$platform" "$endpoint" "GET")

    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        echo -e "${YELLOW}⚠️  API call failed.${NC}"
        return 0
    fi

    # Use jq to find repos where the name contains the new_name (case-insensitive)
    local similar_repos
    similar_repos=$(echo "$response" | jq -r --arg new_name "$new_name" \
        '.[] | select(.name | test($new_name; "i")) | .name' | head -5)

    if [[ -n "$similar_repos" ]]; then
        echo -e "${YELLOW}⚠️  FOUND${NC}"
        echo -e "${YELLOW}  Existing $platform repos with similar names:${NC}"
        while IFS= read -r repo; do
            echo -e "    - $repo"
        done <<< "$similar_repos"
        echo ""
        return 0 # Warning only; callers continue
    else
        echo -e "${GREEN}✅ Clear${NC}"
        return 0
    fi
}

# Scans defined project directories and warns if multiple local folders point to the same remote
warn_duplicate_remote_connections() {
    local search_dirs=("$REMOTE_ROOT" "$LOCAL_ROOT") # Scan both trees
    echo -n "Checking for duplicate remote connections... "

    # Use associative array: key=remote_url, value="list_of_paths"
    declare -A remote_map
    local duplicate_found=0

    while IFS= read -r git_dir; do
        local repo_dir=$(dirname "$git_dir")
        local remote_url
        remote_url=$(git -C "$repo_dir" remote get-url origin 2>/dev/null || git -C "$repo_dir" remote get-url github 2>/dev/null || echo "")

        if [[ -n "$remote_url" ]]; then
            remote_map["$remote_url"]+="|$repo_dir"
        fi
    done < <(find "${search_dirs[@]}" -type d -name ".git" 2>/dev/null)

    # Check which remotes have more than one path
    for url in "${!remote_map[@]}"; do
        local paths="${remote_map[$url]}"
        # Count the non-empty path entries
        local count=$(echo "$paths" | tr '|' '\n' | grep -c .)

        if [[ $count -gt 1 ]]; then
            if [[ $duplicate_found -eq 0 ]]; then
                echo -e "${YELLOW}⚠️  WARNING${NC}"
                duplicate_found=1
            fi
            echo -e "${YELLOW}  Remote: $(_redact_url_credentials "$url")${NC}"
            echo "$paths" | tr '|' '\n' | grep -v "^$" | while IFS= read -r path; do
                echo -e "    -> $path"
            done
            echo ""
        fi
    done

    if [[ $duplicate_found -eq 0 ]]; then
        echo -e "${GREEN}✅ Clear${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Multiple local directories are connected to the same remote."
        echo -e "  This can cause confusion when pushing/pulling.${NC}"
    fi
    printf "\n" >&2
    return 0
}

# ========================================= REPOSITORIES AND REMOTE FUNCTIONS ===================================
# Generic function to call a platform's API
platform_api_call() {
    local platform="$1"
    local endpoint="$2"
    local method="${3:-GET}"
    local data="${4:-}"
    local max_retries=3
    local retry_delay=2

    # Get platform configuration
    local api_base="${PLATFORM_API_BASE[$platform]}"
    local token_var_name="${PLATFORM_TOKEN_VAR[$platform]}"
    local token_value="${!token_var_name:-}"
    local auth_template="${PLATFORM_AUTH_HEADER[$platform]:-Bearer {token}}"
    local auth_header_name="${PLATFORM_AUTH_HEADER_NAME[$platform]:-Authorization}"

    # Platform validation
    if [[ -z "$api_base" ]]; then
        echo -e "${RED}❌ No API base URL configured for platform: $platform${NC}" >&2
        return 1
    fi

    if [[ ! "$token_var_name" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
        echo -e "${RED}❌ Invalid token variable name configuration for platform: $platform${NC}" >&2
        return 1
    fi

    if [[ -z "$token_value" ]]; then
        echo -e "${RED}❌ Token for '$platform' is not set in environment${NC}" >&2
        echo -e "${YELLOW}Set: export $token_var_name=your_token${NC}"
        return 1
    fi

    if [[ "$api_base" != https://* ]]; then
        echo -e "${RED}❌ API base URL must use HTTPS for platform: $platform${NC}" >&2
        echo -e "${YELLOW}Current: $api_base${NC}"
        echo -e "${YELLOW}HTTPS is required for secure API communication.${NC}"
        return 1
    fi

    # DRY RUN mode handling
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN] API call:${NC}"
        echo "  Platform: $platform"
        echo "  Method: $method"
        echo "  Endpoint: $endpoint"
        [[ -n "$data" ]] && echo "  Data: $data"
        echo -e "${YELLOW}No actual API call made in DRY RUN mode${NC}"
        return 0
    fi

    ### curl_args initialization
    # Get Accept header from platform config, default to application/json
    local accept_header="${PLATFORM_ACCEPT_HEADER[$platform]:-application/json}"
    local curl_args=(-sS --fail --fail-with-body -w "\n%{http_code}" -X "$method" -H "Accept: $accept_header" -H "Content-Type: application/json" --max-time 30)

    ### authentication

    # Build auth header value from template
    # SAFE TOKEN REPLACEMENT (no sed, no injection risk)
    local auth_header_value=""
    if [[ "$auth_template" == *"{token}"* ]]; then
        # Simple, secure string replacement
        auth_header_value="${auth_template//\{token\}/$token_value}"
    else
        auth_header_value="$token_value"
    fi

    # SAFE CLEANUP: Remove ONLY stray braces using pure bash
    auth_header_value="${auth_header_value%%\}*}"  # Remove trailing }
    auth_header_value="${auth_header_value##\{*}"   # Remove leading {

    # TRIM WHITESPACE SAFELY
    auth_header_value="${auth_header_value#"${auth_header_value%%[![:space:]]*}"}"  # Leading
    auth_header_value="${auth_header_value%"${auth_header_value##*[![:space:]]}"}"   # Trailing

    # SECURITY: NEVER LOG FULL TOKENS IN DEBUG
#     local safe_token_preview="${token_value:0:4}...${token_value: -4}"
#     echo -e "${YELLOW}[DEBUG] Token preview (safe): $safe_token_preview${NC}" >&2
#     echo -e "${YELLOW}[DEBUG] Final auth header: $auth_header_name: ${auth_header_value:0:15}...${NC}" >&2

    # Keep the token out of the process command line: curl reads the auth
    # header from a 0600 file. argv (and therefore ps/proc) only sees the path.
    auth_header_name="${auth_header_name//$'\r'/}"
    auth_header_name="${auth_header_name//$'\n'/}"
    auth_header_value="${auth_header_value//$'\r'/}"
    auth_header_value="${auth_header_value//$'\n'/}"

    local header_file=""
    header_file=$(mktemp "${TMPDIR:-/tmp}/repo-crafter-hdr.XXXXXX") || {
        echo -e "${RED}❌ Could not create a temporary auth header file${NC}" >&2
        return 1
    }
    chmod 600 "$header_file" 2>/dev/null || true
    if ! printf '%s: %s\n' "$auth_header_name" "$auth_header_value" > "$header_file"; then
        rm -f "$header_file"
        echo -e "${RED}❌ Could not write the temporary auth header file${NC}" >&2
        return 1
    fi

    # ADD TO CURL ARGS
    curl_args+=(-H "@$header_file")

    [[ -n "$data" ]] && curl_args+=(-d "$data")

    # DEBUG: Show the request. The token is in the header file, never in argv.
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo -e "${YELLOW}[DEBUG] API Call: ${NC}" >&2
        echo "curl ${curl_args[*]} \"${api_base}${endpoint}\"" >&2
    fi

    # Execute with retries
    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        local response
        response=$(curl "${curl_args[@]}" "${api_base}${endpoint}" 2>&1)
        local http_code="${response##*$'\n'}"
        local body="${response%$'\n'*}"

        # 202 is GitLab's documented response for an accepted project delete.
        if [[ "$http_code" =~ ^(200|201|202|204)$ ]]; then
            rm -f "$header_file"
            echo "$body"
            return 0
        fi

        # Handle errors
        case "$http_code" in
            401)
                rm -f "$header_file"
                echo -e "${RED}❌ Authentication failed for $platform${NC}" >&2
                return 1
                ;;
            403|404)
                rm -f "$header_file"
                echo -e "${RED}❌ Error $http_code from $platform${NC}" >&2
                echo -e "${YELLOW}Possible causes:${NC}" >&2
                echo -e "  • Token lacks required permissions (need 'repo' scope for GitHub)" >&2
                echo -e "  • Repository may already exist with that name" >&2
                echo -e "  • API rate limit exceeded" >&2
                echo -e "${YELLOW}Hint: Run './repo-crafter.sh --debug' to see API details${NC}" >&2
                return 1
                ;;
            *)
                if [[ $attempt -lt $max_retries ]]; then
                    echo -e "${YELLOW}⚠️  Attempt $attempt failed ($http_code). Retrying in $retry_delay seconds...${NC}" >&2
                    sleep $retry_delay
                    ((retry_delay *= 2))
                else
                    rm -f "$header_file"
                    echo -e "${RED}❌ API call failed after $max_retries attempts${NC}" >&2
                    return 1
                fi
                ;;
        esac
        ((attempt++))
    done
    rm -f "$header_file"
    return 1
}

# List existing remote repositories for a platform
list_remote_repos() {
    local platform="$1"
    echo -n "Fetching repositories from $platform... "
    local response
    response=$(platform_api_call "$platform" "${PLATFORM_REPO_LIST_ENDPOINT[$platform]}" "GET")
    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        echo -e "${RED}❌ Failed${NC}"
        return 1
    fi
    # Check if we got valid repos
    if ! echo "$response" | jq -e '.[]' >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  No repositories found${NC}"
        return 0
    fi
    echo -e "${GREEN}✅ Found${NC}"

    # PLATFORM-SPECIFIC JQ FILTERS
    if [[ "$platform" == "github" ]]; then
        echo "$response" | jq -r '.[] | "\(.name) (\(.visibility)) - git@github.com:\(.owner.login)/\(.name).git"'
    elif [[ "$platform" == "gitlab" ]]; then
        echo "$response" | jq -r '.[] | "\(.name) (\(.visibility)) - git@gitlab.com:\(.path_with_namespace).git"'
    else
        # Generic fallback (you probably don't need this yet)
        echo "$response" | jq -r '.[] | "\(.name // "unnamed") (\(.visibility // "unknown"))"'
    fi

    ### Always return success when we reach this point ###
    return 0
}

# Function to get authenticated username from platform API
get_authenticated_user() {
    local platform="$1"
    local endpoint="${PLATFORM_AUTHENTICATED_USER_ENDPOINT[$platform]:-}"
    local key="${PLATFORM_AUTHENTICATED_USER_KEY[$platform]:-}"

    if [[ -z "$endpoint" ]] || [[ -z "$key" ]]; then
        echo -e "${YELLOW}⚠️  Platform $platform doesn't support authenticated user lookup${NC}" >&2
        return 1
    fi

    local response
    response=$(platform_api_call "$platform" "$endpoint" "GET")

    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        echo -e "${RED}❌ Failed to get authenticated user for $platform${NC}" >&2
        return 1
    fi

    local username
    username=$(echo "$response" | jq -r "$key // empty" 2>/dev/null || echo "")

    if [[ -z "$username" ]]; then
        echo -e "${RED}❌ Could not extract username from API response${NC}" >&2
        return 1
    fi

    echo "$username"
}

# Creating a new repository in remote platform of choice
create_remote_repo() {
    local platform="$1" repo_name="$2" visibility="$3" user_name="$4"

    if ! validate_project_name "$repo_name" "repository name"; then
        return 1
    fi

    # Get authenticated username from API (overrides the passed user_name)
    local api_user_name
    if api_user_name=$(get_authenticated_user "$platform"); then
        user_name="$api_user_name"
        echo -e "${BLUE}Using authenticated user: $user_name${NC}" >&2
    else
        echo -e "${YELLOW}⚠️  Falling back to provided username: $user_name${NC}" >&2
    fi

    # 2. Get template - use direct assignment to avoid bash brace interpretation
    local template
    if [[ -n "${PLATFORM_PAYLOAD_TEMPLATE[$platform]:-}" ]]; then
        template="${PLATFORM_PAYLOAD_TEMPLATE[$platform]}"
    else
        template='{"name":"{repo}"}'
    fi

    # 3. Simple placeholder replacement (your complex logic breaks things)
    template="${template//\{repo\}/$(printf '%s' "$repo_name" | jq -sRr @uri)}"
    template="${template//\{owner\}/$(printf '%s' "$user_name" | jq -sRr @uri)}"

    # Handle {private} placeholder only
    if [[ "$visibility" == "private" ]]; then
        template="${template//\{private\}/true}"
    else
        template="${template//\{private\}/false}"
    fi

    # Clean up any unused placeholders
    template="${template//\{private\}/}"

    echo -n "Creating repository on $platform... " >&2

    # Send request
    local response
    response=$(platform_api_call "$platform" "${PLATFORM_REPO_CREATE_ENDPOINT[$platform]}" "POST" "$template")

    # 4. Error handling with configurable patterns
    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        echo -e "${RED}❌ API failed${NC}" >&2

        local error_msg=$(echo "$response" | jq -r '.message // .error // "Unknown error"' 2>/dev/null || echo "$response")
        echo -e "${YELLOW}Error: ${error_msg:0:100}...${NC}" >&2

        # Check if error matches configurable patterns
        local patterns="${PLATFORM_OWNER_NOT_FOUND_PATTERNS[$platform]}"
        local should_fallback=false

        if [[ -n "$patterns" ]]; then
            IFS=',' read -ra pattern_array <<< "$patterns"
            for pattern in "${pattern_array[@]}"; do
                if echo "$error_msg" | grep -qi "$pattern"; then
                    should_fallback=true
                    break
                fi
            done
        fi

        if [[ "$should_fallback" == "true" ]]; then
            echo -e "${YELLOW}⚠️  Owner '$user_name' not found. Trying authenticated user...${NC}" >&2
            # ... rest of fallback logic from your original function ...
        else
            return 1
        fi
    else
        echo -e "${GREEN}✅ Created${NC}" >&2
    fi

    # 5. Extract SSH URL using configurable fields
    local ssh_url=""

    # Try configurable fields first
    local url_fields="${PLATFORM_SSH_URL_FIELDS[$platform]}"
    if [[ -n "$url_fields" ]]; then
        IFS=',' read -ra field_array <<< "$url_fields"
        for field in "${field_array[@]}"; do
            # Trim whitespace from field name
            field=$(echo "$field" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            ssh_url=$(echo "$response" | jq -r ".$field // empty" 2>/dev/null || echo "")
            [[ -n "$ssh_url" ]] && break
        done
    fi

    # Fallback to common fields
    if [[ -z "$ssh_url" ]]; then
        ssh_url=$(echo "$response" | jq -r '.ssh_url // .ssh_url_to_repo // .clone_url // empty' 2>/dev/null || echo "")
    fi

    # Final fallback to template
    if [[ -z "$ssh_url" ]]; then
        local ssh_template="${PLATFORM_SSH_URL_TEMPLATE[$platform]:-git@{ssh_host}:{owner}/{repo}.git}"
        ssh_url="${ssh_template//\{ssh_host\}/${PLATFORM_SSH_HOST[$platform]}}"
        ssh_url="${ssh_url//\{owner\}/$user_name}"
        ssh_url="${ssh_url//\{repo\}/$repo_name}"
    fi

    if [[ -n "$ssh_url" ]]; then
        echo "$ssh_url"
        return 0
    else
        echo "ERROR: Failed to create repository (no SSH URL generated)" >&2
        return 1
    fi
}

# Unified function to sync local branch with remote
# Returns: 0 on success, 1 on failure/cancellation
sync_with_remote() {
    local platform="$1"
    local remote_url="$2"
    local current_branch="${3:-}"
    local dry_run_mode="${DRY_RUN:-false}"  # Use global DRY_RUN if available

    # Reject option-injection / non-standard transports before git sees the URL.
    _validate_git_url "$remote_url" || {
        echo -e "${RED}❌ Invalid remote URL: '$remote_url'${NC}" >&2
        echo -e "${YELLOW}   Only https://… or git@host:… URLs are accepted.${NC}" >&2
        return 1
    }

    # Get current branch if not provided
    if [[ -z "$current_branch" ]]; then
        current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
        if [[ -z "$current_branch" ]]; then
            echo -e "${RED}❌ Cannot determine the current branch (detached HEAD?).${NC}"
            return 1
        fi
    fi

    # If this project has a manifest, report drift before changing anything.
    if [[ -f "repo-crafter.yml" ]]; then
        manifest_reconcile "$PWD" "true" || true
    fi

    echo -e "\n${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       FETCH & INTEGRATION             ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"

    # Check remote accessibility with timeout
    echo -n "Checking remote accessibility... "
    # A reachable but empty repository exits non-zero with --exit-code, so do
    # not use it here: an empty remote is exactly what a new repo looks like.
    if timeout 5 git ls-remote -- "$remote_url" &>/dev/null; then
        echo -e "${GREEN}✓ Accessible${NC}"
    else
        echo -e "${RED}✗ Cannot access remote${NC}"
        echo -e "${YELLOW}  The remote may not exist or you lack permissions.${NC}"

        if [[ "$dry_run_mode" != "true" ]] && confirm_action "Continue without synchronization?" "n" "Skip sync"; then
            return 0
        fi
        return 1
    fi

    # Fetch remote state
    echo -n "Fetching remote state... "
    if ! git fetch "$platform" --quiet 2>/dev/null; then
        echo -e "${RED}✗ Failed to fetch${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ Fetched${NC}"

    # Branch inventory
    local -a local_branches=() remote_branches=() local_only=() remote_only=()
    mapfile -t local_branches < <(git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null | sort)
    mapfile -t remote_branches < <(git for-each-ref --format='%(refname:lstrip=3)' "refs/remotes/$platform/" 2>/dev/null | grep -v '^HEAD$' | sort)

    local -A local_set=() remote_set=()
    local b rb
    for b in "${local_branches[@]}"; do
        local_set["$b"]=1
    done
    for rb in "${remote_branches[@]}"; do
        remote_set["$rb"]=1
    done
    for b in "${local_branches[@]}"; do
        [[ -n "${remote_set[$b]:-}" ]] || local_only+=("$b")
    done
    for rb in "${remote_branches[@]}"; do
        [[ -n "${local_set[$rb]:-}" ]] || remote_only+=("$rb")
    done

    echo -e "\n${BLUE}Branch inventory:${NC}"
    echo -e "  Current    : ${CYAN}$current_branch${NC}"
    echo -e "  Local-only : ${#local_only[@]}${local_only[*]:+ (${local_only[*]})}"
    echo -e "  Remote-only: ${#remote_only[@]}${remote_only[*]:+ (${remote_only[*]})}"

    # Never rename branches; just report a different remote default
    local remote_default
    remote_default=$(git ls-remote --symref -- "$remote_url" HEAD 2>/dev/null | \
        awk '/^ref:/ {sub("refs/heads/", "", $2); print $2; exit}')
    if [[ -n "$remote_default" && "$remote_default" != "$current_branch" ]]; then
        echo -e "${YELLOW}ℹ️  Remote default is '$remote_default'; staying on '$current_branch'.${NC}"
    fi

    # Is the current branch on the remote?
    local current_on_remote=false
    [[ -n "${remote_set[$current_branch]:-}" ]] && current_on_remote=true

    if [[ "$current_on_remote" == "false" ]]; then
        echo -e "\n${YELLOW}Current branch '$current_branch' is not on '$platform'.${NC}"
        echo -e "${YELLOW}Push it yourself when you are ready:${NC}"
        echo -e "    ${CYAN}git push -u $platform $current_branch${NC}"
    else
        local remote_branch="$current_branch"
        echo -e "  Remote branch: $platform/$remote_branch"
        echo -e "  Local branch : $current_branch"

        # Analyze divergence
        git fetch "$platform" "$remote_branch"
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}❌ Failed to fetch from remote '$platform' branch '$remote_branch'.${NC}" >&2
            return 1
        fi
        local ahead=0 behind=0
        ahead=$(git rev-list --count "$platform/$remote_branch..$current_branch")
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}❌ Failed to count ahead commits.${NC}" >&2
            return 1
        fi
        behind=$(git rev-list --count "$current_branch..$platform/$remote_branch")
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}❌ Failed to count behind commits.${NC}" >&2
            return 1
        fi

        echo -e "\n${BLUE}Divergence analysis:${NC}"
        echo "  Local is $ahead commit(s) ahead of remote"
        echo "  Local is $behind commit(s) behind remote"

        if [[ "$behind" -eq 0 && "$ahead" -eq 0 ]]; then
            # Scenario 1: Identical branches
            echo -e "${GREEN}✓ No divergence - branches are identical${NC}"
            echo -e "${YELLOW}Nothing to push.${NC}"
        elif [[ "$behind" -eq 0 && "$ahead" -gt 0 ]]; then
            # Scenario 2: Only local commits
            echo -e "${GREEN}✓ Only local commits (no remote changes)${NC}"
            echo -e "${YELLOW}Push $ahead commit(s) yourself when ready:${NC}"
            echo -e "    ${CYAN}git push -u $platform $current_branch${NC}"
        elif [[ "$behind" -gt 0 ]]; then
            # Scenario 3: Divergence detected
            echo -e "${YELLOW}⚠️  DIVERGENCE DETECTED: Remote has $behind new commit(s)${NC}"

            # Handle uncommitted changes
            local stashed=false
            if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
                echo -e "${YELLOW}Stashing uncommitted changes...${NC}"
                if git stash push -m "repo-crafter: pre-sync" --quiet; then
                    stashed=true
                    echo -e "${GREEN}✓ Stashed${NC}"
                else
                    echo -e "${RED}✗ Failed to stash changes${NC}"
                    return 1
                fi
            fi

            echo -e "\n${BLUE}Integration options:${NC}"
            echo "  1) Rebase (clean history)"
            echo "  2) Merge (safer for collaboration)"
            echo "  3) Skip integration (no push)"
            echo "  x) Cancel"

            local sync_choice=""
            read -rp "Choice (1-3 or x): " sync_choice || sync_choice=""

            case "$sync_choice" in
                1) # REBASE
                    echo -e "\n${BLUE}Rebasing local commits...${NC}"
                    if execute_dangerous "Rebase onto $platform/$remote_branch" git rebase "$platform/$remote_branch" --quiet; then
                        echo -e "${GREEN}✓ Rebase successful${NC}"
                        if [[ "$stashed" == "true" ]]; then
                            echo -n "Applying stashed changes... "
                            if git stash pop --quiet; then
                                echo -e "${GREEN}✓ Restored${NC}"
                            else
                                echo -e "${YELLOW}⚠️  Auto-merge failed. Run: git stash pop${NC}"
                            fi
                        fi

                        echo -e "${YELLOW}Rebase rewrote local history. Push it yourself with:${NC}"
                        echo -e "    ${CYAN}git push --force-with-lease -u $platform $current_branch${NC}"
                        echo -e "${YELLOW}  (only if you are sure; this rewrites the remote branch)${NC}"
                    else
                        echo -e "${RED}✗ Rebase failed. Resolve conflicts manually.${NC}"
                        [[ "$stashed" == "true" ]] && echo -e "${YELLOW}⚠️  Your changes are stashed.${NC}"
                        return 1
                    fi
                    ;;

                2) # MERGE
                    echo -e "\n${BLUE}Merging remote changes...${NC}"
                    if execute_dangerous "Merge remote" git merge "$platform/$remote_branch" --no-edit --quiet; then
                        echo -e "${GREEN}✓ Merge successful${NC}"
                        echo -e "${YELLOW}Push the merged branch yourself when ready:${NC}"
                        echo -e "    ${CYAN}git push -u $platform $current_branch${NC}"
                    else
                        echo -e "${RED}✗ Merge conflict. Resolve conflicts manually.${NC}"
                        return 1
                    fi
                    ;;

                3) # SKIP
                    echo -e "${YELLOW}Skipping integration. Local and remote remain divergent.${NC}"
                    echo -e "${YELLOW}Integrate manually, then push:${NC}"
                    echo -e "    ${CYAN}git pull --rebase $platform $current_branch${NC}"
                    echo -e "    ${CYAN}git push -u $platform $current_branch${NC}"
                    ;;

                x|X|"")
                    echo -e "${YELLOW}Synchronization cancelled.${NC}"
                    # Restore stashed changes if any
                    [[ "$stashed" == "true" ]] && git stash pop --quiet >/dev/null 2>&1
                    return 1
                    ;;

                *)
                    echo -e "${RED}Invalid choice. Synchronization cancelled.${NC}"
                    [[ "$stashed" == "true" ]] && git stash pop --quiet >/dev/null 2>&1
                    return 1
                    ;;
            esac
        fi
    fi

    # List local-only branches and the exact commands. Never push them here.
    # Never merge/rebase a branch that is not checked out; that needs a
    # checkout or worktree and is a separate flow.
    local -a other_local_only=()
    for b in "${local_only[@]}"; do
        [[ "$b" == "$current_branch" ]] || other_local_only+=("$b")
    done
    if [[ ${#other_local_only[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}Local branches not on '$platform': ${other_local_only[*]}${NC}"
        echo -e "${YELLOW}Push them yourself when ready:${NC}"
        for b in "${other_local_only[@]}"; do
            [[ "$b" == "$current_branch" ]] && continue
            echo -e "    ${CYAN}git push -u $platform $b${NC}"
        done
    fi

    if [[ ${#remote_only[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}Remote branches not local: ${remote_only[*]}${NC}"
        echo -e "${YELLOW}  Not checked out automatically. Create them with:${NC}"
        for b in "${remote_only[@]}"; do
            echo "    git switch -c $b $platform/$b"
        done
    fi

    return 0
}

# ======================= INTERACTIVE WORKFLOW FUNCTIONS ======================
##### Create a new project #####
create_new_project_workflow() {
  echo -e "\n${BLUE}=== CREATE NEW PROJECT ===${NC}"

  warn_duplicate_remote_connections

  echo "How do you want to start?"
  echo "  1) Create new local + remote repo (API)"
  echo "  2) Clone existing remote repo"
  echo "  3) Create local-only project (no binding)"
  echo "  x) ← Back to Main Menu"
  read -rp "Choice (1-3 or x): " choice

   case "$choice" in
     1) local project_name visibility platform
        project_name=$(_prompt_project_name) || { echo -e "${YELLOW}Cancelled.${NC}"; return; }
        platform=$(select_platforms "Select platform for new repository:" "false") || { echo -e "${YELLOW}Cancelled.${NC}"; return; }
        platform=$(echo "$platform" | tr -d '[:space:]')  # Clean whitespace
        visibility=$(_prompt_visibility) || { echo -e "${YELLOW}Cancelled.${NC}"; return; }

        # Summary and confirmation
        echo ""
        echo -e "${BLUE}=== SUMMARY ===${NC}"
        echo -e "  Project: ${CYAN}$project_name${NC}"
        echo -e "  Platform: ${CYAN}$platform${NC}"
        echo -e "  Visibility: ${CYAN}$visibility${NC}"
        echo ""

        if ! confirm_action "Create this repository?"; then
            echo -e "${YELLOW}Cancelled.${NC}"
            return
        fi

        _create_with_new_remote "$project_name" "$visibility" "$platform" ;;
    2) local cloned_dir
       cloned_dir=$(_clone_existing_remote "standalone") || return
       if [[ -n "$cloned_dir" ]]; then
         if [[ "$DRY_RUN" == "true" ]]; then
           preview_and_abort_if_dry
           return
         fi
         if [[ -f "$cloned_dir/repo-crafter.yml" ]]; then
           echo -e "${GREEN}✓ Using the manifest that came with the clone.${NC}"
           manifest_validate "$cloned_dir" || true
         elif [[ -f "$cloned_dir/REMOTE_STATE.yml" ]]; then
           manifest_migrate_legacy "$cloned_dir" || true
         else
           create_manifest "$cloned_dir" "clone_existing" "" || {
             echo -e "${YELLOW}⚠️  Manifest was not created. The clone is usable.${NC}"
           }
         fi
       fi
       ;;
    3) _create_local_only ;;
    x|X) echo -e "${YELLOW}Cancelled.${NC}"; return ;;
    *) echo -e "${RED}Invalid choice.${NC}" ;;
  esac
}

# Helper: Create local repo + API remote
_create_with_new_remote() {
  local project_name="$1"
  local visibility="${2:-private}"
  local platform="$3"

  # Set up directory path
  local dir="$REMOTE_ROOT/${PLATFORM_WORK_DIR[$platform]}/$project_name"

  # Validate inputs
  [[ -z "$project_name" ]] && { echo -e "${RED}❌ Project name required${NC}"; return 1; }
  [[ ! " ${AVAILABLE_PLATFORMS[*]} " =~ " $platform " ]] && { echo -e "${RED}❌ Invalid platform: $platform${NC}"; return 1; }

  echo -e "\n${BLUE}=== CREATE REMOTE REPOSITORY (${platform^^}) ===${NC}"
  echo -e "Project: ${CYAN}$project_name${NC}"
  echo -e "Visibility: ${CYAN}$visibility${NC}"
  echo -e "Local path: ${CYAN}$dir${NC}"

  # Never reuse an existing destination: refusing here keeps the later
  # cleanup path from deleting a folder that was not ours to begin with.
  if [[ -e "$dir" ]]; then
    echo -e "${RED}❌ Destination already exists: $dir${NC}"
    echo -e "${YELLOW}Choose another project name. Nothing was created.${NC}"
    return 1
  fi

  # Warn if a repository with this name already exists elsewhere under PROJECT_ROOT
  if ! warn_duplicate_repo_name "$project_name" "$(dirname "$dir")"; then
    echo -e "${YELLOW}Cancelled. Nothing was created.${NC}"
    return 1
  fi

  # DRY RUN handling
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Would create remote repository on $platform${NC}"
    echo -e "${YELLOW}[DRY RUN] Would initialize local repository${NC}"
    echo -e "${YELLOW}[DRY RUN] Would create manifest${NC}"
    return 0
  fi

  # Create parent directory
  mkdir -p "$(dirname "$dir")" || { echo -e "${RED}❌ Failed to create parent directory${NC}"; return 1; }

  # Create remote repository using reusable function
  local remote_url
  echo ""
  if ! remote_url=$(create_remote_repo "$platform" "$project_name" "$visibility" "$(git config --global user.name 2>/dev/null || echo 'default_user')"); then
    echo -e "${RED}❌ Failed to create remote repository on $platform${NC}"
    return 1
  fi

  if [[ -z "$remote_url" ]]; then
    echo -e "${RED}❌ Failed to get repository URL from API response${NC}"
    return 1
  fi

  echo -e "${GREEN}✓ Created on $platform${NC}"
  echo -e "  URL: ${CYAN}$(_redact_url_credentials "$remote_url")${NC}"

  # Initialize local repository with cleanup on failure
  echo -e "\n${BLUE}Initializing local repository...${NC}"

  if ! mkdir -p "$dir"; then
    echo -e "${RED}❌ Failed to create project directory${NC}"
    _cleanup_failed_creation "$platform" "$project_name" "$remote_url"
    return 1
  fi

  # Initialize git with dynamic branch detection
  local default_branch
  default_branch=$(git config --get init.defaultBranch 2>/dev/null || echo "main")

  if ! git -C "$dir" init -b "$default_branch" >/dev/null 2>&1; then
    echo -e "${RED}❌ Failed to initialize git repository${NC}"
    _cleanup_failed_creation "$platform" "$project_name" "$remote_url"
    return 1
  fi

  # Create initial commit
  echo "# $project_name" > "$dir/README.md"
  if ! git -C "$dir" add README.md 2>/dev/null; then
      echo -e "${RED}❌ Failed to add README.md${NC}" >&2
      _cleanup_failed_creation "$platform" "$project_name" "$remote_url"
      return 1
  fi

  if ! git -C "$dir" commit -m "Initial commit" 2>/dev/null; then
      echo -e "${RED}❌ Failed to create initial commit${NC}" >&2
      _cleanup_failed_creation "$platform" "$project_name" "$remote_url"
      return 1
  fi

  # Add remote
  if ! git -C "$dir" remote add "$platform" "$remote_url" 2>&1; then
      echo -e "${RED}❌ Failed to add remote '$platform'${NC}" >&2
      echo -e "${YELLOW}Remote may already exist. Try removing it first.${NC}"
      _cleanup_failed_creation "$platform" "$project_name" "$remote_url"
      return 1
  fi
   echo -e "  Added remote: ${CYAN}$platform${NC}"
  
  echo -e "${YELLOW}NOTE: Repository created but not pushed automatically.${NC}"
  echo -e "${YELLOW}You can push manually later using:${NC}"
  echo -e "      git push -u $platform $default_branch${NC}"

  echo -e "${GREEN}✓ Repository created${NC}"

  # Every bound project declares its intent, even with a single remote.
  create_manifest "$dir" "create_with_new_remote" "$remote_url" || {
    echo -e "${YELLOW}⚠️  Manifest was not created. The remote is configured.${NC}"
  }

  echo -e "\n${GREEN}✅ SUCCESS: Repository created${NC}"
  echo -e "  Local path: ${CYAN}$dir${NC}"
  echo -e "  Remote URL: ${CYAN}$(_redact_url_credentials "$remote_url")${NC}"

  preview_and_abort_if_dry
  return 0
}

# Cleanup helper for failed creations
_cleanup_failed_creation() {
    local platform="$1"
    local project_name="$2"
    local remote_url="$3"

    echo -e "\n${YELLOW}Cleaning up partial creation...${NC}"

    # Try to delete remote repository using the platform's delete endpoint
    if [[ -n "$remote_url" ]]; then
        echo -e "  Attempting to delete remote repository..."

        local owner repo
        owner=$(get_owner_from_ssh_url "$remote_url" 2>/dev/null) || owner=""
        repo=$(basename "$(parse_git_url "$remote_url")")

        local delete_endpoint="${PLATFORM_REPO_DELETE_ENDPOINT[$platform]:-}"
        local delete_method="${PLATFORM_REPO_DELETE_METHOD[$platform]:-DELETE}"

        if [[ -z "$owner" || -z "$repo" || -z "$delete_endpoint" ]]; then
            echo -e "  ${YELLOW}⚠️  Cannot delete remote automatically (missing owner, repo, or delete endpoint).${NC}"
            echo -e "  ${YELLOW}   Remove it manually: $(_redact_url_credentials "$remote_url")${NC}"
        else
            delete_endpoint=$(_build_delete_endpoint "$platform" "$remote_url") || delete_endpoint=""
            if [[ -z "$delete_endpoint" ]]; then
                echo -e "  ${YELLOW}⚠️  Refusing to delete: the remote URL does not yield a safe endpoint.${NC}"
                echo -e "  ${YELLOW}   Remove it manually: $(_redact_url_credentials "$remote_url")${NC}"
            elif _delete_remote_quiet "$platform" "$delete_endpoint" "$delete_method"; then
                echo -e "  ${GREEN}✓ Remote repository deleted${NC}"
            else
                echo -e "  ${YELLOW}⚠️  Remote deletion failed; remove it manually: $(_redact_url_credentials "$remote_url")${NC}"
            fi
        fi
    fi

    # Delete local directory
    local work_dir="${PLATFORM_WORK_DIR[$platform]}"
    local dir="$REMOTE_ROOT/$work_dir/$project_name"

    if [[ -d "$dir" ]]; then
        echo -e "  Deleting local directory..."
        rm -rf -- "$dir" 2>/dev/null
        echo -e "  ${YELLOW}Local cleanup attempted${NC}"
    fi
}
# Helper: Clone existing repo
_clone_existing_remote() {
  # PURPOSE: Universal clone engine. Clones first URL, decides destination based on URL count.
  # INPUT: $1 = mode ("standalone" or "binding")
  #        $2..$N = URLs to consider (for 'binding' mode; can be empty for 'standalone')

  local mode="${1:-standalone}"
  shift  # Remove the mode from arguments
  local urls=("$@")  # All remaining arguments are URLs

  echo -e "\n${BLUE}=== Clone Existing Repository ===${NC}" >&2

  # --- PART 1: GET THE URL(S) ---
  local first_url=""

  if [[ "$mode" == "binding" && ${#urls[@]} -gt 0 ]]; then
    # Mode 1: Called from convert_local_to_remote with a pre-provided list
    first_url="${urls[0]}"
    echo -e "${GREEN}Using URL from binding workflow...${NC}" >&2
  else
    # Mode 2: Standalone mode - interactively ask for one URL (old behavior)
    echo -e "${YELLOW}Enter repository URL:${NC}" >&2
    echo "Example: git@github.com:user/repo.git" >&2
    read -rp "URL: " first_url
    [[ -z "$first_url" ]] && return
  fi

  [[ -z "$first_url" ]] && { echo -e "${RED}No URL provided.${NC}" >&2; return 1; }

  # Reject option-injection / non-standard transports before git sees the URL.
  _validate_git_url "$first_url" || {
    echo -e "${RED}❌ Invalid remote URL: '$first_url'${NC}" >&2
    echo -e "${YELLOW}   Only https://… or git@host:… URLs are accepted.${NC}" >&2
    return 1
  }

  # --- PART 2: PARSE URL & DETECT PLATFORM (Your existing code) ---
  local parsed_path=$(parse_git_url "$first_url")
  [[ -z "$parsed_path" ]] && { echo -e "${RED}Invalid URL format${NC}" >&2; return 1; }
  local repo_name
  repo_name=$(safe_dir_name "$parsed_path")
  if [[ "$repo_name" != "$(basename "$parsed_path")" ]]; then
      echo -e "${YELLOW}Using directory name: $repo_name${NC}" >&2
  fi

  local host
  host=$(extract_host_from_url "$first_url")

  local platform=""
  platform=$(detect_platform_from_url "$first_url") || { echo -e "${RED}Unknown platform for URL: $(_redact_url_credentials "$first_url")${NC}" >&2; return 1; }

  # --- PART 3: DECIDE DESTINATION DIRECTORY (THE NEW LOGIC) ---
  local dest_dir=""

  if [[ "$mode" == "binding" && ${#urls[@]} -gt 1 ]]; then
    # MULTI-PLATFORM BINDING: Clone to Multi-server
    dest_dir="$REMOTE_ROOT/Multi-server/$repo_name"
    echo -e "${BLUE}Multi-platform mode: Cloning to Multi-server/${NC}" >&2
  else
    # SINGLE PLATFORM: Clone to platform-specific directory
    dest_dir="$REMOTE_ROOT/${PLATFORM_WORK_DIR[$platform]}/$repo_name"
    echo -e "${BLUE}Single platform ($platform): Cloning to ${PLATFORM_WORK_DIR[$platform]}/${NC}" >&2
  fi

  # Dry run: report the clone without touching the filesystem or the network.
  # The caller still receives the destination path it would have used.
  if [[ "$DRY_RUN" == "true" ]]; then
      DRY_RUN_ACTIONS+=("Clone $(_redact_url_credentials "$first_url") into $dest_dir")
      echo -e "${YELLOW}[DRY RUN] Would clone $(_redact_url_credentials "$first_url") into $dest_dir${NC}" >&2
      echo "$dest_dir"
      return 0
  fi

  # --- PART 4: CLONE (Your existing code) ---
  # Check SSH auth
  if [[ "$first_url" =~ ^git@ ]]; then
      check_ssh_auth "$host" "$platform" || return 1
  fi

  # Clone (no pipe: keep git's exit status and full error output)
  echo -e "\n${BLUE}Cloning to: $dest_dir${NC}" >&2
  if ! git clone -- "$first_url" "$dest_dir"; then
      echo -e "${RED}❌ Failed to clone repository${NC}" >&2
      echo -e "${YELLOW}Check: 1) URL is correct 2) SSH keys configured 3) Repository exists${NC}" >&2
      return 1
  fi
  echo -e "${GREEN}✅ Cloned to $dest_dir${NC}" >&2

  # --- PART 5: RETURN THE PATH ---
  # Only the path goes to stdout so callers can capture it
  echo "$dest_dir"

  # Only pause in standalone mode
  if [[ "$mode" == "standalone" ]]; then
      read -rp "Press Enter to continue..." -n 1 || true
  fi

  return 0
}

# Helper: Create local-only project
_create_local_only() {
  local project_name dest_dir

  project_name=$(_prompt_project_name) || return
  [[ -n "$project_name" ]] || return

  dest_dir="$LOCAL_ROOT/$project_name"
  [[ -d "$dest_dir" ]] && { echo -e "${RED}Destination already exists: $dest_dir${NC}"; return 1; }

  # Warn if a repository with this name already exists elsewhere under PROJECT_ROOT
  if ! warn_duplicate_repo_name "$project_name" "$LOCAL_ROOT"; then
    echo -e "${YELLOW}Cancelled. Nothing was created.${NC}"
    return 1
  fi

  execute_safe "Create project directory" mkdir -p "$dest_dir"
  local default_branch=$(git config --get init.defaultBranch 2>/dev/null || echo "main")
  execute_safe "Initialize git repository" git -C "$dest_dir" init -b "$default_branch"
  execute_safe "Create README.md" bash -c 'printf "# %s\n" "$2" > "$1"' _ "$dest_dir/README.md" "$project_name"

  # Everything below writes git state; never run it in dry-run
  if [[ "$DRY_RUN" == "true" ]]; then
    preview_and_abort_if_dry
    return 0
  fi

  # A fresh init has no remotes; keep the project isolated if any appear
  remove_existing_remotes "$dest_dir" || echo -e "${YELLOW}Continuing with existing remotes.${NC}"

  if ! git -C "$dest_dir" add README.md 2>&1; then
      echo -e "${RED}❌ Failed to add README.md${NC}" >&2
      return 1
  fi
  if ! git -C "$dest_dir" commit -m "Initial commit" 2>&1; then
      echo -e "${RED}❌ Failed to create initial commit${NC}" >&2
      return 1
  fi

  echo -e "${GREEN}✅ Created at $dest_dir${NC}"
  echo -e "${YELLOW}Note: Unbound project. Use 'Bind Local → Remote' later if needed.${NC}"
  sleep 5
  preview_and_abort_if_dry
}
##### Convert a single platform project to Multi platform project #####
convert_single_to_multi_platform() {
  echo -e "\n${BLUE}=== CONVERT SINGLE-PLATFORM TO MULTI-PLATFORM ===${NC}"

  # Let user select a single-platform project (Multi-server excluded)
  local source_dir
  source_dir=$(_select_project_from_dir "$REMOTE_ROOT" "Single-platform projects available:" "$REMOTE_ROOT/Multi-server") || return 0
  [[ -z "$source_dir" ]] && return 0
  # Backstop: source and destination would be the same directory
  if [[ "$source_dir" == "$REMOTE_ROOT/Multi-server/"* ]]; then
    echo -e "${YELLOW}Already multi-platform (in Multi-server/). Nothing to convert.${NC}"
    return 0
  fi

  local project_name=$(basename "$source_dir")
  local current_platform=""

  # 2. Detect current platform from directory
  for platform in "${AVAILABLE_PLATFORMS[@]}"; do
    if [[ "$source_dir" == "$REMOTE_ROOT/${PLATFORM_WORK_DIR[$platform]}/"* ]]; then
      current_platform="$platform"
      break
    fi
  done

  echo -e "\n${GREEN}Selected: $project_name${NC}"
  echo -e "${YELLOW}Current platform: $current_platform${NC}"

  # 3. Get current remote URL
  local current_url
  current_url=$(git -C "$source_dir" remote get-url origin 2>/dev/null || git -C "$source_dir" remote get-url "$current_platform" 2>/dev/null)
  if [[ -z "$current_url" ]]; then
    echo -e "${RED}❌ Could not read the current remote URL for '$project_name'.${NC}"
    return 1
  fi

  echo -e "\n${BLUE}Current remote:${NC}"
  echo -e "  $(_redact_url_credentials "$current_url")"

  # Warn if an existing manifest disagrees with the current remotes.
  if [[ -f "$source_dir/repo-crafter.yml" ]]; then
      manifest_reconcile "$source_dir" "true" || true
  fi

  # 4. Ask for additional URLs
  echo -e "\n${YELLOW}Enter additional repository URLs (one per line, empty to finish):${NC}"
  local urls=("$current_url")  # Start with current URL
  while true; do
    read -rp "URL: " url
    [[ -z "$url" ]] && break
    urls+=("$url")
  done

  [[ ${#urls[@]} -eq 1 ]] && {
    echo -e "${YELLOW}No additional URLs. Staying as single-platform.${NC}"
    return
  }

  # 5. Set new destination
  local dest_dir="$REMOTE_ROOT/Multi-server/$project_name"

  echo -e "\n${BLUE}Will convert to multi-platform:${NC}"
  echo -e "  From: $source_dir"
  echo -e "  To: $dest_dir"
  echo -e "  Platforms: ${#urls[@]} remotes"

  confirm_action "Proceed with conversion?" || return

  # Ensure the managed parent exists (git clone creates it; mv does not)
  execute_safe "Create Multi-server directory" mkdir -p "$(dirname "$dest_dir")" || return 1

  # 6. Move to Multi-server
  if [[ -d "$dest_dir" ]]; then
    echo -e "${YELLOW}Directory '$dest_dir' already exists.${NC}"
    local overwrite_choice
    read -rp "Do you want to overwrite it? (y/N): " overwrite_choice
    if [[ "${overwrite_choice,,}" =~ ^y$ ]]; then
      if ! execute_dangerous "Remove existing directory" rm -rf "$dest_dir"; then
        echo -e "${YELLOW}Aborted.${NC}"
        return 1
      fi
      [[ "$DRY_RUN" == "true" ]] || echo -e "${GREEN}Removed existing directory '$dest_dir'.${NC}"
    else
      echo -e "${YELLOW}Aborting conversion.${NC}"
      return 1
    fi
  fi
  if ! execute_dangerous "Move project to Multi-server" mv "$source_dir" "$dest_dir"; then
    echo -e "${RED}❌ Failed to move '$source_dir' to '$dest_dir'.${NC}"
    return 1
  fi

  # In dry-run the move was skipped; stop here so nothing else runs
  if [[ "$DRY_RUN" == "true" ]]; then
    preview_and_abort_if_dry
    return 0
  fi

  # 7. Rename current remote (if it's "origin" or generic)
  echo -e "\n${BLUE}Configuring remotes...${NC}"

  # If remote is named "origin", rename to platform name
  if git -C "$dest_dir" remote | grep -q "^origin$" && [[ -n "$current_platform" ]]; then
    if git -C "$dest_dir" remote rename origin "$current_platform"; then
      echo -e "${GREEN}✓ Renamed remote: origin → $current_platform${NC}"
    else
      echo -e "${YELLOW}⚠️  Could not rename origin → $current_platform (name may already be used).${NC}"
    fi
  fi

  # 8. Add additional remotes (skip first URL - it's the current one)
  for ((i=1; i<${#urls[@]}; i++)); do
      local url="${urls[$i]}"
      local platform_name=""

      # Detect platform from URL
      platform_name=$(detect_platform_from_url "$url") || platform_name="remote$((i+1))"

      # Pick a free remote name instead of silently skipping duplicate platforms
      local remote_name="$platform_name"
      local suffix=2
      while git -C "$dest_dir" remote | grep -qx "$remote_name"; do
          remote_name="${platform_name}_${suffix}"
          ((suffix++)) || true
      done

      if git -C "$dest_dir" remote add "$remote_name" "$url"; then
          echo -e "${GREEN}✓ Added remote: $remote_name${NC}"
      else
          echo -e "${YELLOW}⚠️  Failed to add remote: $remote_name${NC}"
      fi
  done

  # 9. Create the manifest from the actual git remotes, never from platform keys
  echo -e "\n${YELLOW}Creating project manifest...${NC}"
  create_manifest "$dest_dir" "convert_single_to_multi" "$current_url" || {
    echo -e "${YELLOW}⚠️  Manifest was not created. Remotes are configured; you can add it later.${NC}"
  }

  # 10. Show status
  echo -e "\n${GREEN}✅ Successfully converted to multi-platform!${NC}"
  echo -e "Remotes:"
  git -C "$dest_dir" remote -v
  echo -e "\n${YELLOW}Next steps:${NC}"
  echo "  - Run: git fetch --all"
  echo "  - Push to new remotes: git push --all"
  preview_and_abort_if_dry
}

##### Convert a local project to remote project #####
# Copy a project's files into a bound destination, never the .git directory.
_bind_copy_files() {
  local source_dir="$1"
  local dest_dir="$2"

  if command -v rsync &>/dev/null; then
    rsync -av --exclude='.git' "$source_dir/" "$dest_dir/" || return 1
  else
    ( cd "$source_dir" && find . -name '.git' -prune -o -print0 | cpio -pdm0 "$dest_dir" ) || return 1
  fi
  return 0
}

# Show status and offer a single commit; a failed commit leaves files in place.
_bind_commit_changes() {
  local dest_dir="$1"
  local default_message="$2"
  local commit_choice commit_msg

  if [[ "$DRY_RUN" == "true" ]]; then
    DRY_RUN_ACTIONS+=("Offer to commit changes in $dest_dir")
    echo -e "${YELLOW}[DRY RUN] Would offer to commit changes in $dest_dir${NC}"
    return 0
  fi

  echo -e "\n${BLUE}Repository status:${NC}"
  git -C "$dest_dir" status --short

  echo -e "\n${BLUE}Commit changes?${NC}"
  echo "  y) Yes, commit now"
  echo "  n) No, I'll handle manually"
  read -rp "Choice (y/n): " commit_choice

  if [[ "$commit_choice" =~ ^[Yy]$ ]]; then
    read -rp "Commit message: " commit_msg
    [[ -z "$commit_msg" ]] && commit_msg="$default_message"
    if git -C "$dest_dir" add -A && git -C "$dest_dir" commit -m "$commit_msg"; then
      echo -e "${GREEN}✓ Changes committed${NC}"
    else
      echo -e "${YELLOW}⚠️  Commit failed. Files are in place; run 'git add -A && git commit' manually.${NC}"
    fi
  else
    echo -e "${YELLOW}⚠️  Changes not committed. Run 'git add . && git commit' when ready.${NC}"
  fi
}

convert_local_to_remote_workflow() {
  echo -e "\n${BLUE}=== BIND LOCAL PROJECT TO REMOTE ===${NC}"

  # === SELECT LOCAL PROJECT ===
  local source_dir
  source_dir=$(_select_project_from_dir "$LOCAL_ROOT" "Local projects available to bind:") || {
    echo -e "${YELLOW}No project selected. Returning to menu.${NC}"
    return 1
  }

  local project_name=$(basename "$source_dir")
  echo -e "\n${GREEN}Selected: $project_name${NC}"
  echo -e "${YELLOW}Source: $source_dir${NC}"

  # Commit warning if any changes exist
  echo -e "\n${BLUE}=== Checking Repository Status ===${NC}"

  if ! check_local_exists "$source_dir"; then
    echo -e "${YELLOW}⚠️  Not a git repository yet; it will be initialized during binding.${NC}"
  else
    local -a status_remotes=()
    mapfile -t status_remotes < <(git -C "$source_dir" remote 2>/dev/null)

    if [[ ${#status_remotes[@]} -eq 0 ]]; then
      echo -e "${YELLOW}⚠️  No remotes configured (local-only project); nothing to fetch.${NC}"
    else
      # Fetch remote to get latest state
      echo -e "${YELLOW}Fetching remote...${NC}"
      if git -C "$source_dir" fetch --quiet 2>/dev/null; then
        # Only claim a comparison when the branch actually tracks a remote
        # (rev-list separates the two counts with a tab, not a space)
        if git -C "$source_dir" rev-list --left-right --count @{u}...HEAD 2>/dev/null | grep -qE '^[0-9]+[[:space:]]+[0-9]+$'; then
          local remote_behind
          local remote_ahead
          remote_behind=$(git -C "$source_dir" rev-list --left-right --count @{u}...HEAD 2>/dev/null | cut -f1) || remote_behind=0
          remote_ahead=$(git -C "$source_dir" rev-list --left-right --count @{u}...HEAD 2>/dev/null | cut -f2) || remote_ahead=0

          # Show remote status
          if [[ "$remote_behind" -gt 0 ]]; then
            echo -e "${YELLOW}⚠️  Remote has $remote_behind new commit(s)${NC}"
          fi
          if [[ "$remote_ahead" -gt 0 ]]; then
            echo -e "${YELLOW}⚠️  You have $remote_ahead local commit(s) not pushed${NC}"
          fi
          if [[ "$remote_behind" -eq 0 && "$remote_ahead" -eq 0 ]]; then
            echo -e "${GREEN}✓ Local and remote are in sync${NC}"
          fi
        else
          echo -e "${YELLOW}⚠️  Current branch has no upstream; remote state not compared.${NC}"
        fi
      else
        echo -e "${YELLOW}⚠️  Could not fetch remote${NC}"
      fi
    fi

    # Show uncommitted changes
    if git -C "$source_dir" diff --quiet 2>/dev/null && git -C "$source_dir" diff --cached --quiet 2>/dev/null; then
      echo -e "${GREEN}✓ No uncommitted changes${NC}"
    else
      echo -e "${YELLOW}⚠️  Uncommitted changes present (will be preserved)${NC}"
      echo -e "${YELLOW}Changes:${NC}"
      git -C "$source_dir" diff --stat 2>/dev/null
    fi
  fi

  # === CHOOSE BINDING METHOD ===
  echo -e "\n${BLUE}How do you want to bind this project?${NC}"
  echo "  1) Create NEW remote repositories on selected platform(s)"
  echo "  2) Connect to EXISTING remote repository (provide URL)"
  echo "  x) Cancel"

  read -rp "Choice (1-2 or x): " bind_choice

  if [[ "$bind_choice" == "x" ]] || [[ -z "$bind_choice" ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    return 1
  fi

  # === VARIABLES DECLARATION ===
  local dest_dir=""
  local platform_array=()
  local visibility=""
  local user_name=$(git config --global user.name)

  # === OPTION 1: CREATE NEW REPOSITORIES ===
  if [[ "$bind_choice" == "1" ]]; then
    echo -e "\n${YELLOW}Select platform(s) for new repositories:${NC}"

    local platforms
    platforms=$(select_platforms "Choose platform(s):" "true")

    # Check if selection was cancelled or empty
    if [[ $? -ne 0 ]] || [[ -z "$platforms" ]]; then
        echo -e "${YELLOW}Platform selection cancelled.${NC}"
        return 1
    fi

    IFS=$'\n' read -ra platform_array <<< "$platforms"

    # Determine destination directory
    if [[ ${#platform_array[@]} -eq 1 ]]; then
        local platform_work_dir="${PLATFORM_WORK_DIR[${platform_array[0]}]}"
        dest_dir="$REMOTE_ROOT/$platform_work_dir/$project_name"
    else
        dest_dir="$REMOTE_ROOT/Multi-server/$project_name"
    fi

    # Ask for visibility
    echo -e "\n${YELLOW}Repository visibility for new repositories?${NC}"
    echo "  1) Private"
    echo "  2) Public"
    read -rp "Select visibility (1-2): " visibility_choice

    if [[ "$visibility_choice" != "1" && "$visibility_choice" != "2" ]]; then
      echo -e "${YELLOW}Invalid visibility choice.${NC}"
      if [[ "$DRY_RUN" == "true" ]]; then
        preview_and_abort_if_dry
      fi
      return 1
    fi

    visibility="$([[ "$visibility_choice" == "1" ]] && echo "private" || echo "public")"

    # Warn about similar remote repos
    for platform in "${platform_array[@]}"; do
      warn_similar_remote_repos "$platform" "$project_name" "$user_name"
    done

    # Summary and confirmation
    echo ""
    echo -e "${BLUE}=== SUMMARY ===${NC}"
    echo -e "  Project: ${CYAN}$project_name${NC}"
    echo -e "  Platform(s): ${CYAN}$platforms${NC}"
    echo -e "  Visibility: ${CYAN}$visibility${NC}"
    echo -e "  Destination: ${CYAN}$dest_dir${NC}"
    echo ""

    if ! confirm_action "Create repository and bind project?"; then
      echo -e "${YELLOW}Cancelled.${NC}"
      return 1
    fi

    # Create destination directory only after confirmation
    execute_safe "Create destination directory" mkdir -p "$dest_dir"

  # === OPTION 2: CONNECT TO EXISTING REPOSITORY ===
  elif [[ "$bind_choice" == "2" ]]; then
    echo -e "\n${YELLOW}Enter repository URLs (one per line, empty line to finish):${NC}"
    echo "Examples: git@github.com:user/repo.git"

    local urls=()
    while true; do
        read -rp "URL: " url
        [[ -z "$url" ]] && break
        urls+=("$url")
    done

    [[ ${#urls[@]} -eq 0 ]] && { echo -e "${RED}No URLs provided.${NC}"; return 1; }

    # Parse first URL for cloning
    local first_url="${urls[0]}"
    # === CLONE USING THE NEW UNIVERSAL FUNCTION ===
    echo -e "\n${BLUE}Cloning primary repository...${NC}"

    # Call the refactored function. Pass "binding" mode and all the user's URLs.
    # It will handle: platform detection, SSH auth, and Smart destination logic.
    local cloned_dir
    cloned_dir=$(_clone_existing_remote "binding" "${urls[@]}")

    if [[ -z "$cloned_dir" ]]; then
        echo -e "${RED}❌ Clone failed or was cancelled.${NC}"
        return 1
    fi

    # CRITICAL: The cloned directory path is now in $cloned_dir.
    # Set $dest_dir to this value for any later logic that expects it.
    dest_dir="$cloned_dir"

    # Dry run stops here: the clone was only planned, not performed.
    if [[ "$DRY_RUN" == "true" ]]; then
        preview_and_abort_if_dry
        return 0
    fi

    # Now, change into the cloned directory to proceed with merging files.
    cd "$dest_dir" || { echo -e "${RED}❌ Cannot enter cloned directory.${NC}"; return 1; }

        # === MERGE LOCAL FILES ===
        echo -e "\n${BLUE}Merging your local files...${NC}"
        echo -e "${YELLOW}This will copy files from:${NC}"
        echo -e "  Source: $source_dir"
        echo -e "  Destination: $dest_dir"

        confirm_action "Copy local files (overwriting any conflicts)?" || {
            echo -e "${YELLOW}Leaving repository as cloned.${NC}"
            cd - >/dev/null
            return 0
        }

        # COPY files, not move
        echo -e "${BLUE}Copying files...${NC}"
        if ! _bind_copy_files "$source_dir" "$dest_dir"; then
          echo -e "${RED}❌ Copy failed; original kept.${NC}"
          return 1
        fi

        # === GIT STATUS & COMMIT ===
        _bind_commit_changes "$dest_dir" "Merge local changes from $project_name"

        # === ADD OTHER REMOTES ===
        if [[ ${#urls[@]} -gt 1 ]]; then
            echo -e "\n${BLUE}Adding additional remotes...${NC}"
            for ((i=1; i<${#urls[@]}; i++)); do
                local url="${urls[$i]}"
                local remote_name="remote$((i+1))"

                # Reject option-injection / non-standard transports.
                _validate_git_url "$url" || {
                    echo -e "  ${YELLOW}⚠️  Skipping invalid URL: $url${NC}"
                    continue
                }

                git remote add "$remote_name" -- "$url" 2>/dev/null && \
                    echo -e "  ${GREEN}✓ Added: $remote_name${NC}" || \
                    echo -e "  ${YELLOW}⚠️  Failed to add: $remote_name${NC}"
            done
        fi

        # === CLEANUP ===
        echo -e "\n${BLUE}Cleanup options:${NC}"
        echo "  1) Keep original local project"
        echo "  2) Remove original local project"
        echo "  3) Move original to backup location"
        read -rp "Choice (1-3): " cleanup_choice

        case $cleanup_choice in
            2)
                execute_dangerous "Remove original project" rm -rf "$source_dir" || return 1
                echo -e "${GREEN}✓ Original project removed${NC}"
                ;;
            3)
                local backup_dir="$LOCAL_ROOT/_backup_$project_name"
                execute_dangerous "Move original to backup" mv "$source_dir" "$backup_dir" || return 1
                echo -e "${GREEN}✓ Original moved to: $backup_dir${NC}"
                ;;
            *)
                echo -e "${YELLOW}⚠️  Original kept at: $source_dir${NC}"
                ;;
        esac

        echo -e "\n${GREEN}✅ Bound to existing repository!${NC}"
        echo -e "Location: $dest_dir"
        echo -e "${YELLOW}Remotes available:${NC}"
        git remote -v | sed -E 's#(https?://)[^/@]+@#\1#g'

        # A cloned repository may already declare its intent; never replace it.
        if [[ -f "$dest_dir/repo-crafter.yml" ]]; then
            echo -e "${GREEN}✓ Using the manifest that came with the clone.${NC}"
            manifest_validate "$dest_dir" || true
            manifest_reconcile "$dest_dir" || true
        elif [[ -f "$dest_dir/REMOTE_STATE.yml" ]]; then
            manifest_migrate_legacy "$dest_dir" || true
        else
            # Declare the actual remotes (origin plus any remoteN) in a manifest
            create_manifest "$dest_dir" "connect_existing" "$first_url" || {
                echo -e "${YELLOW}⚠️  Manifest was not created. Remotes are configured.${NC}"
            }
        fi

        # Offer to reconcile branches now that local and remote are connected
        if [[ "$DRY_RUN" != "true" ]] && confirm_action "Synchronize '$project_name' with 'origin' now?" "y"; then
            ( sync_with_remote origin "$first_url" ) || echo -e "${YELLOW}Synchronization skipped.${NC}"
        fi

        cd - >/dev/null
        return 0
    fi

  if [[ "$bind_choice" == "1" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      DRY_RUN_ACTIONS+=("Copy local files from $source_dir to $dest_dir")
      echo -e "${YELLOW}[DRY RUN] Would copy local files to $dest_dir${NC}"
    else
      echo -e "\n${BLUE}Copying your local files...${NC}"
      echo -e "${YELLOW}This will copy files from:${NC}"
      echo -e "  Source: $source_dir"
      echo -e "  Destination: $dest_dir"

      if confirm_action "Copy local files (overwriting any conflicts)?"; then
        echo -e "${BLUE}Copying files...${NC}"
        if ! _bind_copy_files "$source_dir" "$dest_dir"; then
          echo -e "${RED}❌ Failed to copy files${NC}"
          return 1
        fi
        echo -e "${GREEN}✅ Files copied successfully${NC}"
      else
        echo -e "${YELLOW}⚠️  Skipping file copy${NC}"
      fi
    fi
  fi

  # Dry run stops before any directory change, git init, or commit.
  if [[ "$DRY_RUN" == "true" ]]; then
    preview_and_abort_if_dry
    return 0
  fi

  cd "$dest_dir" || {
    echo -e "${RED}❌ Failed to change to destination directory: $dest_dir${NC}"
    return 1
  }

  # Initialize git if needed
  if [[ "$DRY_RUN" != "true" ]]; then
    if [[ ! -d ".git" ]]; then
      echo -e "${YELLOW}Initializing git repository...${NC}"
      local default_branch=$(detect_current_branch)
      git init -b "$default_branch" >/dev/null 2>&1 || {
        echo -e "${RED}❌ Failed to initialize git repository${NC}"
        return 1
      }
      echo -e "${GREEN}✅ Git repository initialized${NC}"
    fi
  else
    echo -e "${YELLOW}[DRY RUN] Would check/initialize git repository${NC}"
  fi

  if [[ "$bind_choice" == "1" ]]; then
    _bind_commit_changes "$dest_dir" "Initial commit with local changes from $project_name"
  fi

  # === REMOTE CONFIGURATION ===
  if [[ "$bind_choice" == "1" ]]; then
    # CREATE NEW REPOSITORIES
    echo -e "\n${BLUE}Creating and connecting new repositories...${NC}"

    for platform in "${platform_array[@]}"; do
      echo -n "Creating $platform repository... "

      local new_repo_url=""
      if new_repo_url=$(create_remote_repo "$platform" "$project_name" "$visibility" "$user_name"); then
        echo -e "${GREEN}✓ Created${NC}"

        # Add remote
        if handle_existing_remote "$platform" "$new_repo_url"; then
          if ! git remote get-url "$platform" &>/dev/null; then
            execute_dangerous "Add remote" git remote add "$platform" -- "$new_repo_url"
          fi
          echo -e "${GREEN}✓ Connected to $platform${NC}"

          # Push initial code
          if [[ "$DRY_RUN" != "true" ]]; then
            echo -e "${YELLOW}NOTE: Repository created but not pushed automatically.${NC}"
            echo -e "${YELLOW}You can push manually later using:${NC}"
            echo -e "      git push -u $platform $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")${NC}"
          else
            echo -e "${YELLOW}⚠️  DRY-RUN: Would ask about pushing initial code.${NC}"
          fi
        fi
      else
        echo -e "${RED}✗ Failed to create repository${NC}"
        return 1
      fi
    done

    # Create manifest for multi-platform projects from the actual git remotes
    if [[ ${#platform_array[@]} -gt 1 ]]; then
      echo -e "\n${BLUE}Creating project manifest...${NC}"
      local primary_url=""
      primary_url=$(git remote get-url "${platform_array[0]}" 2>/dev/null || true)
      create_manifest "$dest_dir" "convert_local_to_remote" "$primary_url" || {
        echo -e "${YELLOW}⚠️  Manifest was not created. Remotes are configured.${NC}"
      }
    elif [[ ${#platform_array[@]} -eq 1 ]]; then
      # Single platform: declare the remote, then offer to reconcile branches
      local sync_platform="${platform_array[0]}"
      local sync_url
      sync_url=$(git remote get-url "$sync_platform" 2>/dev/null || echo "")
      create_manifest "$dest_dir" "convert_local_to_remote" "$sync_url" || {
        echo -e "${YELLOW}⚠️  Manifest was not created. The remote is configured.${NC}"
      }
      if [[ -n "$sync_url" && "$DRY_RUN" != "true" ]] && \
         confirm_action "Synchronize '$project_name' with '$sync_platform' now?" "y"; then
        ( sync_with_remote "$sync_platform" "$sync_url" ) || echo -e "${YELLOW}Synchronization skipped.${NC}"
      fi
    fi

  fi

  # === FINAL SUCCESS MESSAGE ===
  cd - >/dev/null 2>&1

  echo -e "\n${GREEN}✅ Project successfully bound!${NC}"
  echo -e "Location: $dest_dir"

  # Only pause in dry-run mode
  if [[ "$DRY_RUN" == "true" ]]; then
    preview_and_abort_if_dry
  fi

  return 0
}

##### Convert a remote project #####
convert_remote_to_local_workflow() {
  echo -e "\n${BLUE}=== UNBIND REMOTE PROJECT TO LOCAL ===${NC}"

  # === SELECT A BOUND PROJECT ===
  local source_dir
  source_dir=$(_select_project_from_dir "$REMOTE_ROOT" "Projects available to bind:") || return
  local project_name=$(basename "$source_dir")
  echo -e "${GREEN}Selected: $project_name${NC}"
  local dest_dir="$LOCAL_ROOT/$project_name"

  # Resolve the destination before any destructive step
  if [[ -d "$dest_dir" ]]; then
    echo -e "${RED}Destination exists: $dest_dir${NC}"
    if ! confirm_action "Destination exists. Overwrite?"; then
      echo -e "${YELLOW}Cancelled. Nothing was changed.${NC}"
      return 0
    fi
    if ! execute_dangerous "Remove existing destination" rm -rf "$dest_dir"; then
      echo -e "${RED}❌ Failed to remove existing destination.${NC}"
      return 1
    fi
  fi

  # 2. Confirm unbinding
  echo -e "${YELLOW}This will:${NC}"
  echo "  - Remove ALL git remotes"
  echo "  - Move project to $dest_dir"
  echo "  - Delete repo-crafter.yml (and legacy REMOTE_STATE.yml) if present"
  confirm_action "This will remove ALL git remotes and move project to Local_Projects/" || return

  cd "$source_dir" || { echo -e "${RED}❌ Cannot enter '$source_dir'.${NC}"; return 1; }

  # Warn if the manifest and git remotes disagree before removing anything.
  if [[ -f "repo-crafter.yml" ]]; then
      manifest_reconcile "$PWD" "true" || true
  fi

  echo -e "\n${BLUE}=== Checking Repository Status ===${NC}"
  if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
      echo -e "${GREEN}✓ No uncommitted changes${NC}"
  else
      echo -e "${YELLOW}⚠️  Uncommitted changes present (will be preserved)${NC}"
  fi

  # 3. Remove remotes with error handling
  local removed_count=0
  local remotes=()
  mapfile -t remotes < <(git remote 2>/dev/null)
  for remote in "${remotes[@]}"; do
      if execute_dangerous "Remove remote $remote" git remote remove "$remote"; then
          [[ "$DRY_RUN" == "true" ]] || echo -e "${GREEN}✓ Removed remote: $remote${NC}"
          removed_count=$((removed_count + 1))
      else
          echo -e "${YELLOW}⚠️  Skipped removing remote: $remote${NC}"
      fi
  done

  if [[ $removed_count -eq 0 ]]; then
      echo -e "${YELLOW}⚠️  No remotes were removed.${NC}"
      confirm_action "Continue with directory move anyway?" || return
  fi

  # 4. Delete manifest (the project is no longer bound to any remote)
  [[ -f "repo-crafter.yml" ]] && execute_safe "Remove repo-crafter.yml" rm -f "repo-crafter.yml"
  [[ -f "REMOTE_STATE.yml" ]] && execute_safe "Remove REMOTE_STATE.yml" rm -f "REMOTE_STATE.yml"

  cd - >/dev/null || { echo -e "${RED}❌ Cannot return to previous directory.${NC}"; return 1; }

  # 5. Move directory
  # CREATE PARENT DIRECTORY AND MOVE
  local parent_dir=$(dirname "$dest_dir")
  execute_safe "Create directory structure" mkdir -p "$parent_dir"
  execute_dangerous "Move project to local directory" mv "$source_dir" "$dest_dir" || {
    echo -e "${RED}Move failed.${NC}"; return
  }

  if [[ "$DRY_RUN" != "true" ]]; then
    echo -e "\n${GREEN}✅ Project unbound and moved to $dest_dir${NC}"
  fi
  preview_and_abort_if_dry
}

# Helper: Function to list repos from available platform (given user account)
list_remote_repos_workflow() {
    echo -e "\n${BLUE}=== LIST REMOTE REPOSITORIES ===${NC}"

    # FIXED: Proper array handling for multiple platforms
    local -a platforms
    mapfile -t platforms < <(select_platforms "Choose platform(s) to list:" "true")
    if [[ ${#platforms[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Cancelled.${NC}"
        return
    fi

    # Process each selected platform
    local platform_count=0

    set +e
    for platform in "${platforms[@]}"; do
        # Clean platform name
        platform=$(echo "$platform" | tr -d '[:space:]')
        [[ -z "$platform" ]] && continue

        echo -e "\n${YELLOW}=== $platform ===${NC}"
        # This works because list_remote_repos() now has return 0
        if list_remote_repos "$platform"; then
            ((platform_count++))
        else
            echo -e "${RED}Failed to list repositories for $platform.${NC}"
        fi
    done
    set -e

    if [[ $platform_count -gt 0 ]]; then
        echo -e "\n${GREEN}✅ Listed repositories from $platform_count platform(s).${NC}"
    else
        echo -e "\n${RED}❌ No repositories could be listed.${NC}"
    fi
    printf "\n" >&2
    read -rp $'\n'"Press Enter to continue..." -n 1 || true
}


# DANGER Processes

manage_project_workflow() {
  echo -e "\n${RED}=== DELETE PROJECT (SAFE) ===${NC}"

  echo "Delete what?"
  echo "  1) Delete local files (remote repo kept if bound)"
  echo "  2) Unbind from remote (keeps local, moves to Local_Projects/)"
  echo "  3) Delete BOTH (TYPE PROJECT NAME TO CONFIRM)"
  echo "  x) Cancel"
  read -rp "Choice (1-3 or x): " choice

  case "$choice" in
    1) _delete_local_copy ;;
    2) convert_remote_to_local_workflow ;;  # Reuse unbind logic!
    3) _delete_both ;;
    x) return ;;
    *) echo -e "${RED}Invalid.${NC}" ;;
  esac
}

# Delete local files only (bound remotes are kept)
_delete_local_copy() {
  local source_dir project_name

  # Bound and local-only projects are both listed; only local files are removed
  source_dir=$(_select_project_from_dir "$PROJECT_ROOT" "Select project to DELETE LOCALLY:") || return
  [[ -z "$source_dir" ]] && return

  project_name=$(basename "$source_dir")

  # Warn differently for bound and local-only projects
  local remotes=()
  mapfile -t remotes < <(git -C "$source_dir" remote 2>/dev/null)
  if [[ ${#remotes[@]} -eq 0 ]]; then
    echo -e "\n${RED}⚠️  This project has NO remote repository.${NC}"
    echo -e "${YELLOW}Deleting it removes the ONLY copy — this cannot be undone.${NC}"
  else
    echo -e "\n${YELLOW}This deletes the local files only.${NC}"
    echo -e "  • Remote repositories stay untouched: ${remotes[*]}"
    echo -e "  • You can clone it again later"
    echo -e "  • ${CYAN}repo-crafter.yml${NC} and legacy ${CYAN}REMOTE_STATE.yml${NC} (if present) are deleted with the folder"
  fi

  confirm_action "Are you sure you want to DELETE the local files of $project_name?" || return

  if execute_dangerous "Delete local directory" rm -rf "$source_dir"; then
    [[ "$DRY_RUN" == "true" ]] || echo -e "${GREEN}✅ Deleted local copy${NC}"
  else
    echo -e "${RED}❌ Failed${NC}"
  fi
  sleep 5
  preview_and_abort_if_dry
}

# Run a platform API delete without printing the raw response body
_delete_remote_quiet() {
  platform_api_call "$@" >/dev/null
}

# Helper: Delete both local and remote
_delete_both() {
  local source_dir project_name

  # Use helper for listing, bounds checking, and selection
  # Multi-server projects hold several remotes; exclude them for now
  source_dir=$(_select_project_from_dir "$REMOTE_ROOT" "Select project to DELETE EVERYTHING:" "$REMOTE_ROOT/Multi-server") || return
  [[ -z "$source_dir" ]] && return
  if [[ "$source_dir" == "$REMOTE_ROOT/Multi-server/"* ]]; then
    echo -e "${YELLOW}Multi-server projects are not handled here. Remove them manually for now.${NC}"
    return 0
  fi

  project_name=$(basename "$source_dir")

  # ENHANCED WARNING - more explicit about consequences
  echo -e "\n${RED} ⚠️ THIS IS A PERMANENT, IRREVERSIBLE ACTION ${NC}"
  echo -e "${YELLOW}This will:${NC}"
  echo -e "  • ${RED}PERMANENTLY DELETE${NC} the remote repository on all platforms"
  echo -e "  • ${RED}PERMANENTLY DELETE${NC} all local project files"
  echo -e "  • ${RED}ALL DATA WILL BE LOST${NC} - this cannot be undone"
  echo -e "\n${YELLOW}To confirm, you must:${NC}"
  echo -e "  1) Type the EXACT project name: '${CYAN}$project_name${NC}'"
  echo -e "  2) Type 'DELETE' to acknowledge permanent data loss"

  # TWO-FACTOR CONFIRMATION
  read -rp "Project name: " confirm_name
  if [[ "$confirm_name" != "$project_name" ]]; then
    echo -e "${RED}❌ Project name mismatch. Operation cancelled.${NC}"
    return
  fi

  read -rp "Type 'DELETE' to confirm permanent deletion: " confirm_delete
  if [[ "$confirm_delete" != "DELETE" ]]; then
    echo -e "${RED}❌ Delete confirmation not provided. Operation cancelled.${NC}"
    return
  fi

  cd "$source_dir" || { echo -e "${RED}❌ Cannot enter '$source_dir'.${NC}"; return 1; }

  # Warn if the manifest and git remotes disagree before deleting anything.
  if [[ -f "repo-crafter.yml" ]]; then
      manifest_reconcile "$PWD" "true" || true
  fi

  # Delete every remote repository, each on its own platform
  echo -e "\n${YELLOW}Deleting remote repositories...${NC}"
  local remotes=()
  mapfile -t remotes < <(git remote 2>/dev/null)
  if [[ ${#remotes[@]} -eq 0 ]]; then
    echo -e "${YELLOW}⚠️  No remotes found. Local files preserved.${NC}"
    return 1
  fi

  local remote url platform delete_endpoint
  for remote in "${remotes[@]}"; do
    url=$(git remote get-url "$remote" 2>/dev/null) || continue
    if ! platform=$(detect_platform_from_url "$url"); then
      echo -e "${RED}❌ Unknown platform for '$remote' ($(_redact_url_credentials "$url")). Local files preserved.${NC}"
      return 1
    fi
    # The target comes from this remote's URL, never from the folder name.
    if ! delete_endpoint=$(_build_delete_endpoint "$platform" "$url"); then
      echo -e "${RED}❌ Refusing to delete '$remote': its URL does not yield a safe endpoint. Local files preserved.${NC}"
      echo -e "${YELLOW}   URL: $(_redact_url_credentials "$url")${NC}"
      return 1
    fi

    if execute_dangerous "Delete remote repository ($platform)" _delete_remote_quiet "$platform" "$delete_endpoint" "${PLATFORM_REPO_DELETE_METHOD[$platform]:-DELETE}"; then
      [[ "$DRY_RUN" == "true" ]] || echo -e "${GREEN}✅ Remote repository deleted ($platform)${NC}"
    else
      echo -e "${RED}❌ Failed to delete remote repository ($platform)${NC}"
      echo -e "${YELLOW}Local files preserved. Operation cancelled.${NC}"
      return 1
    fi
  done

  # Delete local - use execute_dangerous for confirmation
  cd "$HOME"
  echo -e "\n${YELLOW}Deleting local files...${NC}"
  if execute_dangerous "Delete local directory" rm -rf "$source_dir"; then
    [[ "$DRY_RUN" == "true" ]] || echo -e "${GREEN}✅ Deleted everything${NC}"
  else
    echo -e "${RED}❌ Failed to delete local files${NC}"
    return 1
  fi

  sleep 5
  preview_and_abort_if_dry
}


# =================================  GITIGNORE WORKFLOW ====================================
# Standalone gitignore maker with flexible pattern sources
# Append the built-in generic ignore patterns
_append_generic_patterns() {
    local ignore_file="$1"
    cat >> "$ignore_file" << 'EOF'

# ==================== GENERIC PATTERNS ====================
# Operating System
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
Desktop.ini
$RECYCLE.BIN/

# Editors and IDEs
*.swp
*.swo
*~
.idea/
.vscode/
*.sublime-*

# Build and package artifacts
dist/
build/
out/
target/
bin/
obj/
*.min.*
*.map
coverage/

# Logs and temporary files
*.log
*.tmp
*.temp
logs/
tmp/
temp/

# Environment and credentials
.env
.env.*
secrets.json
credentials.json
api_keys.*
EOF
}

gitignore_maker() {
    local project_dir="$1"
    local mode="${2:-standalone}"  # "first-push" or "standalone"
    local ignore_file="$project_dir/.gitignore"

    echo -e "\n${YELLOW}=== Gitignore Setup ===${NC}"

    # Validate project directory
    if [[ ! -d "$project_dir" ]]; then
        echo -e "${RED}❌ Project directory does not exist: $project_dir${NC}"
        return 1
    fi

    if [[ ! -d "$project_dir/.git" ]]; then
        echo -e "${RED}❌ Not a Git repository: $project_dir${NC}"
        echo -e "${YELLOW}Run 'git init' first, then try again.${NC}"
        return 1
    fi

    # DRY RUN mode handling
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}┌─────────────────────────────────────┐${NC}"
        echo -e "${YELLOW}│            DRY RUN MODE             │${NC}"
        echo -e "${YELLOW}│      (No changes will be made)      │${NC}"
        echo -e "${YELLOW}└─────────────────────────────────────┘${NC}"
        echo -e "${YELLOW}[DRY RUN] Gitignore workflow for: $project_dir${NC}"
        echo -e "${YELLOW}Mode: $mode${NC}"

        if [[ -f "$ignore_file" ]]; then
            echo -e "${YELLOW}⚠️  DRY RUN: .gitignore exists - would ask about overwrite${NC}"
        else
            echo -e "${GREEN}✅ DRY RUN: No existing .gitignore found${NC}"
        fi

        echo -e "\n${BLUE}DRY RUN: Would ask for pattern source:${NC}"
        echo "  1) Generic patterns only"
        echo "  2) Fetch from GitHub gitignore templates"
        echo "  3) Manual entry only"

        echo -e "\n${GREEN}✓ DRY RUN completed successfully${NC}"
        return 0
    fi

    # Handle existing .gitignore file
    if [[ -f "$ignore_file" ]]; then
        echo -e "${YELLOW}⚠️  .gitignore already exists:${NC}"
        echo "  $ignore_file"
        echo ""
        echo "${YELLOW}Options:${NC}"
        echo "  1) Review and edit existing file"
        echo "  2) Backup existing and create new"
        echo "  3) Append to existing file"
        echo "  4) Cancel"

        read -rp "Choice (1-4): " existing_choice

        case "$existing_choice" in
            1)
                echo -e "\n${BLUE}Opening existing .gitignore in nano...${NC}"
                nano "$ignore_file"
                echo -e "${GREEN}✓ Review complete${NC}"
                return 0
                ;;
            2)
                local backup_file="${ignore_file}.bak_$(date +%Y%m%d_%H%M%S)"
                mv "$ignore_file" "$backup_file"
                echo -e "${YELLOW}⚠️  Backed up existing .gitignore to:${NC}"
                echo "  $backup_file"
                ;;
            3)
                echo -e "\n${BLUE}Appending to existing .gitignore${NC}"
                echo "" >> "$ignore_file"
                echo "# --- Additional patterns added by repo-crafter ---" >> "$ignore_file"
                ;;
            4|*)
                echo -e "${YELLOW}Cancelled.${NC}"
                return 1
                ;;
        esac
    fi

    # Create new .gitignore file if needed
    if [[ ! -f "$ignore_file" ]]; then
        echo "# Generated by repo-crafter on $(date)" > "$ignore_file"
        echo "" >> "$ignore_file"
    fi

    # Ask about pattern source
    echo -e "\n${BLUE}Where should we get ignore patterns from?${NC}"
    echo "  1) Generic patterns only (OS, editors, build artifacts)"
    echo "  2) Fetch from GitHub gitignore templates"
    echo "  3) Manual entry only (you add everything yourself)"

    read -rp "Choice (1-3): " source_choice

    case "$source_choice" in
        1) # Generic patterns only
            _append_generic_patterns "$ignore_file"
            echo -e "${GREEN}✓ Added generic patterns${NC}"
            ;;

        2) # Fetch from GitHub gitignore templates
            echo -e "\n${BLUE}Fetching available templates from GitHub...${NC}"
                local templates
                templates=$(curl -fsS https://api.github.com/repos/github/gitignore/contents 2>/dev/null | jq -r '.[] | select(.type=="file") | .name' 2>/dev/null | sed 's/\.gitignore$//' || true)

                if [[ -z "$templates" ]]; then
                    echo -e "${YELLOW}⚠️  Failed to fetch templates. Using generic patterns instead.${NC}"
                    _append_generic_patterns "$ignore_file"
                    echo -e "${GREEN}✓ Added generic patterns${NC}"
                else
                    echo -e "\n${BLUE}Select templates to include (space-separated numbers):${NC}"
                    echo "  0) None (skip template selection)"

                    # Show first 20 templates with numbering
                    local i=1
                    while IFS= read -r template; do
                        echo "  $i) $template"
                        ((i++))
                        if [[ $i -gt 20 ]]; then break; fi
                    done <<< "$templates"

                    echo ""
                    echo "Example: '1 3 5' for first, third, and fifth templates"
                    read -rp "Selection: " template_selection

                    if [[ "$template_selection" != "0" && -n "$template_selection" ]]; then
                        echo "" >> "$ignore_file"
                        echo "# ==================== TEMPLATES ====================" >> "$ignore_file"

                        for num in $template_selection; do
                            if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -gt 0 ]] && [[ "$num" -le 20 ]]; then
                                local template_name
                                template_name=$(echo "$templates" | sed -n "${num}p")
                                if [[ -n "$template_name" ]]; then
                                    echo -e "\n${BLUE}Fetching $template_name template...${NC}"
                                    local template_body
                                    if template_body=$(curl -fsS "https://raw.githubusercontent.com/github/gitignore/main/${template_name}.gitignore" 2>/dev/null); then
                                        {
                                            echo ""
                                            echo "# --- $template_name ---"
                                            printf '%s\n' "$template_body"
                                        } >> "$ignore_file"
                                        echo -e "${GREEN}✓ Added $template_name patterns${NC}"
                                    else
                                        echo -e "${YELLOW}⚠️  Failed to fetch $template_name; skipped.${NC}"
                                    fi
                                fi
                            fi
                        done
                    fi
                fi
            ;;

        3) # Manual entry only
            echo -e "${YELLOW}Skipping predefined patterns${NC}"
            ;;
    esac

    # Custom patterns entry
    echo -e "\n${BLUE}Add custom ignore patterns (one per line, empty line to finish):${NC}"
    echo "Examples: my-config.json, temp/, *.tmp"

    while true; do
        read -rp "Pattern: " pattern
        [[ -z "$pattern" ]] && break
        echo "$pattern" >> "$ignore_file"
        echo -e "${GREEN}✓ Added: $pattern${NC}"
    done

    # Mode selection
    echo -e "\n${BLUE}Select gitignore mode:${NC}"
    echo "  1) Commit to repository (recommended)"
    echo "  2) Keep local only (.git/info/exclude - never pushed)"

    read -rp "Choice (1-2): " mode_choice

    local strategy="normal"

    case "$mode_choice" in
        1) # Commit to repository
            echo -e "\n${BLUE}Committing .gitignore changes...${NC}"

            if git -C "$project_dir" add ".gitignore"; then
                if git -C "$project_dir" commit -m "Add/update .gitignore patterns"; then
                    echo -e "${GREEN}✓ Successfully committed .gitignore${NC}"
                else
                    echo -e "${YELLOW}⚠️  Commit failed. Changes staged but not committed.${NC}"
                    echo -e "${YELLOW}Run 'git commit -m \"Add .gitignore\"' to complete.${NC}"
                    return 1
                fi
            else
                echo -e "${RED}❌ Failed to stage .gitignore${NC}"
                return 1
            fi
            ;;

        2) # Local only
            echo -e "\n${RED}⚠️  LOCAL-ONLY MODE SELECTED${NC}"
            echo -e "${YELLOW}Patterns will be stored in .git/info/exclude and NEVER pushed to remote repositories.${NC}"
            echo "This is useful for personal IDE settings or machine-specific configurations."

            if ! confirm_action "Proceed with local-only mode?"; then
                echo -e "${YELLOW}Cancelled.${NC}"
                return 1
            fi

            local exclude_file="$project_dir/.git/info/exclude"
            mkdir -p "$(dirname "$exclude_file")"

            if [[ -f "$ignore_file" ]]; then
                cat "$ignore_file" >> "$exclude_file"
                rm "$ignore_file"
                echo -e "${GREEN}✓ Moved patterns to local exclude file${NC}"
            else
                touch "$exclude_file"
                echo "# Local-only patterns (never pushed)" > "$exclude_file"
            fi

            strategy="exclude"
            ;;

        *)
            echo -e "${YELLOW}Cancelled. Patterns were written to .gitignore but nothing was committed.${NC}"
            return 1
            ;;
    esac

    # Create template file for documentation (only when committing)
    if [[ "$strategy" == "normal" ]]; then
    cat > "$project_dir/.gitignore.template" << 'EOF'
# ==================== GITIGNORE TEMPLATE ====================
# This file is for reference only. Copy patterns to .gitignore as needed.
#
# How to use:
# 1. Review patterns in this template
# 2. Copy needed patterns to your .gitignore file
# 3. Commit the .gitignore file to share with team members
#
# Common categories to consider:
#
# Operating System Files:
# .DS_Store (macOS)
# Thumbs.db (Windows)
# .Trash/ (Linux)
#
# IDE/Editor Files:
# .vscode/
# .idea/
# *.swp (Vim)
# *.suo (Visual Studio)
#
# Build Artifacts:
# dist/
# build/
# *.min.js
# *.map
#
# Environment Files:
# .env
# config.local
#
# Note: For sensitive files like API keys or credentials,
# consider using .git/info/exclude (local-only) instead.
EOF
    echo -e "${GREEN}✓ Created .gitignore.template for reference${NC}"
    fi

    # Return strategy for caller
    if [[ "$strategy" == "exclude" ]]; then
        echo "exclude"
        return 0
    fi

    echo "normal"
    return 0
}

# ======================= UTILITY HELPERS ==========================
# to get detials from given repo
# Parse owner from SSH/HTTPS URL
get_owner_from_ssh_url() {
    local ssh_url="$1"

    # SSH: git@github.com:owner/repo.git → owner
    if [[ "$ssh_url" =~ ^git@[^:]+:(.+)/[^/]+\.git$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    # HTTPS: https://github.com/owner/repo.git → owner
    if [[ "$ssh_url" =~ ^https?://[^/]+/(.+)/[^/]+\.git$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    # No .git suffix: git@github.com:owner/repo → owner
    if [[ "$ssh_url" =~ ^git@[^:]+:(.+)/[^/]+$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# Detect current branch name safely
detect_current_branch() {
    git symbolic-ref --short HEAD 2>/dev/null ||
    git rev-parse --abbrev-ref HEAD 2>/dev/null ||
    git config --get init.defaultBranch 2>/dev/null ||
    echo "main"
}

# Check and handle existing remote with the same name
handle_existing_remote() {
    local platform="$1"  # e.g., "gitlab"
    local remote_url="$2" # The new URL to add

    # Reject option-injection / non-standard transports before git sees the URL.
    _validate_git_url "$remote_url" || {
        echo -e "${RED}❌ Invalid remote URL: '$remote_url'${NC}" >&2
        echo -e "${YELLOW}   Only https://… or git@host:… URLs are accepted.${NC}" >&2
        return 1
    }

    if git remote get-url "$platform" &>/dev/null; then
        echo -e "${YELLOW}⚠️  A remote named '$platform' already exists in this repository.${NC}"
        echo "Current URL: $(_redact_url_credentials "$(git remote get-url "$platform")")"
        echo "New URL:     $(_redact_url_credentials "$remote_url")"

        if confirm_action "Do you want to update the existing remote '$platform' to point to the new URL?" "y" "Update remote"; then
            execute_dangerous "Update remote $platform" git remote set-url "$platform" -- "$remote_url"
            return 0
        else
            echo -e "${YELLOW}⚠️  Keeping existing remote '$platform'. You may need to choose a different platform name.${NC}"
            return 1  # Signal to caller that we shouldn't proceed
        fi
    fi
    return 0  # No conflict, proceed normally
}

# Helper: Check and remove any existing remotes (for local-only projects)
remove_existing_remotes() {
    local dir="${1:-.}"
    local remotes
    remotes=$(git -C "$dir" remote 2>/dev/null)

    if [[ -n "$remotes" ]]; then
        echo ""
        echo -e "${YELLOW}⚠️  Existing remotes detected in this local project:${NC}"
        git -C "$dir" remote -v

        if confirm_action "Remove all remotes to make project truly local-only?" "n" "Remove remotes"; then
            local remote
            while read -r remote; do
                execute_dangerous "Remove remote $remote" git -C "$dir" remote remove "$remote"
            done <<< "$remotes"
            return 0
        else
            echo -e "${YELLOW}⚠️  Keeping existing remotes (not truly local-only)${NC}"
            return 1
        fi
    fi
    return 0  # No remotes found, proceed normally
}

# CORRECT universal git URL parser
parse_git_url() {
    local url="$1"

    # Remove protocol prefixes (ssh://, https://, http://, git://)
    # This handles ALL URL formats in one regex
    if [[ "$url" =~ ^[a-z\+]+:// ]]; then
        # Remove protocol:// part
        url="${url#*://}"
        # Remove userinfo@ part (username:token@ or username@)
        url="${url#*@}"
    fi

    # Handle SSH URL format (git@host:path). Keep the full owner/repo path.
    if [[ "$url" =~ ^[^/@]+@[^:/]+:(.+) ]]; then
        url="${BASH_REMATCH[1]}"
    else
        # Protocol form: remove the host part (everything up to first '/')
        url="${url#*/}"
    fi

    # Remove .git suffix if present
    url="${url%.git}"

    # Remove any leading/trailing slashes
    url="${url#/}"
    url="${url%/}"

    echo "$url"
}


# Remove HTTP(S) userinfo (user[:password]@) from a URL. Used before a URL is
# stored, compared, or printed so an embedded token never reaches the manifest,
# a log, or the terminal. SSH user names (git@host) are left untouched.
_redact_url_credentials() {
    local url="$1"
    if [[ "$url" =~ ^(https?://)[^/@]+@(.*)$ ]]; then
        printf '%s%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    else
        printf '%s' "$url"
    fi
}

# Percent-encode one path segment for an API URL. jq is already a hard
# dependency, so this adds no new requirement.
_url_encode_segment() {
    printf '%s' "$1" | jq -sRr @uri
}

# Validate an owner taken from a remote URL before it is interpolated into a
# delete endpoint. Anything that could retarget the request path is rejected.
#   github: one name, [A-Za-z0-9._-]
#   gitlab: nested groups allowed, but no traversal or encoded separators
_validate_remote_owner() {
    local platform="$1" owner="$2"
    [[ -z "$owner" ]] && return 1
    [[ "$owner" == "." ]] && return 1
    [[ "$owner" == *$'\n'* || "$owner" == *$'\r'* || "$owner" == *$'\t'* ]] && return 1
    [[ "$owner" == *..* || "$owner" == *%* || "$owner" == *\?* || "$owner" == *\#* ]] && return 1
    [[ "$owner" == /* || "$owner" == */ || "$owner" == *//* ]] && return 1
    case "$platform" in
        github) [[ "$owner" =~ ^[A-Za-z0-9._-]+$ ]] || return 1 ;;
        gitlab) [[ "$owner" =~ ^[A-Za-z0-9._/-]+$ ]] || return 1 ;;
        *) return 1 ;;
    esac
    return 0
}

# Validate a repository name taken from a remote URL. It must be a single
# path segment on both supported platforms.
_validate_remote_repo() {
    local repo="$1"
    [[ -z "$repo" ]] && return 1
    [[ "$repo" == "." || "$repo" == ".." ]] && return 1
    [[ "$repo" == *..* || "$repo" == *%* || "$repo" == *\?* || "$repo" == *\#* ]] && return 1
    [[ "$repo" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    return 0
}

# Build a delete endpoint from the remote URL itself, never from the local
# directory name. Owner and repository are validated and percent-encoded before
# substitution. Returns 1 without any API call when the URL is not trustworthy.
_build_delete_endpoint() {
    local platform="$1" url="$2"
    local template="${PLATFORM_REPO_DELETE_ENDPOINT[$platform]:-}"
    [[ -z "$template" ]] && return 1

    local path owner repo
    path=$(parse_git_url "$url")
    [[ -z "$path" || "$path" != */* ]] && return 1
    repo="${path##*/}"
    owner="${path%/*}"

    _validate_remote_owner "$platform" "$owner" || return 1
    _validate_remote_repo "$repo" || return 1

    local enc_owner enc_repo
    enc_owner=$(_url_encode_segment "$owner")
    enc_repo=$(_url_encode_segment "$repo")

    template="${template//\{owner\}/$enc_owner}"
    template="${template//\{repo\}/$enc_repo}"
    printf '%s' "$template"
}

# Detect platform from a git URL
# Returns: platform name or empty string if not found
detect_platform_from_url() {
    local url="$1"
    [[ -z "$url" ]] && return 1

    # Extract host from URL
    local host=""
    if [[ "$url" =~ ^git@([^:]+): ]]; then
        host="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ ^https?://([^/]+)/ ]]; then
        host="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ ^[^@]+@([^:/]+) ]]; then
        host="${BASH_REMATCH[1]}"
    fi

    # Drop any HTTP(S) userinfo before comparing the host.
    host="${host##*@}"

    [[ -z "$host" ]] && return 1

    # Match against known platforms
    for p in "${AVAILABLE_PLATFORMS[@]}"; do
        if [[ "$host" == "${PLATFORM_REPO_DOMAIN[$p]}" ]] || [[ "$host" == "${PLATFORM_SSH_HOST[$p]}" ]]; then
            echo "$p"
            return 0
        fi
    done

    return 1
}


# Extract host from a git URL
# Returns: hostname or empty string
extract_host_from_url() {
    local url="$1"
    [[ -z "$url" ]] && return 1

    local host=""
    if [[ "$url" =~ ^git@([^:]+): ]]; then
        host="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ ^https?://([^/]+)/ ]]; then
        host="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ ^[^@]+@([^:/]+) ]]; then
        host="${BASH_REMATCH[1]}"
    fi

    # Drop any HTTP(S) userinfo so a token cannot be mistaken for the host.
    host="${host##*@}"
    [[ -n "$host" ]] && echo "$host"
}


# Preview operation and return to menu if in dry-run mode
preview_and_abort_if_dry() {
  if [[ "$DRY_RUN" != "true" ]]; then
    return 0
  fi

  echo -e "\n${YELLOW}┌─────────────────────────────────────────────────────┐${NC}"
  echo -e "${YELLOW}│                  DRY RUN COMPLETE                   │${NC}"
  echo -e "${YELLOW}│             NO CHANGES WERE MADE                    │${NC}"
  echo -e "${YELLOW}└─────────────────────────────────────────────────────┘${NC}"

  # Show accumulated dry-run actions
  if [[ ${#DRY_RUN_ACTIONS[@]} -gt 0 ]]; then
    echo -e "\n${BLUE}Planned actions:${NC}"
    local i=1
    for action in "${DRY_RUN_ACTIONS[@]}"; do
      echo -e "  ${i}) ${action}"
      ((i++))
    done
  fi

  echo -e "\n${YELLOW}To execute these actions for real, run without --dry-run${NC}"
  echo -e "${YELLOW}Or with: ${CYAN}repo-crafter.sh <command> <args>${NC}"

  return 0
}

# Gitignore Helper wrapper
gitignore_maker_interactive() {
  echo -e "\n${BLUE}=== Gitignore Manager ===${NC}"
  local dir
  dir=$(_select_project_from_dir "$PROJECT_ROOT" "Select project for .gitignore:") || return 1
  [[ -n "$dir" ]] || return 1
  gitignore_maker "$dir" "standalone" || true
}


# ======================= MANIFEST (HUMAN-OWNED INTENT) =========================
# repo-crafter.yml is the committed source of truth. The tool reads it and only
# writes it on an explicit create/convert/init/migrate action. Volatile state
# (head commits, timestamps, ahead/behind) is never stored here; it is derived
# from git on demand.

_url_host() {
  local url="$1" host=""

  if [[ "$url" =~ ^[a-z][a-z0-9+.-]*://([^/]+)/ ]]; then
    host="${BASH_REMATCH[1]}"
  elif [[ "$url" =~ ^[^/@]+@([^:/]+)[:/] ]]; then
    host="${BASH_REMATCH[1]}"
  else
    return 1
  fi

  host="${host##*@}"
  [[ -n "$host" ]] || return 1
  printf '%s' "$host"
}

_yaml_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  # Escape control characters so they stay inside the quoted scalar and can
  # not break out to inject YAML keys or emit terminal escapes.
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  value="${value//$'\e'/\\e}"
  printf '"%s"' "$value"
}

_manifest_write_atomic() {
  local target="$1"
  local content="$2"
  local dir tmp

  dir=$(dirname "$target")
  tmp=$(mktemp "$dir/.repo-crafter.yml.XXXXXX") || {
    echo -e "${RED}❌ Could not create a temporary manifest in $dir${NC}" >&2
    return 1
  }

  if ! printf '%s\n' "$content" > "$tmp"; then
    rm -f "$tmp"
    echo -e "${RED}❌ Could not write the temporary manifest${NC}" >&2
    return 1
  fi

  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    echo -e "${RED}❌ Refusing to write an empty manifest${NC}" >&2
    return 1
  fi

  # Validate before replacing the original. yq is optional; when present it is
  # the strongest check. The original file is never touched on failure.
  if command -v yq &>/dev/null; then
    if ! yq e '.' "$tmp" >/dev/null 2>&1; then
      rm -f "$tmp"
      echo -e "${RED}❌ Generated manifest is not valid YAML; original left untouched.${NC}" >&2
      return 1
    fi
  fi

  # Keep the previous version inside the git dir (never committed) before an
  # explicit rewrite. This is a convenience copy; git history remains the
  # primary recovery path for a committed manifest.
  if [[ -f "$target" ]]; then
    local git_dir
    git_dir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null || true)
    if [[ -n "$git_dir" ]]; then
      [[ "$git_dir" == /* ]] || git_dir="$dir/$git_dir"
      mkdir -p "$git_dir/repo-crafter" 2>/dev/null || true
      cp -p "$target" "$git_dir/repo-crafter/repo-crafter.yml.bak" 2>/dev/null || true
    fi
  fi

  chmod 0644 "$tmp" 2>/dev/null || true
  if ! mv -f "$tmp" "$target"; then
    rm -f "$tmp"
    echo -e "${RED}❌ Could not replace $target; original left untouched.${NC}" >&2
    return 1
  fi
  return 0
}

create_manifest() {
  local dir="$1"
  local action_type="${2:-create}"
  local primary_url="${3:-}"

  if [[ "$DRY_RUN" == "true" ]]; then
    DRY_RUN_ACTIONS+=("Create manifest at $dir/repo-crafter.yml (schema 1)")
    return 0
  fi

  if ! git -C "$dir" rev-parse --git-dir &>/dev/null; then
    echo -e "${RED}❌ Cannot create a manifest: '$dir' is not a git repository.${NC}" >&2
    return 1
  fi

  # Build the remote list from the actual git remotes, never from platform
  # detection. This keeps manifest names identical to `git remote` names even
  # when a rename failed or a collision suffix was used.
  local -a remote_names=() remote_urls=()
  local rname rurl seen=""
  local remote
  while IFS= read -r remote; do
    [[ -z "$remote" ]] && continue
    rname="$remote"
    case " $seen " in *" $rname "*) continue ;; esac
    seen+=" $rname"
    # Read the URL via config, not by parsing `git remote -v` lines. That keeps
    # embedded newlines/spaces in the URL intact instead of awk splitting them
    # into fake remotes (e.g. name/injected:, url/"yes").
    rurl=$(git -C "$dir" config "remote.${rname}.url" 2>/dev/null || true)
    [[ -z "$rurl" ]] && continue
    case "$rurl" in
      *[$'\n\r\t\e\f\v']*)
        echo -e "${RED}❌ Cannot create a manifest: remote '$rname' URL contains control characters.${NC}" >&2
        echo -e "${YELLOW}   Remove the offending remote and retry.${NC}" >&2
        return 1
        ;;
    esac
    remote_names+=("$rname")
    remote_urls+=("$rurl")
  done < <(git -C "$dir" remote 2>/dev/null)

  if [[ ${#remote_names[@]} -eq 0 ]]; then
    echo -e "${RED}❌ Cannot create a manifest: no git remotes found.${NC}" >&2
    return 1
  fi

  local project_name default_branch primary_name=""
  local now
  project_name=$(basename "$dir")
  default_branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || echo "main")
  now=$(date +"%Y-%m-%dT%H:%M:%S%z")

  # The primary remote is the one whose URL is the project's original/current
  # remote; otherwise the first remote git reports.
  local i
  if [[ -n "$primary_url" ]]; then
    for i in "${!remote_urls[@]}"; do
      if [[ "${remote_urls[$i]}" == "$primary_url" ]]; then
        # Prefer origin when several remotes share the same URL.
        if [[ -z "$primary_name" || "${remote_names[$i]}" == "origin" ]]; then
          primary_name="${remote_names[$i]}"
        fi
        [[ "$primary_name" == "origin" ]] && break
      fi
    done
  fi
  if [[ -z "$primary_name" ]]; then
    if [[ " ${remote_names[*]} " == *" origin "* ]]; then
      primary_name="origin"
    else
      primary_name="${remote_names[0]}"
    fi
  fi

  local content=""
  content+="# repo-crafter manifest"$'\n'
  content+="# Declares intent. repo-crafter reads this file; edit it deliberately."$'\n'
  content+="# Generated: ${now}"$'\n'
  content+="# Action: ${action_type}"$'\n'
  content+=""$'\n'
  content+="schema: 1"$'\n'
  content+=""$'\n'
  content+="project:"$'\n'
  content+="  name: $(_yaml_quote "$project_name")"$'\n'
  content+="  default_branch: $(_yaml_quote "$default_branch")"$'\n'
  content+=""$'\n'
  content+="remotes:"$'\n'

  local host owner repo path platform role display_url redacted_any=false
  for i in "${!remote_names[@]}"; do
    rname="${remote_names[$i]}"
    rurl="${remote_urls[$i]}"

    host=$(_url_host "$rurl" 2>/dev/null || true)
    path=$(parse_git_url "$rurl")
    repo="${path##*/}"
    owner="${path%/*}"
    [[ "$owner" == "$path" ]] && owner=""
    platform=$(detect_platform_from_url "$rurl" 2>/dev/null || true)
    [[ -z "$platform" ]] && platform="unknown"
    if [[ "$rname" == "$primary_name" ]]; then role="primary"; else role="mirror"; fi

    # Never commit credentials: the manifest records the canonical URL only.
    display_url=$(_redact_url_credentials "$rurl")
    [[ "$display_url" != "$rurl" ]] && redacted_any=true

    content+="  - name: $(_yaml_quote "$rname")"$'\n'
    content+="    platform: $(_yaml_quote "$platform")"$'\n'
    [[ -n "$host" ]] && content+="    host: $(_yaml_quote "$host")"$'\n'
    [[ -n "$owner" ]] && content+="    owner: $(_yaml_quote "$owner")"$'\n'
    content+="    repo: $(_yaml_quote "$repo")"$'\n'
    content+="    role: $(_yaml_quote "$role")"$'\n'
    content+="    url: $(_yaml_quote "$display_url")"$'\n'
  done

  if [[ "$redacted_any" == "true" ]]; then
    echo -e "${YELLOW}⚠️  Credentials embedded in a remote URL were removed from the manifest.${NC}" >&2
    echo -e "${YELLOW}   Keep tokens out of committed files; use SSH or a credential helper.${NC}" >&2
  fi

  if ! _manifest_write_atomic "$dir/repo-crafter.yml" "$content"; then
    return 1
  fi

  echo -e "${GREEN}✓ Manifest written: $dir/repo-crafter.yml${NC}"
  echo -e "${YELLOW}  Commit it so the declared intent travels with the project.${NC}"
  return 0
}

# Strip one layer of YAML quoting and surrounding whitespace.
_manifest_unquote() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  # A trailing comment is allowed on unquoted scalars.
  if [[ "$value" != \"* && "$value" != \'* ]]; then
    value="${value%%[[:space:]]#*}"
    value="${value%"${value##*[![:space:]]}"}"
  fi
  if [[ ${#value} -ge 2 && "$value" == \"*\" ]]; then
    value="${value:1:${#value}-2}"
    value="${value//\\\"/\"}"
    value="${value//\\\\/\\}"
  elif [[ ${#value} -ge 2 && "$value" == \'*\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

# Read the documented block-YAML subset without requiring yq. The reader is
# indentation-tolerant inside project/remotes and ignores comments and blanks.
_manifest_read_awk() {
  local file="$1"
  local line key value section="" have_remote=0
  local r_name="" r_platform="" r_host="" r_owner="" r_repo="" r_role="" r_url=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

    if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      case "$key" in
        schema)
          printf 'SCHEMA\x1f%s\n' "$(_manifest_unquote "$value")"
          section=""
          ;;
        project) section="project" ;;
        remotes) section="remotes" ;;
        *) section="" ;;
      esac
      continue
    fi

    if [[ "$section" == "project" && "$line" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value=$(_manifest_unquote "${BASH_REMATCH[2]}")
      printf 'PROJECT\x1f%s\x1f%s\n' "$key" "$value"
      continue
    fi

    if [[ "$section" == "remotes" ]]; then
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.*)$ ]]; then
        if [[ "$have_remote" == "1" ]]; then
          printf 'REMOTE\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n' \
            "$r_name" "$r_platform" "$r_host" "$r_owner" "$r_repo" "$r_role" "$r_url"
        fi
        have_remote=1
        r_name=$(_manifest_unquote "${BASH_REMATCH[1]}")
        r_platform=""; r_host=""; r_owner=""; r_repo=""; r_role=""; r_url=""
        continue
      fi
      if [[ "$have_remote" == "1" && "$line" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value=$(_manifest_unquote "${BASH_REMATCH[2]}")
        case "$key" in
          platform) r_platform="$value" ;;
          host) r_host="$value" ;;
          owner) r_owner="$value" ;;
          repo) r_repo="$value" ;;
          role) r_role="$value" ;;
          url) r_url="$value" ;;
        esac
        continue
      fi
    fi
  done < "$file"

  if [[ "$have_remote" == "1" ]]; then
    printf 'REMOTE\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n' \
      "$r_name" "$r_platform" "$r_host" "$r_owner" "$r_repo" "$r_role" "$r_url"
  fi
}

# yq handles full YAML; jq turns it into the same line format as the awk reader.
_manifest_read_yq() {
  local file="$1"
  yq e -o=json '.' "$file" 2>/dev/null | jq -r '
    (
      "SCHEMA\u001f\((.schema // "") | tostring)",
      "PROJECT\u001fname\u001f\((.project.name // "") | tostring)",
      "PROJECT\u001fdefault_branch\u001f\((.project.default_branch // "") | tostring)",
      ((.remotes // [])[] |
        "REMOTE\u001f\((.name // "") | tostring)\u001f\((.platform // "") | tostring)\u001f\((.host // "") | tostring)\u001f\((.owner // "") | tostring)\u001f\((.repo // "") | tostring)\u001f\((.role // "") | tostring)\u001f\((.url // "") | tostring)")
    )
  '
}

# Emit normalized lines: SCHEMA<TAB>value, PROJECT<TAB>key<TAB>value,
# REMOTE<TAB>name<TAB>platform<TAB>host<TAB>owner<TAB>repo<TAB>role<TAB>url.
# Returns 2 when the manifest is absent, 1 when it cannot be parsed.
_manifest_read() {
  local dir="$1"
  local file="$dir/repo-crafter.yml"
  [[ -f "$file" ]] || return 2

  if command -v yq &>/dev/null; then
    _manifest_read_yq "$file"
  else
    _manifest_read_awk "$file"
  fi
}

# Validate the declared intent. Never writes. Returns 0 valid, 1 invalid,
# 2 absent.
manifest_validate() {
  local dir="$1"
  local file="$dir/repo-crafter.yml"
  local output line kind a b c d e f g
  local schema="" project_name="" default_branch=""
  local remote_count=0 primary_count=0 errors=0 warnings=0
  local -A seen_names=()

  if [[ ! -f "$file" ]]; then
    echo -e "${YELLOW}No manifest found: $file${NC}"
    return 2
  fi

  if ! output=$(_manifest_read "$dir"); then
    echo -e "${RED}❌ Could not parse $file${NC}"
    return 1
  fi
  [[ -n "$output" ]] || { echo -e "${RED}❌ Manifest is empty: $file${NC}"; return 1; }

  while IFS=$'\x1f' read -r kind a b c d e f g; do
    case "$kind" in
      SCHEMA)
        schema="$a"
        ;;
      PROJECT)
        case "$a" in
          name) project_name="$b" ;;
          default_branch) default_branch="$b" ;;
        esac
        ;;
      REMOTE)
        remote_count=$((remote_count + 1))
        local rname="$a" rrole="$f" rurl="$g"
        if [[ -z "$rname" ]]; then
          echo -e "${RED}❌ Remote entry #$remote_count has no name.${NC}"
          errors=$((errors + 1))
          continue
        fi
        if [[ -n "${seen_names[$rname]:-}" ]]; then
          echo -e "${RED}❌ Duplicate remote name: '$rname'.${NC}"
          errors=$((errors + 1))
        fi
        seen_names["$rname"]=1
        if [[ -z "$rurl" && -z "$e" ]]; then
          echo -e "${YELLOW}⚠️  Remote '$rname' has neither url nor repo; reconciliation will skip it.${NC}"
          warnings=$((warnings + 1))
        fi
        if [[ "$rrole" == "primary" ]]; then
          primary_count=$((primary_count + 1))
        elif [[ -n "$rrole" && "$rrole" != "mirror" ]]; then
          echo -e "${YELLOW}⚠️  Remote '$rname' has unknown role '$rrole'.${NC}"
          warnings=$((warnings + 1))
        fi
        ;;
    esac
  done <<< "$output"

  if [[ "$schema" != "1" ]]; then
    echo -e "${RED}❌ Unsupported or missing schema: '${schema:-none}' (expected 1).${NC}"
    errors=$((errors + 1))
  fi
  if [[ -z "$project_name" ]]; then
    echo -e "${RED}❌ project.name is missing.${NC}"
    errors=$((errors + 1))
  fi
  if [[ -z "$default_branch" ]]; then
    echo -e "${YELLOW}⚠️  project.default_branch is missing.${NC}"
    warnings=$((warnings + 1))
  fi
  if [[ $remote_count -eq 0 ]]; then
    echo -e "${RED}❌ The manifest declares no remotes.${NC}"
    errors=$((errors + 1))
  fi
  if [[ $remote_count -gt 0 && $primary_count -eq 0 ]]; then
    echo -e "${YELLOW}⚠️  No remote is marked role: primary.${NC}"
    warnings=$((warnings + 1))
  elif [[ $primary_count -gt 1 ]]; then
    echo -e "${YELLOW}⚠️  More than one remote is marked role: primary.${NC}"
    warnings=$((warnings + 1))
  fi

  if [[ $errors -gt 0 ]]; then
    echo -e "${RED}❌ Manifest invalid: $errors error(s), $warnings warning(s).${NC}"
    return 1
  fi
  echo -e "${GREEN}✓ Manifest valid: $remote_count remote(s), $warnings warning(s).${NC}"
  return 0
}

# Compare declared remotes with the actual git remotes. Read-only: reports
# drift and returns 1, but never blocks the caller unless it chooses to.
manifest_reconcile() {
  local dir="$1"
  local quiet="${2:-false}"
  local file="$dir/repo-crafter.yml"
  [[ -f "$file" ]] || return 0

  if ! manifest_validate "$dir" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Manifest is invalid; not reconciling against git.${NC}"
    return 1
  fi

  local -A declared=() declared_url=()
  local output line kind a b c d e f g
  output=$(_manifest_read "$dir") || return 1
  while IFS=$'\x1f' read -r kind a b c d e f g; do
    [[ "$kind" == "REMOTE" ]] || continue
    declared["$a"]=1
    # Compare canonical URLs so credentials in git never look like drift.
    declared_url["$a"]=$(_redact_url_credentials "$g")
  done <<< "$output"

  local -A actual=() actual_url=()
  local rname rurl
  while IFS=$'\t' read -r rname rurl; do
    [[ -z "$rname" ]] && continue
    actual["$rname"]=1
    actual_url["$rname"]=$(_redact_url_credentials "$rurl")
  done < <(git -C "$dir" remote -v 2>/dev/null | awk '$3 == "(fetch)" { print $1 "\t" $2 }')

  local drift=0 alt
  for rname in "${!declared[@]}"; do
    if [[ -z "${actual[$rname]:-}" ]]; then
      alt=""
      for a in "${!actual_url[@]}"; do
        if [[ -n "${declared_url[$rname]}" && "${actual_url[$a]}" == "${declared_url[$rname]}" ]]; then
          alt="$a"
          break
        fi
      done
      if [[ -n "$alt" ]]; then
        echo -e "${YELLOW}⚠️  Manifest remote '$rname' is named '$alt' in git (same URL).${NC}"
      else
        echo -e "${YELLOW}⚠️  Manifest remote '$rname' is missing from git.${NC}"
      fi
      drift=1
    elif [[ -n "${declared_url[$rname]}" && "${actual_url[$rname]}" != "${declared_url[$rname]}" ]]; then
      echo -e "${YELLOW}⚠️  Manifest remote '$rname' URL differs:${NC}"
      echo -e "     manifest: ${declared_url[$rname]}"
      echo -e "     git     : ${actual_url[$rname]}"
      drift=1
    fi
  done

  for rname in "${!actual[@]}"; do
    if [[ -z "${declared[$rname]:-}" ]]; then
      echo -e "${YELLOW}⚠️  Git remote '$rname' is not declared in the manifest.${NC}"
      drift=1
    fi
  done

  if [[ $drift -eq 0 ]]; then
    [[ "$quiet" == "true" ]] || echo -e "${GREEN}✓ Manifest matches git remotes.${NC}"
    return 0
  fi
  return 1
}

# Move a legacy REMOTE_STATE.yml into .git/repo-crafter/legacy, then build the
# new manifest from git. The legacy file is restored if the new write fails.
manifest_migrate_legacy() {
  local dir="$1"
  local legacy="$dir/REMOTE_STATE.yml"
  local new="$dir/repo-crafter.yml"
  local git_dir backup_dir

  [[ -f "$legacy" ]] || return 0
  if [[ -f "$new" ]]; then
    echo -e "${YELLOW}Both repo-crafter.yml and legacy REMOTE_STATE.yml exist; leaving both untouched.${NC}"
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    DRY_RUN_ACTIONS+=("Migrate legacy manifest $legacy to $new")
    return 0
  fi

  git_dir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null) || {
    echo -e "${RED}❌ Cannot migrate: '$dir' is not a git repository.${NC}" >&2
    return 1
  }
  [[ "$git_dir" == /* ]] || git_dir="$dir/$git_dir"
  backup_dir="$git_dir/repo-crafter/legacy"

  mkdir -p "$backup_dir" || return 1
  if ! mv "$legacy" "$backup_dir/REMOTE_STATE.yml"; then
    echo -e "${RED}❌ Could not preserve the legacy manifest; migration aborted.${NC}" >&2
    return 1
  fi

  if ! create_manifest "$dir" "migrate_legacy" ""; then
    mv "$backup_dir/REMOTE_STATE.yml" "$legacy" 2>/dev/null || true
    echo -e "${RED}❌ Migration failed; legacy manifest restored.${NC}" >&2
    return 1
  fi

  echo -e "${GREEN}✓ Legacy manifest preserved at $backup_dir/REMOTE_STATE.yml${NC}"
  return 0
}

# Interactive home for check / create / migrate.
manifest_workflow() {
  echo -e "\n${BLUE}=== PROJECT MANIFEST ===${NC}"

  local project_dir
  project_dir=$(_select_project_from_dir "$REMOTE_ROOT" "Projects available:") || return 0
  [[ -z "$project_dir" ]] && return 0

  local manifest="$project_dir/repo-crafter.yml"
  local legacy="$project_dir/REMOTE_STATE.yml"

  if [[ -f "$legacy" && ! -f "$manifest" ]]; then
    if confirm_action "Migrate legacy REMOTE_STATE.yml to repo-crafter.yml?" "y"; then
      manifest_migrate_legacy "$project_dir" || true
    fi
  fi

  if [[ -f "$manifest" ]]; then
    if manifest_validate "$project_dir"; then
      manifest_reconcile "$project_dir" || true
      if confirm_action "Rewrite repo-crafter.yml from the current git remotes?" "n"; then
        create_manifest "$project_dir" "rewrite" "" || true
      fi
    else
      echo -e "${YELLOW}Fix the manifest before rewriting it; the current file was left untouched.${NC}"
    fi
  else
    if confirm_action "No manifest found. Create one from the current git remotes?" "y"; then
      create_manifest "$project_dir" "init" "" || true
    fi
  fi

  read -rp $'\n'"Press Enter to continue..." -n 1 || true
}

# Prompt for project name with validation
_prompt_project_name() {
  local name
  while true; do
    read -rp "Project name: " name || return 1
    [[ -z "$name" ]] && continue
    if validate_project_name "$name" "project name"; then
      echo "$name"
      return 0
    fi
  done
}

# Prompt for visibility (private/public)
# Prompts go to stderr (user sees), result to stdout (captured)
_prompt_visibility() {
  # Prompts to stderr so user sees them
  echo "" >&2
  echo "Repository visibility?" >&2
  echo "  1) Private  2) Public" >&2
  echo "" >&2
  echo -n "Choice (1-2): " >&2

  # Read from stdin
  read choice

  echo "" >&2

  # Result to stdout (for command substitution)
  if [[ "$choice" == "1" ]]; then
    echo "private"
  else
    echo "public"
  fi
}

# Select project from directory
_select_project_from_dir() {
    local root_dir="$1"
    local prompt="$2"
    local exclude_dir="${3:-}"
    local projects=()

    # Resolve the root once so prefix checks compare canonical paths
    local root_canon
    root_canon=$(realpath -e "$root_dir" 2>/dev/null) || root_canon="$root_dir"

    local local_root_canon
    local_root_canon=$(realpath -e "$LOCAL_ROOT" 2>/dev/null) || local_root_canon="$LOCAL_ROOT"

    # Find all project directories
    if [[ "$root_canon" == "$local_root_canon" ]]; then
        # Local projects: flat structure
        while IFS= read -r p; do
            local p_canon
            p_canon=$(realpath -e "$p" 2>/dev/null) || continue
            [[ "$p_canon" == "$root_canon/"* ]] || continue
            projects+=("$p_canon")
        done < <(find "$root_canon" -maxdepth 1 -mindepth 1 -type d ! -name ".*" 2>/dev/null | sort)
    else
        # Remote projects: find directories with .git
        local find_args=("$root_canon")
        if [[ -n "$exclude_dir" ]]; then
            local exclude_canon
            exclude_canon=$(realpath -e "$exclude_dir" 2>/dev/null) || exclude_canon="$exclude_dir"
            find_args+=(-path "$exclude_canon" -prune -o)
        fi
        find_args+=(-type d -name ".git" -print)
        while IFS= read -r git_dir; do
            local repo_canon
            repo_canon=$(realpath -e "$(dirname "$git_dir")" 2>/dev/null) || continue
            [[ "$repo_canon" == "$root_canon/"* ]] || continue
            projects+=("$repo_canon")
        done < <(find "${find_args[@]}" 2>/dev/null)
    fi

    [[ ${#projects[@]} -eq 0 ]] && {
        echo -e "${YELLOW}No projects found in $root_dir${NC}" >&2
        return 1
    }

    # Show the list to stderr (so user sees it)
    {
        echo ""
        echo -e "${BLUE}$prompt${NC}"
        echo -e "${YELLOW}Found ${#projects[@]} project(s):${NC}\n"

        for i in "${!projects[@]}"; do
            local project_name=$(basename "${projects[i]}")
            local project_path="${projects[i]}"
            local git_info=""

            if [[ -d "${projects[i]}/.git" ]]; then
                local branch=$(git -C "${projects[i]}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
                local remotes=$(git -C "${projects[i]}" remote 2>/dev/null | tr '\n' ',' | sed 's/,$//')
                if [[ -n "$remotes" ]]; then
                    git_info="${GREEN}✓${NC} ($branch → ${remotes})"
                else
                    git_info="${YELLOW}✓${NC} ($branch, no remotes)"
                fi
            else
                git_info="${RED}✗${NC} (no git)"
            fi

            local display_path="${project_path#$PROJECT_ROOT/}"

            echo -e "  ${BLUE}$((i+1)))${NC} ${GREEN}$project_name${NC}"
            echo -e "      Location: $display_path"
            echo -e "      Git: $git_info"
            echo ""
        done
    } >&2

    # Get selection from stdin, fallback to /dev/tty if not a terminal
    while true; do
        if [[ -t 0 ]]; then
            read -rp "Select project (1-${#projects[@]}) or 'x' to cancel: " choice
        else
            read -rp "Select project (1-${#projects[@]}) or 'x' to cancel: " choice </dev/tty
        fi

        [[ "$choice" =~ ^[xX]$ ]] && {
            echo -e "${YELLOW}Cancelled.${NC}" >&2
            return 1
        }

        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Please enter a number (1-${#projects[@]}) or 'x' to cancel${NC}" >&2
            continue
        fi

        local idx=$((choice-1))

        if [[ $idx -lt 0 || $idx -ge ${#projects[@]} ]]; then
            echo -e "${RED}Invalid selection. Choose 1-${#projects[@]}.${NC}" >&2
            continue
        fi

        # Return ONLY the selected path (for command substitution)
        echo "${projects[$idx]}"
        return 0
    done
}

show_about() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         ABOUT REPO-CRAFTER           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo "repo-crafter v${SCRIPT_VERSION} - A safe, interactive shell script for managing Git repositories across multiple platforms."
    echo "Copyright (C) 2026 Dharrun Singh .M"
    echo ""
    echo "This program is free software: you can redistribute it and/or modify"
    echo "it under the terms of the GNU General Public License as published by"
    echo "the Free Software Foundation, either version 3 of the License, or"
    echo "(at your option) any later version."
    echo ""
    echo "This program is distributed WITHOUT ANY WARRANTY."
    echo ""
    echo "For the full license text, see: https://www.gnu.org/licenses/gpl-3.0.txt"
    echo "For support, contact: dharrunsingh@gmail.com"
    echo ""
    echo "For Troubleshooting visit my repo for Documentations"
    read -rp "Press Enter to return to menu..." || true
}

# ======================= EXECUTION HELPERS ==========================

# For DANGEROUS operations (always preview + confirm)
execute_dangerous() {
    local description="$1"
    shift

    # Filesystem-destructive commands may only touch paths under PROJECT_ROOT
    local cmd="${1:-}"
    if [[ "$cmd" == "rm" || "$cmd" == "mv" ]]; then
        local -a path_args=()
        local arg
        for arg in "${@:2}"; do
            [[ "$arg" == -* ]] && continue
            path_args+=("$arg")
        done
        if [[ ${#path_args[@]} -eq 0 ]]; then
            echo -e "${RED}❌ Refusing '$cmd' with no target.${NC}"
            return 1
        fi
        for arg in "${path_args[@]}"; do
            if ! _is_under_project_root "$arg"; then
                echo -e "${RED}❌ Refusing to $cmd outside $PROJECT_ROOT: $arg${NC}"
                return 1
            fi
        done
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}┌─────────────────────────────────────┐${NC}"
        echo -e "${YELLOW}│             DRY RUN MODE            │${NC}"
        echo -e "${YELLOW}│      (No changes will be made)      │${NC}"
        echo -e "${YELLOW}└─────────────────────────────────────┘${NC}"
        echo -e "${YELLOW}[DRY RUN]${NC} $description"
        echo -e "  $(printf '%q ' "$@")"
        return 0
    fi

    # Normal mode: Show preview → Ask → Execute
    echo -e "${YELLOW}[PREVIEW]${NC} $description"
    echo -e "  $(printf '%q ' "$@")"
    confirm_action "Execute command?" && "$@" || return 1
}

# For SAFE operations (only preview with --dry-run)
execute_safe() {
    local description="$1"
    shift

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} $description"
        echo -e "  $(printf '%q ' "$@")"
        return 0
    fi

    # Normal mode: Execute silently
    "$@"
}

# ======================= UX and navigation FUNCTIONS ====================================


# Create a standard confirmation function
confirm_action() {
    local message="$1"
    local default="${2:-n}"  # Default to "no" for dangerous actions

    echo -e "${YELLOW}⚠️  $message${NC}"
    if [[ "$default" == "y" ]]; then
        read -rp "Proceed? (Y/n): " -n 1 || { echo; return 1; }
        echo
        [[ ! $REPLY =~ ^[Nn]$ ]]
    else
        read -rp "Proceed? (y/N): " -n 1 || { echo; return 1; }
        echo
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}


# ======================= MAIN MENU & ENTRY POINT =============================

# Run a menu action in a subshell; a non-zero result returns to the menu.
# The explicit `set -e` inside keeps failures aborting the action at the point
# they happen, instead of being suppressed by a `||` context.
run_menu_action() {
    local rc=0
    set +e
    ( set -e; "$@" )
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        echo -e "\n${YELLOW}Returned to menu.${NC}"
        sleep 1
    fi
}

main_menu() {
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║     / REPO-CRAFTER v${SCRIPT_VERSION} \     ║${NC}"
        echo -e "${BLUE}║     | Generic Platform Edition |     ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
        echo -e "${GREEN}Copyright (C) 2026 Dharrun Singh .M under GNU GPLV3+${NC}"
        echo -e "${YELLOW}Select About for more details${NC}"
        echo -e "${RED}⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️o⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️⚡️${NC}"
        echo -e "${YELLOW}┌ Platforms: ${GREEN}${AVAILABLE_PLATFORMS[*]}${NC}"
        echo -e "${YELLOW}└ Root: ${GREEN}$PROJECT_ROOT/${NC}"

        echo -e "\n${BLUE}🛠  CREATE NEW PROJECT${NC}"
        echo -e "\n${BLUE}📦 PROJECT MANAGEMENT${NC}"
        echo "  1) 🆕 Create New Project"
        echo "  2) 👥 Convert single to Multi-server project"
        echo "  3) 🔗 Convert Local → Remote"
        echo "  4) 🔓 Convert Remote → Local"
        echo "  5) 🗑️  Manage/Delete Project"

        echo -e "\n${BLUE}🌐 REMOTE OPERATIONS${NC}"
        echo "  6) 📋 List Remote Repositories"
        echo "  7) ⚙️  Configure .gitignore"

        echo -e "\n${BLUE}⚙️  SYSTEM${NC}"
        echo "  8) 🧪 Test Configuration"
        echo "  9) ℹ️ About this script"
        echo " 10) 🧾 Project Manifest"
        echo "  0) 🚪 Exit"
        echo ""
        read -rp "Select (0-10): " choice

        case $choice in
            1) run_menu_action create_new_project_workflow ;;
            2) run_menu_action convert_single_to_multi_platform ;;
            3) run_menu_action convert_local_to_remote_workflow ;;
            4) run_menu_action convert_remote_to_local_workflow ;;
            5) run_menu_action manage_project_workflow ;;
            6) run_menu_action list_remote_repos_workflow ;;
            7) run_menu_action gitignore_maker_interactive ;;
            8) run_menu_action test_platform_config ;;
            9) run_menu_action show_about ;;
           10) run_menu_action manifest_workflow ;;
            0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid option.${NC}"; sleep 1 ;;
        esac
    done
}


# ======================= DRY-RUN AND PLATFORM-TESTING CONFIGURATION ==============================
DRY_RUN=false  # Set to true via --dry-run flag
DEBUG_MODE=false  # Set to true to see API calls with half-masked tokens

# Parse command line arguments (before any operations)
parse_args() {
    case "${1:-}" in
        --help|-h)
            echo "repo-crafter v${SCRIPT_VERSION} - Interactive Git Repository Manager"
            echo "Copyright (C) 2026 Dharrun Singh .M - GPL v3+"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "    --help, -h      Show this help message"
            echo "    --dry-run, -n   Preview operations without executing"
            echo "    --debug, -d     Show API calls with half-masked tokens"
            echo "    --test, -t      Run configuration tests and exit"
            echo "    --version       Show version and license info"
            echo ""
            echo "Without options, starts interactive menu."
            echo ""
            echo "For full documentation, visit:"
            echo "    https://github.com/DevKingofEarth/Repo-Crafter"
            echo ""
            echo "For support: dharrunsingh@gmail.com"
            exit 0
            ;;
        --version)
            echo "repo-crafter v${SCRIPT_VERSION} - Generic Platform Edition"
            echo "Copyright (C) 2026 Dharrun Singh .M"
            echo "License: GNU GPL v3+ (https://www.gnu.org/licenses/gpl-3.0.txt)"
            echo "This program comes with ABSOLUTELY NO WARRANTY."
            exit 0
            ;;
        --dry-run|-n)
            DRY_RUN=true
            echo -e "${YELLOW}=== DRY-RUN MODE (preview only) ===${NC}"
            ;;
        --debug|-d)
            DEBUG_MODE=true
            echo -e "${YELLOW}=== DEBUG MODE ENABLED (API calls will be shown with masked tokens) ===${NC}"
            ;;
        --test|-t)
            if ! load_platform_config; then exit 1; fi
            test_platform_config
            exit 0
            ;;
    esac
}
parse_args "$@"

# ======================= SCRIPT INITIALIZATION ===============================
main() {
    # 1. Check for essential tools
    local required_tools=(git curl jq ssh tr)
    local optional_tools=(yq)

    echo -n "Checking required tools... "

    for cmd in "${required_tools[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}✗ FAILED${NC}"
            echo -e "${RED}❌ Required tool '$cmd' is not installed.${NC}"
            echo -e "${YELLOW}Install with: sudo apt install $cmd (Debian/Ubuntu)${NC}"
            exit 1
        fi
    done

    echo -e "${GREEN}✓${NC}"

    # Check optional tools
    echo -n "Checking optional tools... "
    local missing_optional=()
    for cmd in "${optional_tools[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_optional+=("$cmd")
        fi
    done

    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Missing: ${missing_optional[*]}${NC}"
        echo -e "${YELLOW}Some features may not work without: yq (for YAML manifest)${NC}"
    else
        echo -e "${GREEN}✓${NC}"
    fi

    # 2. Load platform configuration (REPLACES old token checks)
    if ! load_platform_config; then
        echo -e "${RED}Failed to load platform configuration. Exiting.${NC}"
        exit 1
    fi

    # 3. Optional: Test configuration (skip if .no-auto-test exists)
    echo -e "${YELLOW}Run configuration test? (Recommended)${NC}"
    if confirm_action "Test platform configuration now?" "y" "Run test"; then
        test_platform_config
    fi

    # 4. Safety check for current directory
    if ! is_safe_directory "$(pwd)"; then
        echo -e "${RED}Please run from a safe directory (e.g., ~/Projects).${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Status:${NC}"   # lastly done, needed to be reviewed.
    for platform in "${AVAILABLE_PLATFORMS[@]}"; do
        token_var="${PLATFORM_TOKEN_VAR[$platform]}"
        if [[ -n "${!token_var:-}" ]]; then
            echo -e "  ${GREEN}●${NC} $platform (API: ✓)"
        else
            echo -e "  ${RED}○${NC} $platform (API: ✗)"
        fi
    done
    # 5. Start the interactive menu
    main_menu
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

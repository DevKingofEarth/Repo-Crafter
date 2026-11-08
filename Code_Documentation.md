```markdown
# **REPO-CRAFTER CODE DOCUMENTATION**

<!--
Code Documentation for repo-crafter
Copyright (C) 2026 Dharrun Singh .M
SPDX-License-Identifier: CC-BY-SA-4.0
This work is licensed under the Creative Commons Attribution-ShareAlike 4.0 International License.
To view a copy of this license, visit https://creativecommons.org/licenses/by-sa/4.0/.
-->

**Architecture**: Single-file bash script with external config
**Entry Point**: `main()` → `main_menu()` loop


---

## **1. HEADER & SAFETY FLAGS**

```bash
#!/usr/bin/env bash
set -euo pipefail
```

**Purpose**:
- `#!/usr/bin/env bash`: Portable shebang for bash execution
- `set -euo pipefail`: **Critical safety trio**
  - `-e`: Exit immediately on any command failure
  - `-u`: Exit on undefined variable (prevents silent errors)
  - `-o pipefail`: Pipe failures propagate (catches errors in pipelines)

**Debug Impact**: If script exits unexpectedly, check which of these flags triggered. Run with `bash -x repo-crafter.sh` for full trace.

---

## **2. CONFIGURATION & GLOBALS**

```bash
FORBIDDEN_DIRS=("/etc" "/etc/nixos" "/root" "/bin" "/sbin" "/usr")
LOCAL_ROOT="$HOME/Projects/Local_Projects"
REMOTE_ROOT="$HOME/Projects/Remote_Projects"
```

**Key Variables**:
- `FORBIDDEN_DIRS`: Hardcoded blacklist of system directories. **Never modify this unless you understand the risk**. The `is_safe_directory()` function checks against this. You can also add other directories which you want to protect.
- `LOCAL_ROOT`: Where unbound projects live. **Changing this requires manually moving existing projects**.
- `REMOTE_ROOT`: Where bound projects live. **Subdirectory structure is generated from `work_dir` values in `platforms.conf`**.

**Color Constants**: ANSI color codes used throughout for UX. If colors appear broken, verify terminal supports ANSI escape sequences.

---

## **3. PLATFORM CONFIGURATION INFRASTRUCTURE**

```bash
declare -A PLATFORM_ENABLED
declare -A PLATFORM_API_BASE
declare -A PLATFORM_SSH_HOST
declare -A PLATFORM_REPO_DOMAIN
declare -A PLATFORM_TOKEN_VAR
declare -A PLATFORM_AUTH_HEADER
declare -A PLATFORM_AUTH_HEADER_NAME
declare -A PLATFORM_AUTH_QUERY_PARAM
declare -A PLATFORM_ACCEPT_HEADER
declare -A PLATFORM_REPO_DELETE_ENDPOINT
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
declare -A PLATFORM_OWNER_NOT_FOUND_PATTERNS
declare -A PLATFORM_SSH_URL_FIELDS
declare -A PLATFORM_VISIBILITY_MAP
AVAILABLE_PLATFORMS=()
```

**Architecture**: Central design pattern—every platform setting is an associative array keyed by platform name (e.g., "github").

**Arrays**
- `PLATFORM_ENABLED`: Boolean flag from config
- `PLATFORM_API_BASE`: Root API URL (e.g., `https://api.github.com`)
- `PLATFORM_SSH_HOST`: SSH endpoint (e.g., `github.com`)
- `PLATFORM_TOKEN_VAR`: Name of env var holding token
- `_ENDPOINT`: API paths with placeholders `{owner}`, `{repo}`
- `_METHOD`: HTTP verb (GET/POST)
- `_SUCCESS_KEY`: JSON key that proves API call succeeded
- `PLATFORM_WORK_DIR`: Subdirectory name under REMOTE_ROOT
- `PLATFORM_PAYLOAD_TEMPLATE`: JSON body for repo creation (with placeholders)
- `PLATFORM_SSH_URL_TEMPLATE`: SSH URL format
- `PLATFORM_DISPLAY_FORMAT`: How to show repos in list view
- `PLATFORM_AUTH_HEADER`: Authorization header format. Customizable authorization header format (e.g., `Bearer {token}`, `{token}`)
- `PLATFORM_AUTH_HEADER_NAME` - Custom authorization header names (like PRIVATE-TOKEN for GitLab)
- `PLATFORM_AUTH_QUERY_PARAM` - Support for query parameter authentication
- `PLATFORM_ACCEPT_HEADER`: HTTP `Accept` header for API requests (e.g., `application/vnd.github+json` for GitHub)
- `PLATFORM_REPO_DELETE_ENDPOINT`: API endpoint pattern for repository deletion with `{owner}` and `{repo}` placeholders
- `PLATFORM_OWNER_NOT_FOUND_PATTERNS`: Comma-separated error message fragments to detect when repo owner doesn't exist
- `PLATFORM_SSH_URL_FIELDS`: Comma-separated JSON field names to try when extracting SSH URL from API response
- `PLATFORM_VISIBILITY_MAP`: JSON mapping between script's visibility terms and platform-specific terms

**Adding a Platform**: Add a new `[section]` to `platforms.conf`—the script auto-detects it without code changes.

**Required Keys**: GitHub and GitLab now require `accept_header` and `repo_delete_endpoint` in config for proper API operation.

---

## **4. PLATFORM LOADING FUNCTION**

`load_platform_config()`

**Flow**:
1. **Check config file exists** at `$CONFIG_DIR/platforms.conf` (defaults to `~/.config/repo-crafter/platforms.conf`)
2. **Parse INI format** manually (no external dependency)
   - Detects `[section]` headers
   - Parses `key = value` pairs
   - Skips comments (`#`)
3. **Populates associative arrays** dynamically using `declare -g`
4. **Builds `AVAILABLE_PLATFORMS`** array from enabled platforms that have both API base and token variable configured

**Critical Logic**:
- Uses `declare -gA "$array_name"` to create global associative arrays at runtime
- Config parsing uses regex patterns to match `key = value` syntax
- Filters platforms where `enabled=true` AND `api_base` is set AND `token_var` is set
- `work_dir` must be a single directory component (no `/`, not `.` or `..`); an invalid value aborts config loading. If omitted, it defaults to `repo_domain`, then to the platform name

**Extended Support**: Config parsing now automatically handles `auth_header_name`, `auth_query_param`, `accept_header`, and `repo_delete_endpoint` keys when present in platform configuration.

**Error Handling**:
- Config not found → exits with example config snippet
- Syntax errors → silently skipped (robust but may hide typos)
- No platforms enabled → returns error, prevents menu crash

---

## **5. PLATFORM SELECTION FUNCTION**

`select_platforms(prompt, allow_multiple)`

**Purpose**: Interactive menu for choosing platforms. Returns newline-separated list.

**Parameters**:
- `prompt`: String displayed above platform list
- `allow_multiple`: Boolean. If true, shows `a` (All) and `m` (Multiple) options

**Flow**:
1. Prints menu directly to stderr with `>&2` (bypasses stdout capture)
2. Reads input from stdin, with fallback to `/dev/tty` when stdin is not a terminal (handles command substitution)
3. Parses input:
   - `a` → All platforms
   - `m` → Prompts for comma-separated numbers
   - Number(s) → Single or multiple platforms
   - Direct comma-list (e.g., `1,3`) → Multiple platforms
4. Validates bounds against platform count
5. Returns list via `printf` for command substitution

**Key Design**: Returns list via stdout: `platforms=$(select_platforms "Choose:" "true")`

- **Numeric verification**: Uses regex `[[ ! "$idx" =~ ^[0-9]+$ ]]` to validate input
- **Bounds checking**: Ensures `valid_idx >= 0 && valid_idx < ${#AVAILABLE_PLATFORMS[@]}`
- **Error resilience**: Continues processing valid indices even if some are invalid

---

## **6. DIAGNOSTIC TEST FUNCTION**

`test_platform_config()`

**Purpose**: Comprehensive diagnostic tool verifying setup.

**Flow**:
1. **Skip option**: Prompts to run tests (can bypass)
2. **Show loaded platforms**: Lists `AVAILABLE_PLATFORMS`
3. **Token check**: Iterates platforms, uses indirect expansion `${!token_var}` to verify environment variables
4. **SSH check**: Calls `check_ssh_auth()` for each platform
5. **Interactive test**: Runs `select_platforms()` to verify menu functionality
6. **Duplicate check**: Calls `warn_duplicate_remote_connections()`

**Auto-Skip**: Creates `~/.config/repo-crafter/.no-auto-test` if user opts out of future auto-tests.

---

## **7. CORE VALIDATION FUNCTIONS**

### **7.1 `check_local_exists(path)`**
- **Implementation**: `git -C "$dir" rev-parse --git-dir >/dev/null 2>&1` (also true for worktrees and submodules)
- **Purpose**: Check if directory is a Git repository
- **Used by**: Bind workflow to skip fetch/diff checks for a folder that is not a repo yet; the folder is initialized during binding

### **7.2 `check_ssh_auth(host, platform_name)`**
 **7.2 `check_ssh_auth(host, platform_name)`**
- **Tests SSH** with `ssh -T -o ConnectTimeout=10 -o BatchMode=yes git@host`
- **Enhanced timeout handling**: Uses 10-second connection timeout with batch mode (no password prompts)
- **Platform-specific key support**: Checks `~/.ssh/config` for custom IdentityFile entries
- **Success detection**: Accepts both exit code 0 and 1 as successful authentication
  - GitHub returns exit code 1 with "no shell access" message (not an error)
  - GitLab returns exit code 0 with "Welcome" message
- **Failure handling**: Returns detailed debugging information including:
  - Manual test command to run
  - SSH config suggestions
  - Key permission reminders
  - Captured output snippet (up to 100 characters)
- **Returns**: 0 if authenticated, 1 if failed
- **Critical**: Called during `--test` and before cloning operations
- **Error resilience**: If SSH test fails, continues with warning (doesn't block operations)

### **7.3 `is_safe_directory(target_dir)`**
- **Blacklists** `FORBIDDEN_DIRS`
- **Root check**: Explicitly blocks `/` (root directory)
- **Pattern matching**: Checks if path starts with forbidden prefixes
- **Exit on fail**: Called in `main()` before menu starts

### **7.4 `warn_duplicate_repo_name(project_name, parent_dir)`**
- **Scans** predefined search dirs (`~/Projects`, `~/Work`, etc.)
- **Finds** all `.git` directories
- **Compares** basename against `project_name`
- **Excludes** matches inside `target parent_dir` (allows same name in target location)
- **Prompts** user to continue if duplicates found

### **7.5 `warn_similar_remote_repos(platform, new_name, user_name)`**
- **Fetches** user's repo list via API
- **Uses jq** to search for names containing `new_name` (case-insensitive)
- **Shows** up to 5 matches
- **Returns**: 1 if similar found (triggers warning), 0 if clear

### **7.6 `warn_duplicate_remote_connections()`**
- **Scans** both `LOCAL_ROOT` and `REMOTE_ROOT`
- **Builds** associative array mapping remote URL → list of local paths
- **Detects** when single remote is bound to multiple locals
- **Warns** about confusion risk and potential push/pull conflicts

### **7.7 `validate_project_name(project_name, purpose)`**
**Purpose**: Comprehensive security validation to prevent command injection and path traversal attacks.
**Parameters**:
- `project_name`: The project name to validate
- `purpose`: Description of what the name is for (displayed in error messages)
**Security Checks**:
1. **Empty check**: Rejects empty names
2. **Dangerous character detection**: Blocks characters that could enable command injection:
   - `; & | ' " $ ` \ ( ) { } [ ] < >`
3. **Path traversal prevention**: Blocks `../`, `..`, `/`, and `.\/` patterns
4. **Whitelist validation**: Ensures name only contains `a-z, A-Z, 0-9, -, _`
5. **Length validation**: Maximum 100 characters (prevents buffer overflow issues)
**Return values**:
- `0`: Validation passed
- `1`: Validation failed (error message displayed to stderr)
**Used by**: All functions that accept user input for project names to ensure safe shell operations.
**Example**:
```bash
if ! validate_project_name "$user_input" "project name"; then
    echo "Invalid project name"
    return 1
fi

```
### **7.8 detect_current_branch()**
Purpose: Safely detect current Git branch with fallback handling.
Implementation:
current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || 
                 git rev-parse --short HEAD 2>/dev/null || 
                 echo "main")
Used by: Branch synchronization workflows.

### **7.9 remove_existing_remotes()**
Purpose: Remove all Git remotes from current repository.
Usage: Used in _create_local_only() to ensure unbound projects have no remotes.

### **7.10 check_remote_exists(platform, owner, repo)**
Purpose: Check if remote repository exists before attempting operations.
Return values: 
- 0: Repository exists
- 1: Repository does not exist

### **7.11 verify_project_state(project_dir)**
Purpose: Verify project state and configuration consistency.
Checks:
- Remote state manifest existence
- Branch consistency
- Remote URL validation

---

### **8. API INTERACTION FUNCTIONS**

#### **8.1 `platform_api_call(platform, endpoint, method, data)`**
Core API abstraction with error resilience.

**Implementation details:**
- Authentication template resolution: `${PLATFORM_AUTH_HEADER[$platform]:-Bearer {token}}`
- Token substitution: `auth_header="${auth_template//\{token\}/$token_value}"`
- Retry logic: `max_retries=3` with exponential backoff starting at `retry_delay=2`
- Rate limit handling (429): automatic retries with increasing delays
- HTTP status handling:
  * 401: "Authentication failed" with token variable name (uncomment for debugging)
  * 403: "Permission denied" with platform context
  * 404: "Resource not found" with platform context
  * 429: Automatic retry handling with delay progression (2s, 4s, 8s)
  * Other failures: truncated error message (100 chars max) to prevent terminal spam
- DRY_RUN mode: outputs API call details without execution when `--dry-run` is active
**Debug lines**
```bash
#     local safe_token_preview="${token_value:0:4}...${token_value: -4}"
#     echo -e "${YELLOW}[DEBUG] Token preview (safe): $safe_token_preview${NC}" >&2
#     echo -e "${YELLOW}[DEBUG] Final auth header: $auth_header_name: ${auth_header_value:0:15}...${NC}" >&2
```

**Command structure**
```bash
curl -sS -w "\n%{http_code}" -X "$method" \
-H "Accept: $accept_header" \
-H "Content-Type: application/json" \
-H "Authorization: $auth_header" \
--max-time 30 \
"${api_base}${endpoint}"
```

- **Accept header**: Resolved from `PLATFORM_ACCEPT_HEADER[$platform]` (defaults to `application/json`). GitHub requires `application/vnd.github+json` for proper response format.
- **Custom header name support**: Resolves `PLATFORM_AUTH_HEADER_NAME` for platforms like GitLab that use `PRIVATE-TOKEN` instead of `Authorization`
- **Query parameter authentication**: Falls back to `PLATFORM_AUTH_QUERY_PARAM` if configured
- **Enhanced error handling**: 
  - Better timeout management (30-second max-time)
  - Batch mode for non-interactive operation
  - More detailed error output (100-char truncation)

**Return values:**
- Success: raw JSON response body
- Failure: returns 1 with error output to stderr

#### **8.2 `create_remote_repo(platform, repo_name, visibility, user_name)`**
Repository creation with fallback mechanisms.

**Key changes:**
- Visibility mapping: `PLATFORM_VISIBILITY_MAP` JSON parsing via jq
- URL extraction priority:
  1. Configured fields: `IFS=',' read -ra field_array <<< "$url_fields"`
  2. Standard fields: `.ssh_url // .ssh_url_to_repo // .clone_url`
  3. Template generation: `PLATFORM_SSH_URL_TEMPLATE` with host/owner/repo substitution
- Error pattern detection: `PLATFORM_OWNER_NOT_FOUND_PATTERNS` comma-separated matching
- Cleanup on partial failure: `_cleanup_failed_creation()` calls DELETE using `PLATFORM_REPO_DELETE_ENDPOINT` template
- Default branch detection: `git config --get init.defaultBranch` fallback to "main"

**Edge case handling:**
- Repository URL extraction failure triggers cleanup
- Permission errors show platform-specific token requirements
- Owner not found errors trigger fallback to authenticated user

#### **8.3 `sync_with_remote(platform, remote_url, current_branch)`**
Branch synchronization control flow.

**Branch detection flow:**
```bash
current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
[[ -z "$current_branch" ]] && { echo "Detached HEAD"; return 1; }
```

**Branch inventory:**
- Local branches from `refs/heads/*`
- Remote branches from `refs/remotes/<platform>/*` via `%(refname:lstrip=3)`
- Classified as matched, local-only, remote-only
- A different remote default is reported as a notice, never used to rename

**Synchronization states (current branch only):**
- **Missing on remote**: offer `git push -u "$platform" "$current_branch"`
- **Identical branches** (`ahead=0` and `behind=0`): Offer push confirmation
- **Local ahead only** (`behind=0` and `ahead>0`): Simple push workflow
- **Remote ahead** (`behind>0`): Four options:
  1. Rebase: `git rebase "$platform/$remote_branch" --quiet`
  2. Merge: `git merge "$platform/$remote_branch" --no-edit --quiet`
  3. Skip: Push anyway, creating divergent branches
  4. Cancel: restore the stash and return non-zero
- **Other local-only branches**: optional bulk push, excluding the current branch
- **Remote-only branches**: listed with a `git switch -c` suggestion; never merged automatically

**Stash management:**
- Pre-synchronization: `git stash push -m "repo-crafter: pre-sync" --quiet`
- Post-synchronization: `git stash pop --quiet`
- Cancellation recovery: explicit stash pop on exit paths

#### **8.4 `_cleanup_failed_creation(platform, project_name, remote_url)`**
New atomic operation safeguard.

**Cleanup sequence:**
```bash
# Remote cleanup
owner=$(echo "$remote_url" | awk -F'[@:/]' '{print $(NF-1)}')
platform_api_call "$platform" "${PLATFORM_REPO_DELETE_ENDPOINT[$platform]//\{owner\}/$owner//\{repo\}/$project_name}" "DELETE" >/dev/null 2>&1

# Local cleanup
dir="$REMOTE_ROOT/$PLATFORM_WORK_DIR[$platform]/$project_name"
[[ -d "$dir" ]] && rm -rf "$dir" 2>/dev/null
```

**Safety measures:**
- Idempotent operations (safe to call multiple times)
- No partial state left on failure
- Works across all supported platforms
- Handles malformed URLs gracefully

**Note:** Used in `_create_with_new_remote` after any failure point where repository creation succeeded but later steps failed.

---

### **9. WORKFLOW FUNCTIONS**

#### **9.1 `convert_local_to_remote_workflow()`**
Local project binding control flow with divergence handling.

**Critical path flow:**
```bash
source_dir=$(_select_project_from_dir "$LOCAL_ROOT" "Local projects available to bind:")
bind_choice determines execution path:
  1) Create NEW repositories
  2) Connect to EXISTING repository
```

**Option 1 (NEW repositories):**
- Platform selection via `select_platforms "true"`
- Destination path calculation:
  ```bash
  if [[ ${#platform_array[@]} -eq 1 ]]; then
    dest_dir="$REMOTE_ROOT/$platform_work_dir/$project_name"
  else
    dest_dir="$REMOTE_ROOT/Multi-server/$project_name"
  ```
- Repository creation loop: `create_remote_repo "$platform" "$project_name" "$visibility" "$user_name"`
- Single-platform synchronization: `sync_with_remote` offered after the loop (multi-platform deferred)

**Option 2 (EXISTING repository):**
- URL parsing: `parse_git_url "$first_url"`
- Platform detection:
  ```bash
  for p in "${AVAILABLE_PLATFORMS[@]}"; do
    if [[ "$host" == "${PLATFORM_REPO_DOMAIN[$p]}" ]] ||
       [[ "$host" == "${PLATFORM_SSH_HOST[$p]}" ]]; then
  ```
- Directory cloning: `git clone "$first_url" "$dest_dir"`
- File merging: `cp -r "$source_dir/." .`
- Synchronization: `sync_with_remote origin "$first_url"` offered after binding

**Repository status check (before binding):**
1. Skips the checks when the folder is not a git repository yet (it is initialized during binding)
2. Reports "No remotes configured" when the repo has none
3. Fetches and compares ahead/behind only when the current branch has an upstream; otherwise reports that remote state was not compared
4. Warns about uncommitted changes

**Edge case handling:**
- Detached HEAD state detection in `current_branch` logic
- Uncommitted changes preservation during merge operations
- Multi-platform URL parsing with fallback remote naming

#### **9.2 `sync_with_remote(platform, remote_url, current_branch)`**
Branch synchronization state machine.

**State detection logic:**
```bash
ahead=$(git rev-list --count "$platform/$remote_branch..$current_branch" 2>/dev/null || echo 0)
behind=$(git rev-list --count "$current_branch..$platform/$remote_branch" 2>/dev/null || echo 0)
```

**Decision matrix:**
| Local Ahead | Remote Behind | Action |
|-------------|--------------|--------|
| 0 | 0 | Push option |
| >0 | 0 | Simple push |
| Any | >0 | Integration options (rebase/merge/push-anyway/cancel) |

**Stash management protocol:**
```bash
# Pre-synchronization
if ! git diff --quiet || ! git diff --cached --quiet; then
  git stash push -m "repo-crafter: pre-sync" --quiet
fi

# Post-synchronization
if [[ "$stashed" == "true" ]]; then
  git stash pop --quiet
fi

# Cancellation recovery
[[ "$stashed" == "true" ]] && git stash pop --quiet >/dev/null
```

**Branch name mismatches:**
- Remote default detection: `git ls-remote --symref "$remote_url" HEAD`, parsed from the `ref:` line
- A different remote default is only reported; branches are never renamed
- Detached HEAD is refused instead of guessing a branch

**Wiring:**
- Called after a successful bind: connect-existing (`origin`) and single-platform create
- Runs in a subshell; cancel or skip returns to the menu

#### **9.3 `manage_project_workflow()`**
Destructive operation safety protocol.

**Deletion workflow:**
```bash
case "$choice" in
  3) _delete_both ;;  # Most destructive option
esac
```

**Two-factor confirmation system:**
```bash
# Project name verification
[[ "$confirm_name" != "$project_name" ]] && return 1

# Risk acknowledgment
[[ "$confirm_delete" != "DELETE" ]] && return 1
```

**Atomic deletion sequence:**
1. Remote deletion: `platform_api_call "$platform" "/repos/$user_name/$project_name" "DELETE"`
2. Local deletion: `rm -rf "$source_dir"`
3. Failure recovery: partial cleanup on API failure

#### **9.4 `_clone_existing_remote(mode, urls)`**
Universal cloning engine with path determination.
**"standalone"**: Single URL, interactive prompt

**URL normalization flow:**
```bash
parse_git_url() {
  # Protocol stripping
  url="${url#*://}"
  url="${url#*@}"
  
  # SSH format handling
  url="${url#*:}"
  
  # Path extraction
  url="${url#*/}"
  
  # Sanitization
  url="${url%.git}"
  url="${url#/}"
  url="${url%/}"
}
```

**Return value protocol**
```bash
echo "$dest_dir"  # ONLY directory path via stdout
# All status messages go to stderr via >&2
```

#### **9.5 `create_multi_platform_manifest(dir, name, urls_ref)`**
State persistence mechanism for multi-platform projects.

**YAML generation flow:**
```bash
# Machine-readable section
yq -n --arg name "$name" ... '{
  metadata: { ... },
  local_state: { ... },
  platforms: { ... }
}' >> "$dir/REMOTE_STATE.yml"

# Platform-specific data injection
yq -i --arg platform "$platform" ... \
'.platforms[$platform] = { ... }' "$dir/REMOTE_STATE.yml"
```

**Graceful degradation:**
```bash
if ! command -v yq &>/dev/null; then
  # Fallback to simple manifest format
  cat > "$dir/REMOTE_STATE.yml" << EOF
# Simple manifest format
platforms:
  $platform:
    remote_name: "$platform"
    ssh_url: "${urls_ref[$platform]}"
EOF
fi
```

**Critical data points:**
- Branch mapping: `branch_mapping: { ($branch): $commit }`
- API configuration snapshot for future operations
- Last sync status and timestamp for state tracking

**Note**: Manifest is only created for multi-platform projects (2+ platforms). Single-platform projects do not need a manifest as the git remote tracks the connection.


### **9.6 `convert_remote_to_local_workflow()`**

**Unbinds remote project to local-only**.

**Flow**:
1. Select project from `REMOTE_ROOT`
2. Show warning about removing ALL remotes
3. **Status check**: Warns about uncommitted changes
4. **Remove remotes**: Iterates `git remote` output, removes each
5. **Delete manifest**: Removes `REMOTE_STATE.yml` if present
6. **Move directory**: Executes `mv` to `LOCAL_ROOT`
7. **Confirmation**: Shows success message


### **9.7 `list_remote_repos_workflow()`**

**Lists repositories across selected platforms**.

**Features**:
- Multi-platform selection
- Per-platform error handling
- Platform count summary


### **9.8 `manage_project_workflow()`**

**Deletion sub-menu with three options**:
1. Delete local copy (keeps remote)
2. Unbind from remote (keeps local, moves to `Local_Projects/`)
3. Delete BOTH local and remote (irreversible)
4. Cancel

**Option 2 reuse**: Calls `convert_remote_to_local_workflow()` directly.

###  **9.9 `delete_remote_repo(platform, owner, repo)`**
**Purpose**: Delete a remote repository using platform-specific API endpoints.
- **Dynamic endpoint resolution**: Uses `PLATFORM_REPO_DELETE_ENDPOINT` configuration with `{owner}` and `{repo}` placeholders
- **Template substitution**: Replaces `{owner}` and `{repo}` placeholders with actual values
- **Platform agnostic**: Works with any platform configured in `platforms.conf`
- **Silent operation**: Suppresses API response output, only reports status
- **User feedback**: Displays "Remote cleanup attempted" message regardless of result
**Example**:
```
delete_remote_repo "github" "owner" "repository-name"
```
**"binding"**: Multiple URLs provided by caller

**Destination logic:**
```bash
if [[ "$mode" == "binding" && ${#urls[@]} -gt 1 ]]; then
  dest_dir="$REMOTE_ROOT/Multi-server/$repo_name"  # Multi-platform path
else
  dest_dir="$REMOTE_ROOT/${PLATFORM_WORK_DIR[$platform]}/$repo_name"  # Single platform path
fi
```

### **9.10 `_delete_local_copy()`**

**Deletes local files only; bound remotes are never touched**.

**Flow**:
1. Select a project from `PROJECT_ROOT` (local-only and bound projects both listed)
2. Warn based on state:
   - no remotes → this is the only copy, deletion is permanent
   - has remotes → remotes stay, project can be re-cloned, `REMOTE_STATE.yml` goes with the folder
3. Confirm deletion
4. `rm -rf` with `execute_dangerous` (skipped in dry-run)


### **9.11 `_delete_both()`**

**Most dangerous function—permanent deletion**.

- Two-factor confirmation for deletion 
**Safety protocol**
```bash
read -rp "Project name: " confirm_name
[[ "$confirm_name" != "$project_name" ]] && return 1
read -rp "Type 'DELETE': " confirm_delete
[[ "$confirm_delete" != "DELETE" ]] && return 1
```

**Delete sequence**:
1. **Selection**: lists `REMOTE_ROOT` projects, excluding `Multi-server` (multi-platform projects must be removed manually for now)
2. **API deletion**: `DELETE` request for every remote, each on its platform (detected from the remote URL)
3. **Local deletion**: `rm -rf` (only if all API deletions succeeded)

Note: This function relies on _cleanup_failed_creation() for atomic operations during repository creation failures.

### **9.12 `convert_single_to_multi_platform()`**
**Purpose**: Convert existing single-platform projects to multi-platform configuration.
**Workflow Steps**:
1. **Project Discovery**: Scans `REMOTE_ROOT/{platform}/` directories for Git repositories
2. **Interactive Selection**: Uses `_select_project_from_list()` for user choice
3. **Platform Detection**: Identifies current platform from directory structure
4. **URL Collection**: Prompts user for additional repository URLs
5. **Directory Migration**: Moves project to `REMOTE_ROOT/Multi-server/`
6. **Remote Reconfiguration**: 
   - Renames "origin" remote to platform name (if applicable)
   - Adds new remotes for additional URLs
   - Platform detection for remote naming
7. **Manifest Generation**: Calls `create_multi_platform_manifest()` with "convert_single_to_multi" action type
**Directory Structure Transformation**:
Before: REMOTE_ROOT/github.com/my-project/
After:  REMOTE_ROOT/Multi-server/my-project/
**Remote Configuration**:
- Original remote renamed to platform name (e.g., "github")
- Additional URLs added as separate remotes
- Remote names derived from platform detection
**Return Values**: None (void function with early returns on cancellation)
**Used by**: Main menu option 4 (Convert Single → Multi Platform)
User_Manual.md - Add New Workflow Description:
Add to workflow descriptions section:

---

## **10. GITIGNORE WORKFLOW**
### **10.1 `gitignore_maker(project_dir, mode)`**
Direct gitignore management with multiple pattern sources.

**Implementation details:**
- **Directory validation**: Checks for valid project directory and existing Git repository before proceeding
  ```bash
  [[ ! -d "$project_dir" ]] && { echo -e "${RED}❌ Project directory does not exist..."; return 1; }
  [[ ! -d "$project_dir/.git" ]] && { echo -e "${RED}❌ Not a Git repository..."; return 1; }
  ```

- **DRY_RUN integration**: Shows exact workflow simulation without filesystem changes
  ```bash
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN] Gitignore workflow for: $project_dir${NC}"
    # Shows all potential actions without execution
    return 0
  fi
  ```

- **Existing file handling**: Four options when .gitignore already exists:
  1. `Review and edit existing` - Opens file in nano editor
  2. `Backup existing and create new` - Creates timestamped backup before overwriting
  3. `Append to existing file` - Adds new patterns to bottom of file
  4. `Cancel` - Aborts operation

- **Pattern sources**: Three selection modes:
  1. `Generic patterns only` - OS/editor/build artifacts with explicit comments
  2. `Fetch from GitHub templates` - Queries GitHub API for official templates
  3. `Manual entry only` - User provides all patterns interactively

- **GitHub template integration**:
  ```bash
  templates=$(curl -s https://api.github.com/repos/github/gitignore/contents | 
             jq -r '.[] | select(.type=="file") | .name' | 
             sed 's/\.gitignore$//')
  ```
  - Shows first 20 templates with numbering
  - Allows space-separated selection (e.g., "1 3 5")
  - Fetches templates directly from GitHub repository
  - Handles curl/jq absence gracefully

- **Custom pattern entry**:
  ```bash
  while true; do
    read -rp "Pattern: " pattern
    [[ -z "$pattern" ]] && break
    echo "$pattern" >> "$ignore_file"
  done
  ```

- **Mode selection**:
  1. `Commit to repository` (default) - Stages and commits .gitignore
  2. `Keep local only` - Moves patterns to `.git/info/exclude` (never committed/pushed)

- **Template file generation**: Creates `.gitignore.template` in commit mode only, with:
  - Reference patterns for common categories
  - Usage instructions and best practices
  - Security notes about sensitive files
  - Clear separation of OS/IDE/build/environment patterns

**Return values:**
- `0`: Successful operation
- `1`: Cancelled or error occurred
- `"exclude"`: Local-only mode selected (caller must handle specially)
- `"normal"`: Patterns committed to repository (default)

**Critical dependencies:**
- Requires `curl` and `jq` for GitHub template fetching (graceful degradation otherwise)
- Uses `nano` editor for file review (fails if unavailable)
- Depends on Git repository structure for local-only mode

### **10.2 `gitignore_maker_interactive()`**

**Standalone gitignore entry point** (menu option 6).

**Flow**:
1. Prompt for project directory
2. Expand `~` to `$HOME`
3. Validate directory exists
4. Call `gitignore_maker` in "standalone" mode

---

## **11. UTILITY HELPERS**

### **11.1 `get_owner_from_ssh_url(ssh_url)`**

**NEW: Universal SSH/HTTPS URL parser**.

**Handles**:
- SSH: `git@github.com:owner/repo.git` → extracts `owner`
- HTTPS: `https://github.com/owner/repo.git` → extracts `owner`
- No `.git` suffix: `git@github.com:owner/repo` → extracts `owner`

**Returns**: Owner string or exit code 1 on failure.


### **11.2 `handle_existing_remote(platform, remote_url)`**

**NEW: Conflict resolution for existing remotes**.

**Logic**:
- Check if remote named `$platform` already exists
- If exists, show current vs new URL
- Prompt to update or keep existing
- **Returns**: `0` to proceed, `1` to skip

**Prevents**: Accidental remote overwriting.


### **11.3 `parse_git_url(url)`**

**NEW: Universal Git URL parser for path extraction**.

**Process**:
1. Remove protocol prefixes (`ssh://`, `https://`, etc.)
2. Remove userinfo (`user@`, `user:token@`)
3. Handle SSH format (`git@host:path`)
4. Extract path after host
5. Remove `.git` suffix
6. Return `owner/repo` path

**Used by**: Binding workflows to validate and parse user-provided URLs.


### **11.x `detect_platform_from_url(url)`**

**NEW: Automatic platform detection from git URL.**

**Implementation:**
```bash
detect_platform_from_url() {
  local url="$1"
  local host=$(extract_host_from_url "$url")

  for platform in "${AVAILABLE_PLATFORMS[@]}"; do
    if [[ "$host" == "${PLATFORM_REPO_DOMAIN[$platform]}" ]] ||
       [[ "$host" == "${PLATFORM_SSH_HOST[$platform]}" ]]; then
      echo "$platform"
      return 0
    fi
  done
  return 1
}
```

**Used by**: URL parsing in binding workflows to automatically identify platform without user input.

---

### **11.x `extract_host_from_url(url)`**

**NEW: Extract hostname from any git URL format.**

**Handles**:
- SSH: `git@github.com:owner/repo.git` → `github.com`
- HTTPS: `https://github.com/owner/repo` → `github.com`
- SSH with protocol: `ssh://git@gitlab.com/repo` → `gitlab.com`

**Returns**: Hostname string or exit code 1 on parse failure.

**Used by**: `detect_platform_from_url()` and other URL parsing functions.


### **11.4 `preview_and_abort_if_dry(description, ...)`**

**DRY-RUN safety guard**
 Global flag for dry-run mode. When `true`, shows planned actions without executing
**Behavior**:
- If `DRY_RUN=true`:  Shows accumulated planned actions list at completion, then exits
- If `DRY_RUN=false`: Returns `1` (immediately returns)

**Consistent exit**: Always exits after showing planned actions in DRY_RUN mode

**Action tracking**: Functions add planned actions to `DRY_RUN_ACTIONS` array:

```bash
DRY_RUN_ACTIONS+=("Create directory: $dir")
DRY_RUN_ACTIONS+=("API call: $platform $endpoint")
```
**Implementation pattern**
```bash
# At function start
if [[ "$DRY_RUN" == "true" ]]; then
  DRY_RUN_ACTIONS+=("Move project: $src → $dest")
  return 0  # Skip actual execution
fi

# At workflow completion
preview_and_abort_if_dry  # Shows all accumulated actions and exits
````

### **11.5 `_prompt_project_name()`**

**Validated project name input**.

**Loop**:
1. Prompt for name
2. Validate regex `^[a-zA-Z0-9_-]+$`
3. On failure, show error and retry
4. On success, echo name and return

**Ensures**: Safe directory names across all platforms.


### **11.6 `_prompt_visibility()`**

**Interactive visibility selection**.

**Returns**: `"private"` or `"public"` string.


### **11.7 `_select_project_from_dir(root_dir, prompt)`**

**Enhanced project selector with rich display**.

**Features**:
- **Dual-mode scanning**: 
  - `LOCAL_ROOT`: Flat structure (maxdepth 1)
  - `REMOTE_ROOT`: Finds `.git` directories recursively
- **Rich display**: Shows project name, location, size, git branch, remote count
- **Color coding**: 
  - `✓`: Git repository
  - `✗`: No git
  - Branch and remote info
- **Bounds checking**: Validates numeric input, prevents index errors
- **TTY isolation**: Displays directly to terminal, returns only path via stdout

**UX**: Shows formatted list, prompts for selection or `x` to cancel.

### **11.8 `create_multi_platform_manifest(dir, name, urls_ref, action_type)`**

**NEW: Generate machine-readable project state manifest**.

**Purpose**: Tracks multi-platform project state for verification and sync operations.

**Output**: `REMOTE_STATE.yml` with two sections:

**Human-Readable Section**:
- `project_name`, `description`, `created`, `maintainer`
- `last_script_action`, `last_action_timestamp`
- Commented platform URL quick-reference

**Machine-Readable Section**:
- `platforms.{platform}.remote_name`
- `platforms.{platform}.ssh_url`
- `platforms.{platform}.api_config_snapshot`
- `platforms.{platform}.branch_mapping`
- `platforms.{platform}.last_sync_status`
- `local_state.primary_branch`, `local_state.head_commit`

**Usage**: Enables future `verify_project_state()` and sync operations.


### **11.9 `confirm_action(message, default)`**

**Standardized confirmation prompt**.

**Parameters**:
- `message`: Warning/Question text
- `default`: `"y"` or `"n"` (default to "n" for dangerous actions)

**Returns**: Boolean based on user input.


### **11.10 `execute_dangerous(description, command, ...)`**

**Core safety mechanism for destructive operations**.

**DRY-RUN mode**:
- Prints yellow border box
- Shows `[DRY RUN]` tag and quoted command
- **Returns 0** (simulates success)

**Normal mode**:
- Prints `[PREVIEW]` tag and quoted command
- Prompts: "Execute? (y/N)"
- **Executes** if confirmed, **returns 1** if cancelled

**Implementation**: Uses `"$@"` for proper argument handling, `printf '%q '` for shell-escaped display.


### **11.11 `execute_safe(description, command, ...)`**

**Silent execution wrapper**.

**DRY-RUN mode**: Shows preview, returns 0
**Normal mode**: Executes silently, no prompts

**Used for**: `mkdir`, `git add`, `git commit` (safe or already-confirmed operations).
- Provides descriptive error messages on command failure
- Used throughout script for critical operations

### **11.12 Script Version and About**
 **12. SCRIPT VERSION & ABOUT**
 **12.1 `show_about()`**
**Displays script information and copyright**.
**Output includes**:
- Script name and version
- Copyright information
- GPL v3+ license notice
- Author contact information
**Used by**: Menu option 8 (About this script)
 **12.2 Version Display**
**Version string**:
repo-crafter v1.0.0-beta - Generic Platform Edition
Displayed in: 
- About section
- Main menu header
- Command line help output
---


## **13. MAIN MENU & NAVIGATION**

`main_menu()`

**Infinite loop**: `while true; do ... done`

**UX Features**:
- **Clear screen**: `clear` on each iteration
- **Status bar**: Shows loaded platforms and root path
- **Grouped options**: Create, Manage, Remote, System
- **Input**: Single key press (1-8)
- **Invalid handling**: Shows error, sleeps 1 second, loops

**Dispatch**: Simple `case` statement calls workflow functions.

---

## **13. COMMAND-LINE ARGUMENT PARSING**

`parse_args()`

**Global flag**: `DRY_RUN=false` (set by `--dry-run`)

**Arguments**:
- `--dry-run` / `-n`: Enables DRY-RUN mode, prints header, continues to menu
- `--test` / `-t`: Runs config load and test, then **exits** (non-interactive)
- `--help` / `-h`: Shows usage, exits

**Position**: Called at script start, before `main()`.

---

## **14. MAIN INITIALIZATION**

`main()`

**Validation sequence** (must happen in order):

1. **Tool check**: Verifies `git`, `curl`, `jq`, `ssh` in PATH

``` bash
required_tools=(git curl jq ssh envsubst tr)
optional_tools=(yq-go)
for cmd in "${required_tools[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}✗ FAILED${NC}"
        echo -e "${RED}❌ Required tool '$cmd' is not installed.${NC}"
        exit 1
    fi
done
# Optional tools with warnings
for cmd in "${optional_tools[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        missing_optional+=("$cmd")
    fi
done
```
2. **Load config**: `load_platform_config()` - exits on failure
3. **Offer config test**: Interactive prompt to run `--test` (skippable)
4. **Safety check**: `is_safe_directory "$(pwd)"` - exits if in forbidden dir
5. **Status display**: Shows platform token status (✓/✗)
6. **Launch menu**: `main_menu()`

**Critical dependencies**: Config must load successfully before any workflow can function.

---

## **15. SCRIPT EXECUTION GUARD**

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

**Purpose**: Only runs `main()` if script is executed directly (not sourced).
**Allows**: Sourcing script for testing or integration without side effects.

---

## **16. DEBUGGING GUIDE**

### **If script exits with no error message**:
Check `set -e` triggered. Run with `bash -x repo-crafter.sh` to trace.

### **If "Token NOT set" but you set it**:
- Token variable name in `platforms.conf` must match env var exactly
- Run `echo $GITHUB_API_TOKEN` in same terminal
- Check for typos in export statement
- Verify config file loaded from correct path

### **If SSH fails during test**:
- Run `ssh -T git@github.com` manually
- Check key permissions: `chmod 600 ~/.ssh/id_*`
- Verify key added to platform's web UI
- Check `~/.ssh/config` for host-specific configurations

### **If API call fails**:
- Check `PLATFORM_API_BASE` in config
- Use `--test` to see full error output
- Verify token scopes (`repo` for GitHub, `api` for GitLab)
- Check rate limiting (add ` -w "Rate limit: %{http_code}"` to curl args for debug)

### **If push fails with divergence**:
- Use workflow 2 (Convert Local → Remote) and select "Connect to EXISTING"
- The `sync_with_remote()` function offers rebase/merge options
- Check `git status` manually if conflicts occur

---

## **17. REFACTORING NOTES**

**To add a new workflow**:
1. Create function `my_workflow()`
2. Add menu option in `main_menu()` case statement
3. Use `select_platforms()` for platform selection
4. Use `execute_dangerous()` for destructive operations

**To add a new platform setting**:
1. Add `declare -A PLATFORM_NEW_SETTING` to globals section
2. Add to reset loop in `load_platform_config()`
3. Add parsing case in config parser
4. Use in appropriate functions

**To change project root directories**:
Modify `LOCAL_ROOT` and `REMOTE_ROOT` at top of script. **Manually move existing projects** to new locations.

---

**End of Documentation**
```

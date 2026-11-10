
```markdown
# **REPO-CRAFTER USER MANUAL**

<!--
User Manual for repo-crafter
Copyright (C) 2026 Dharrun Singh
SPDX-License-Identifier: CC-BY-4.0
This work is licensed under the Creative Commons Attribution 4.0 International License.
To view a copy of this license, visit https://creativecommons.org/licenses/by/4.0/.
-->

**Purpose**: Safe, interactive Git repository management for solo developers and small teams

---

## **📋 Table of Contents**
1. [Quick Start (5-Minute Setup)](#quick-start)
2. [Initial Configuration](#initial-configuration)
3. [Core Concepts](#core-concepts)
4. [Understanding Project Types](#understanding-project-types)
5. [Workflow Guides](#workflow-guides)
6. [Command-Line Options](#command-line-options)
7. [Gitignore Modes Explained](#gitignore-modes-explained)
8. [Multi-Platform Projects](#multi-platform-projects)
9. [Troubleshooting](#troubleshooting)
10. [Safety Features](#safety-features)
11. [Advanced Configuration](#advanced-configuration)
12. [Best Practices](#best-practices)
13. [File Locations Reference](#file-locations-reference)

---

## **1. Quick Start (5-Minute Setup)**

### **Step 1: Install Dependencies if they don't exist**

**Dependencies**: git, jq, yq, curl, openssh-client
**Intepreter**: BASH 
#### Ubuntu/Debian
```bash
sudo apt update && sudo apt install -y git curl jq openssh-client
```
#### Fedora
```bash
sudo dnf install -y git curl jq openssh-clients
```
#### macOS (with Homebrew)
```bash
brew install git curl jq
```
#### Verify installation
```bash
for cmd in git curl jq ssh; do command -v "$cmd" && echo "✓ $cmd installed"; done
```
#### For NixOS
define them in your packages (pkgs following nixpkg) in configuration.nix, if they don't exist, you can also define this script as an executable and assign an alias, even in home.nix (if you use home-manager).

For example, for those packages which don't exist

Good practice in configuration.nix
```nix
{config, pkgs, libs}
{
  user.user.your-username = {
    packages = with pkgs; [
    jq
    curl
    git
    yq-go
    ];    
  };
}  
```

Or in home.nix

```nix
(config, pkgs, libs)
{
home.packages = with pkgs [
  jq
  yq-go
  git
  curl
  ];
}
```
make sure you follow nixpkgs (define it in flake if you use it flake).

### **Step 2: Configure SSH Keys**

**For GitHub:**
```bash
# Generate key (if you don't have one)
ssh-keygen -t ed25519 -C "your@email.com" -f ~/.ssh/id_ed25519_github

# Add to GitHub
cat ~/.ssh/id_ed25519_github.pub

# Copy output and paste at: https://github.com/settings/keys
# Click "New SSH Key"

# Test connection
ssh -T git@github.com
# Expected: "Hi username! You've successfully authenticated..."
```

**For GitLab:**
```bash
# Generate key
ssh-keygen -t ed25519 -C "your@email.com" -f ~/.ssh/id_ed25519_gitlab

# Add to GitLab
cat ~/.ssh/id_ed25519_gitlab.pub

# Copy output and paste at: https://gitlab.com/-/profile/keys

# Test connection
ssh -T git@gitlab.com
# Expected: "Welcome to GitLab, @username!"
```

### **Step 3: Get API Tokens**

**GitHub Token:**
1. Go to https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Scopes: Select `repo` (full repository access)
4. Expiration: Choose 90 days or custom
5. Click "Generate token"
6. **Copy the token immediately** (starts with `ghp_`)

**GitLab Token:**
1. Go to https://gitlab.com/-/profile/personal_access_tokens
2. Name: `repo-crafter`
3. Expiration: Choose date
4. Scopes: Select `api` (full API access)
5. Click "Create personal access token"
6. **Copy the token immediately** (starts with `glpat-`)

define the token keys as session variables safely without exposure

### **Step 4: Set Environment Variables**

Add to your shell profile (`~/.bashrc`, `~/.zshrc`, or `~/.profile`):

```bash
# GitHub token
export GITHUB_API_TOKEN="ghp_your_token_here"

# GitLab token
export GITLAB_API_TOKEN="glpat_your_token_here"
```

Apply changes:
```bash
source ~/.bashrc  # or ~/.zshrc
```

### **Step 5: Create `platforms.conf`**

Create the config file:
```bash
mkdir -p ~/.config/repo-crafter
nano ~/.config/repo-crafter/platforms.conf
```

Paste this template and save:

```ini
[github]
enabled = true
api_base = https://api.github.com
ssh_host = github.com
repo_domain = github.com
token_var = GITHUB_API_TOKEN
auth_header = Bearer {token}
accept_header = application/vnd.github+json  # Required for GitHub API
repo_delete_endpoint = /repos/{owner}/{repo}
authenticated_user_endpoint = /user
authenticated_user_key = .login  # jq path to extract username
repo_check_endpoint = /repos/{owner}/{repo}
repo_check_method = GET
repo_check_success_key = id
repo_create_endpoint = /user/repos
repo_create_method = POST
repo_list_endpoint = /user/repos?per_page=100&sort=updated
repo_list_success_key = .[0].id
work_dir = github.com
owner_not_found_patterns = not found,does not exist
ssh_url_fields = ssh_url,clone_url
visibility_map = {"private":"private","public":"public"}

[gitlab]
enabled = true
api_base = https://gitlab.com/api/v4
ssh_host = gitlab.com
repo_domain = gitlab.com
token_var = GITLAB_API_TOKEN
auth_header = Bearer {token}
accept_header = application/json
repo_delete_endpoint = /projects/{owner}%2F{repo}
authenticated_user_endpoint = /user
authenticated_user_key = .username
repo_check_endpoint = /projects/{owner}%2F{repo}
repo_check_method = GET
repo_check_success_key = id
repo_create_endpoint = /projects
repo_create_method = POST
repo_list_endpoint = /projects?membership=true&per_page=100&order_by=updated_at
repo_list_success_key = .[0].id
work_dir = gitlab.com
owner_not_found_patterns = not found,does not exist
ssh_url_fields = ssh_url,http_url_to_repo
visibility_map = {"private":"private","public":"public"}

[multi]
work_dir = Multi-server
```



### **Step 6: Download repo-crafter**

```bash
# Place it in your PATH
cd ~/.local/bin
wget https://raw.githubusercontent.com/yourusername/repo-crafter/main/repo-crafter.sh
chmod +x repo-crafter.sh

# Add to PATH if not already there
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## **2. Initial Configuration**
### **Create directories**
Projects
├── Local_Projects
│   
└── Remote_Projects
    └── Multi-server
create directores similar to the tree Structure
You can use the following commands for ease
```bash
# Create Projects directory
mkdir ~/Projects

cd ~/Projects

mkdir Local_Projects

mkdir Remote_Projects

cd Remote_Projects

mkdir Multi-server
```

### **Verify Setup**

```bash
# Run configuration test
repo-crafter --test
```

**Expected output:**

```Loading platform configuration... ✅ Loaded 2 platform(s): github gitlab

=== TESTING PLATFORM CONFIGURATION ===
Available platforms: github gitlab

Token status:
  github: ✓ Token set
  gitlab: ✓ Token set

Testing SSH connection to github.com... ✅ Connected
Testing SSH connection to gitlab.com... ✅ Connected

Testing platform selection...

Choose platform(s):
  1) github
  2) gitlab
  a) All platforms
  m) Multiple selection (e.g., 1,3,5)
  x) Cancel

Enter your choice: x

No selection made

Press Enter to continue...
```

If you see ✓ and ✅, your setup is correct.

---

## **3. Core Concepts**

### **Project Lifecycle States**

1. **Local-only**: No remotes, isolated development
2. **Bound**: Connected to one or more remotes, sync-capable
3. **Multi-platform**: Bound to multiple platforms simultaneously
4. **Archived**: Unbound from remotes, moved to `Local_Projects/`

### **Safety Philosophy**
- **Preview before execute**: All destructive operations show exact command
- **Confirmation required**: Deletions need explicit `y` input
- **Type-to-confirm**: Deleting both local and remote requires typing project name
- **Directory isolation**: Cannot operate in system directories
- **Duplicate detection**: Warns about similar names before creation

---

## **4. Understanding Project Types**

### **Local Projects** (`~/Projects/Local_Projects/`)
- Completely disconnected from remotes
- For prototypes, trade secrets, offline work
- No push/pull capability
- Created via "Create local-only project" option

### **Remote Projects** (`~/Projects/Remote_Projects/`)
- Bound to a platform like  GitHub, Gittea, GitLab, Codeberg, etc
- Can push/pull
- Organized by platform name (e.g., `github.com/`, `gitlab.com/`)

### **Multi-Server Projects** (`~/Projects/Remote_Projects/Multi-server/`)
- Bound to multiple platforms; each push is a deliberate manual command
- Creates `repo-crafter.yml` manifest declaring the actual remotes
- Perfect for mirroring to GitLab backup while using GitHub primary

---

## **5. Workflow Guides**
### **Workflow 1: Create Your First Repository**

**Perfect for**: Starting a new hardware/embedded project/a project from scratch with new Repository creation

```bash
repo-crafter
```

**Menu Navigation**:
1. Select `1) 🆕 Create New Project`
2. Select `1) Create new local + remote repo (API)`
3. Enter project name: `motor-controller`
4. Select platform: `1` (GitHub) or `a` (All platforms)
5. Select visibility: `1` (Private)
6. Gitignore setup:
- First, choose pattern source:
    1) Generic patterns only (OS, editors, build artifacts)
    2) Fetch from GitHub gitignore templates
    3) Manual entry only (you add everything yourself)
- Enter additional custom patterns line-by-line
- Choose mode:
    1) Simple: Commit immediately (recommended)
    2) Cautious: Review in nano first
    3) Local-only: Move to `.git/info/exclude` (never pushed)
7. Confirm preview prompts with `y`

**Result**: New repository created and ready at `~/Projects/Remote_Projects/github.com/motor-controller/`. Nothing was pushed; run the printed `git push -u <remote> <branch>` when you are ready.

### **Workflow 2: Clone an Existing Repository**

**Perfect for**: Joining an open-source project or team repo

```bash
repo-crafter
```

**Menu Navigation**:
1. Select `1) 🆕 Create New Project`
2. Select `2) Clone existing remote repo`
3. Select platform (e.g., GitHub)
4. List shows your repositories for reference
5. Enter repository path: `organization/project-name` or `username/repo-name`
6. Repository clones to `~/Projects/Remote_Projects/github.com/project-name/`

**SSH Check**: Script verifies SSH authentication before attempting clone to prevent errors.


### **Workflow 3: Work on Trade Secrets Offline**

**Perfect for**: Prototypes you don't want to push yet

```bash
repo-crafter
```

**Menu Navigation**:
1. Select `1) 🆕 Create New Project`
2. Select `3) Create local-only project (no binding)`
3. Enter project name: `secret-sensor-design`
4. Work completely offline in `~/Projects/Local_Projects/secret-sensor-design/`

**When ready to share:**
```bash
repo-crafter
# Select: 2) 🔗 Convert Local → Remote
# Choose: secret-sensor-design
# Select binding method: Create new repositories
# Add platform(s), then push manually when ready
```

### **Workflow 4:  Convert Single-Platform to Multi-Platform Project**

**Perfect for**: When you want to mirror your repository across multiple platforms (GitHub + GitLab).

**Menu Navigation:**
1. Select `2) 🔗 Convert Local → Remote`
2. Choose your project that's currently bound to a single platform
3. Select option: `Convert single-platform to multi-platform`
4. Enter additional repository URLs (one per line) for other platforms
   - Example: `git@gitlab.com:username/project.git`
   - Example: `git@github.com:username/project.git`
5. Confirm conversion

**Script performs:**
- Moves project to `~/Projects/Remote_Projects/Multi-server/`
- Adds new remotes for each platform URL
- Creates `repo-crafter.yml` manifest declaring the actual remotes
- Renames existing "origin" remote to platform name (e.g., "github")
- Shows status of all configured remotes

**Important notes:**
- Your original single-platform remote is preserved with a new name
- All existing commits and history are maintained
- You can push to all platforms with `git push --all`
- The manifest file declares intent for future operations; it is not a state cache

**Example output:**

```✅ Successfully converted to multi-platform!
Remotes:
github  git@github.com:username/project.git (fetch)
github  git@github.com:username/project.git (push)
gitlab  git@gitlab.com:username/project.git (fetch)
gitlab  git@gitlab.com:username/project.git (push)
```

### **Workflow 5: Convert Single-Platform to Multi-Platform**
**When to use**: You have a project on one platform (e.g., GitHub) and want to add additional platforms (e.g., also on GitLab).
**Steps**:
1. Select the existing single-platform project
2. Review current remote configuration  
3. Enter additional repository URLs (one per line)
4. Confirm the conversion
5. Automatic setup of multiple remotes
**What happens**:
- Project moves from platform-specific directory to `Multi-server/` folder
- Existing remote renamed to platform name
- Additional remotes added for new platforms
- Multi-platform manifest created for tracking
**Result**: Project with multiple remotes for different platforms, stored in `Multi-server/` directory structure.

### **Workflow 6: Bind Local Project to Existing Remote**

**: Connect to pre-existing repository**.

**Use case**: You cloned manually before, or need to reconnect after issues.

```bash
repo-crafter
```

**Menu Navigation**:
1. Select `2) 🔗 Convert Local → Remote`
2. Choose local project
3. Select binding method: `2) Connect to EXISTING remote repository`
4. Enter repository URL(s) (one per line, empty line to finish):
   - `git@github.com:username/project.git`
   - `git@gitlab.com:username/project.git`
5. Script parses URLs, detects platforms, verifies access
6. Project moves to appropriate `REMOTE_ROOT` subdirectory
7. Remotes added and sync performed

---

### **Workflow 7: Archive a Project (Disconnect)**

**Perfect for**: archiving old work, before removing project from remote.

```bash
repo-crafter
```

**Menu Navigation**:
1. Select `3) 🔓 Convert Remote → Local`
2. Choose project from list
3. Confirm preview → Project moved to `Local_Projects/`, ALL remotes removed
4. `repo-crafter.yml` (and any legacy `REMOTE_STATE.yml`) deleted

**Result**: Keep all code locally, no remote sync, safe for personal backup

---

### **Workflow 8: Handle Remote Divergence**

Perfect for: When you worked offline and the remote repository has new commits.

```repo-crafter


**Menu Navigation:**
1. Select `2) 🔗 Convert Local → Remote`
2. Choose your local project with divergence
3. Select binding method: `2) Connect to EXISTING remote repository`
4. Enter the remote URL
```
**Script detects divergence and presents options:**
```⚠️  DIVERGENCE DETECTED: Remote has 3 new commit(s)
   You have 2 local commit(s) not pushed

Integration options:
  1) Rebase (clean history)
  2) Merge (safer for collaboration)
  3) Skip integration (no push)
  x) Cancel
```

**Option details:**
- **1) Rebase**: Places your local commits on top of remote commits (clean linear history). Best for personal projects. The script then prints the `git push --force-with-lease` command; you run it.
- **2) Merge**: Creates a merge commit that preserves both histories. Safest for team collaboration. The script then prints the `git push` command.
- **3) Skip**: Leaves local and remote divergent and prints the manual `git pull --rebase` and `git push` commands.

> **The script never pushes.** It fetches, reports, and can rebase or merge locally, but every remote write is a command you run deliberately.

**Automatic handling:**
- Uncommitted changes are automatically stashed before operations
- Stashed changes are restored after successful operations
- On cancellation, stashed changes remain available (run `git stash pop` to restore)

**Branch mismatch handling:**
If your local branch name doesn't match the remote's default branch, you'll be prompted:
```⚠️  Branch mismatch: local 'feature/new-ui' vs remote 'main'
Rename local branch to match remote? (Y/n)
```

### **Workflow 9: List All Your Repositories**

**Perfect for**: Finding a project across platforms

```bash
repo-crafter
```

**Menu Navigation**:
1. Select `5) 📋 List Remote Repositories`
2. Select platform(s): `a` (All) or specific platform
3. Shows up to 100 repositories per platform with visibility and SSH URL

---

### **Workflow 10: Manage Gitignore**

**Perfect for**: Adding ignore patterns to existing project

```bash
repo-crafter
```

**Menu Navigation**:
1. Select `6) ⚙️  Configure .gitignore`
2. Enter project directory: `~/Projects/Remote_Projects/github.com/project/`
3. If `.gitignore` exists, choose:
   - `1) Review/edit existing`
   - `2) Overwrite (dangerous)`
   - `3) Delete (not recommended)`
4. Add common patterns automatically? `1) Yes`
5. Enter additional patterns line-by-line
6. Choose mode:
   - `1) Simple`: Commit immediately
   - `2) Cautious`: Review in nano first
   - `3) Local-only`: Move to `.git/info/exclude` (never pushed)

---

### **Workflow 11: Delete Projects Safely**

**Perfect for**: Cleaning up disk space

```bash
repo-crafter
```

**Menu Navigation**:
1. Select `4) 🗑️  Manage/Delete Project`
2. Choose option:
   - `1) Delete local files` (bound remotes are kept; a local-only project is deleted permanently)
   - `2) Unbind from remote` (keeps local, moves to `Local_Projects/`)
   - `3) Delete BOTH` (TYPE PROJECT NAME TO CONFIRM)
3. Select project
4. **Option 3 uses TWO-FACTOR CONFIRMATION**:
  1) First, you must type the EXACT project name (case-sensitive)
  2) Then, you must type 'DELETE' to acknowledge permanent data loss
- This prevents accidental deletions from typos or muscle memory
⚠️ **DANGER**: This permanently deletes remote repository and ALL local files
No recovery possible - this is an irreversible operation

> Option 3 lists single-platform projects only. `Multi-server` projects hold several remotes and must be removed manually for now.

---

## **6. Command-Line Options**

### **Standalone Tests**

```bash
# Verify configuration without launching menu
repo-crafter --test
# or
repo-crafter -t
```

**Use when**: You changed tokens or SSH keys and want quick validation

### **Dry-Run Mode**

```bash
# Preview all operations without executing
repo-crafter --dry-run
```
*Use when: Learning the tool, testing workflows, verifying multi-platform setup before execution*
**What happens**:
All operations are PREVIEWED but NOT EXECUTED
Each action is recorded in a list of planned operations
At workflow completion, ALL accumulated actions are displayed together
NO files created, NO API calls made, NO directories moved or deleted
Final prompt shows: "To execute these actions for real, run without --dry-run"
Critical safety feature: No partial execution - all actions are either previewed or fully executed

### **Help**

```bash
repo-crafter --help
```

---

## **7. Gitignore Modes Explained**

### **Mode 1: Simple (Recommended for Most Projects)**
- Create `.gitignore` file
- Add specified patterns
- Stage and commit immediately
- **Pushable**: Yes, shared with team

**Best for**: Standard development patterns (build artifacts, logs, dependencies)

### **Mode 2: Cautious (Review Before Commit)**
- Create `.gitignore` file
- Add specified patterns
- Open in nano editor for review/editing
- Stage and commit after manual approval
- **Pushable**: Yes, shared with team

**Best for**: Complex projects where ignore rules need careful review, or when learning gitignore syntax

### **Mode 3: Local-Only (Secrets & Personal Patterns)**
- Create temporary `.gitignore` file
- Add specified patterns
- Move to `.git/info/exclude`
- **Never staged, never committed, never pushed**
- **Pushable**: No, stays local only

**Best for**:
- Personal IDE files (`.vscode/settings.json`)
- Local experiment files
- Machine-specific paths
- API keys or secrets that should never be committed

**⚠️ WARNING**: Mode 3 patterns are invisible to collaborators. Use only for truly local patterns.

---

## **8. Multi-Platform Projects**

### **When to Use**
- **Primary + Backup**: GitHub for development, GitLab for backup
- **Open source + Private mirror**: Public GitHub repo, private GitLab mirror
- **Platform migration**: Testing GitLab while still using GitHub
- **Redundancy**: Protect against platform outages

### **How It Works**
1. During creation/binding, select multiple platforms (use `m` for multiple selection)
2. Script creates repositories on **all** selected platforms
3. Adds separate remotes for each platform; the remote names are exactly what `git remote -v` shows
4. Writes `repo-crafter.yml` from those actual remotes
5. Initial push is manual per remote: `git push github`, `git push gitlab`

### **Project Structure**
```~/Projects/Remote_Projects/
└── Multi-server/
    └── my-important-project/
        ├── .git/
        ├── repo-crafter.yml      # Declared intent (commit this)
        └── [project files]
```

### **repo-crafter.yml Manifest**

```yml
# repo-crafter manifest
# Declares intent. repo-crafter reads this file; edit it deliberately.
# Generated: 2026-11-09T11:00:00+0530
# Action: convert_single_to_multi

schema: 1

project:
  name: "my-important-project"
  default_branch: "main"

remotes:
  - name: "github"
    platform: "github"
    host: "github.com"
    owner: "yourusername"
    repo: "my-important-project"
    role: "primary"
    url: "git@github.com:yourusername/my-important-project.git"
  - name: "gitlab"
    platform: "gitlab"
    host: "gitlab.com"
    owner: "yourusername"
    repo: "my-important-project"
    role: "mirror"
    url: "git@gitlab.com:yourusername/my-important-project.git"
```

**What belongs here:** intent only — the project name, default branch, and the remotes that should exist, including their real git names, platforms, hosts, owners, repositories, roles, and URLs.

**What never belongs here:** head commits, timestamps, absolute paths, maintainer usernames, ahead/behind counts, or API endpoint snapshots. Those are observations; the tool derives them from git when needed.

**Ownership and recovery:**
- `repo-crafter.yml` is human-owned and meant to be committed. The tool writes it only on create, convert, init, migrate, or an explicit rewrite.
- Writes are atomic: a temporary file is written and validated, then moved over the original. A failed write leaves the original untouched.
- Before an explicit rewrite, the previous version is copied to `.git/repo-crafter/repo-crafter.yml.bak` (never committed).
- An invalid manifest is reported and left as-is; restore a good copy with `git checkout -- repo-crafter.yml` or the `.bak` copy.
- A legacy `REMOTE_STATE.yml` is moved to `.git/repo-crafter/legacy/REMOTE_STATE.yml` during migration, never deleted.
- Single-platform projects also receive a manifest with one remote, so every bound project has the same shape.
- If a cloned repository already contains a manifest, it is validated and kept, not overwritten.

**Checking a manifest:** menu option `10) 🧾 Project Manifest` selects a project, validates the schema, compares the declared remotes with `git remote -v`, and warns about missing, extra, renamed, or URL-mismatched remotes. It can also create a missing manifest or migrate a legacy one.

**Optional keys:** later versions may use `branches`, `policy`, `ownership`, and `credentials` (references only, never secret values). The current reader uses `project` and `remotes` and ignores unknown keys. An explicit rewrite regenerates the file, so commit before rewriting if you have custom keys.


---

## **9. Troubleshooting**

### **Problem: "Token NOT set" Error**

**Cause**: Environment variable not loaded or config mismatch

**Solution**:
```bash
# Check if variable exists
echo $GITHUB_API_TOKEN

# If empty, reload your profile
source ~/.bashrc

# Or set manually for current session
export GITHUB_API_TOKEN="ghp_xxxxxxxxxxxx"

# Verify config references correct variable name
grep "token_var" ~/.config/repo-crafter/platforms.conf
```

### **Problem: SSH Connection Fails**

**Cause**: SSH key not added to platform or wrong key

**Solution**:
```bash
# Test manually
ssh -T git@github.com

# If fails, check key exists
ls ~/.ssh/id_ed25519_github*

# If missing, regenerate
ssh-keygen -t ed25519 -C "your@email.com" -f ~/.ssh/id_ed25519_github

# Add to GitHub again
cat ~/.ssh/id_ed25519_github.pub
# Copy to https://github.com/settings/keys
```

### **Problem: "Repository already exists" Warning**

**Cause**: You have another local project with same name in search directories

**Solution**:
- Use a different project name, OR
- Delete the old project first, OR
- Use `y` to continue anyway (manage duplicates manually)

### **Problem: Push Fails with 403 or 404**

**Cause**: Token lacks permissions, owner not found, or you're not a collaborator

**Solution**:
1. Regenerate token with `repo` scope (GitHub) or `api` scope (GitLab)
2. If organization repo, ensure you're a collaborator with push access
3. Verify remote URL: `git remote -v`
4. Check `owner_not_found_patterns` in config matches platform error messages

### **Problem: Divergence/Rebase Conflicts**

**Cause**: Remote has commits you don't have locally

**Solution**:
- Use workflow 5 (Connect to existing) to trigger `sync_with_remote()`
- Choose **Merge** if you're not comfortable with rebasing
- For conflicts, script will pause—resolve manually with `git status` and `git add`
- If stashed, restore with `git stash pop` after conflict resolution

### **Problem: "command not found: repo-crafter"**

**Cause**: Script not in PATH

**Solution**:
```bash
# Add to PATH permanently
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Test
which repo-crafter
```

### **Problem: DRY-RUN Shows Preview But Real Run Fails**

**Cause**: DRY-RUN mode cannot catch all real-world issues (network, auth, edge cases)

**Solution**:
- Run `--test` to verify SSH and tokens
- Check `git status` in project directory
- Verify remote URLs: `git remote -v`
- Review API error messages in output

---

## **10. Safety Features**

### **Automatic Protections**
- **Cannot operate in**: `/etc`, `/root`, `/bin`, `/sbin`, `/usr`, `/`
- **Directory checks**: Warns if project with same name exists elsewhere
- **Duplicate remote detection**: Shows when multiple locals point to same remote
- **Confirmation required**: All destructive operations need explicit `y` input
- **Type-to-confirm**: Deleting both local and remote requires typing project name exactly

### **Manual Safeguards**
- **Use `--dry-run`** before unfamiliar workflows
- **Use `--test`** after modifying `platforms.conf` or tokens
- **Never share tokens**; keep them in environment variables only
- **For critical work**: Maintain separate backup on different platform
- **Review manifests**: Check `repo-crafter.yml` before deleting multi-platform projects

### **SSH & API Safety**
- SSH keys never leave your machine
- Tokens only stored in environment (not in config file)
- All API calls use HTTPS with proper authentication headers
- SSH preferred over HTTPS for repository operations

---

## **11. Advanced Configuration**

### **Add a New Platform (e.g., Codeberg)**

Edit `~/.config/repo-crafter/platforms.conf`:

```ini
[codeberg]
enabled = true
api_base = https://codeberg.org/api/v1
ssh_host = codeberg.org
repo_domain = codeberg.org
token_var = CODEBERG_API_TOKEN
auth_header = Bearer {token}
repo_check_endpoint = /repos/{owner}/{repo}
repo_check_method = GET
repo_check_success_key = id
repo_create_endpoint = /user/repos
repo_create_method = POST
repo_list_endpoint = /user/repos
repo_list_success_key = .[0].id
work_dir = codeberg.org
owner_not_found_patterns = not found,does not exist
ssh_url_fields = ssh_url,clone_url
visibility_map = {"private":"private","public":"public"}
```

Set token:
```bash
export CODEBERG_API_TOKEN="your_codeberg_token"
```

Test:
```bash
repo-crafter --test
```

### **Custom Visibility Mapping**

Some platforms use different visibility terms. Use `visibility_map` to translate:

```ini
# Example for enterprise GitHub with "internal" visibility
[github-enterprise]
visibility_map = {"private":"private","public":"public","internal":"internal"}
```

### **Custom SSH URL Fields**

If platform API returns SSH URL under non-standard field names:

```ini
# Try ssh_url first, then fallback to custom field
ssh_url_fields = ssh_url,ssh_clone_url,git_ssh_url
```

### **Custom API Accept Headers**

Some APIs require specific `Accept` headers for proper response formatting:

```ini
# GitHub requires special media type
accept_header = application/vnd.github+json

# GitLab uses standard JSON
accept_header = application/json
```

**When to customize**: Enterprise instances of GitHub/GitLab may require different headers. Most users can use the defaults shown above.

### **Custom Repository Delete Endpoints**

Different platforms use different API paths for repository deletion:

```ini
# GitHub standard format
repo_delete_endpoint = /repos/{owner}/{repo}

# GitLab requires URL-encoded owner/repo
repo_delete_endpoint = /projects/{owner}%2F{repo}
```

**Placeholders**:
- `{owner}`: Repository owner (URL-encoded if needed)
- `{repo}`: Repository name

**Note**: Most platforms work with standard patterns. Enterprise instances may need custom paths.

---

## **12. Best Practices for Developers**

1. **Start local**: Use "Create local-only" for prototypes (workflow 3)
2. **Push when ready**: Convert to remote when collaboration is needed (workflow 2)
3. **Use Mode 3 gitignore**: For private keys, local experiments, personal IDE settings
4. **Multi-platform early**: If you might mirror later, create as multi-server from start
5. **Clean up regularly**: Use `--dry-run` before deletion workflows
6. **Test after changes**: Run `--test` after updating tokens or SSH keys
7. **Review manifests**: Check `repo-crafter.yml` in multi-platform projects before moving/deleting
8. **Document decisions**: Use Mode 2 (cautious) gitignore to add comments explaining patterns

---

## **13. File Locations Reference**

| File | Purpose | Back Up? | Contains Secrets? |
|------|---------|----------|-------------------|
| `~/.config/repo-crafter/platforms.conf` | Platform definitions | ✅ Yes | No (config only) |
| `~/.ssh/id_ed25519_github` | SSH private key | ✅ **CRITICAL** | ✅ **YES** |
| `~/.ssh/id_ed25519_gitlab` | SSH private key | ✅ **CRITICAL** | ✅ **YES** |
| `~/.bashrc` or `~/.zshrc` | Token environment variables | ✅ Yes | ✅ **YES** |
| `~/Projects/` | All your projects | ✅ **CRITICAL** | Maybe (code) |
| `repo-crafter.yml` | Declared project intent | ✅ Yes | No (URLs only) |

**Security Checklist**:
- [ ] SSH keys have `chmod 600` permissions
- [ ] Tokens are in environment variables, not in config files
- [ ] `platforms.conf` is not shared publicly
- [ ] `.git/info/exclude` (Mode 3) is never committed
- [ ] `repo-crafter.yml` can be committed safely (no secrets)

---

**End of Manual**
---


# Repo-Crafter Changelog

All notable changes to Repo-Crafter will be documented in this file.

## [fix/tier0] - 2026-11-07

### Fixed
- Startup crash: `PLATFORM_REPO_DELETE_METHOD` was written by the config parser but never declared, so `set -u` failed on `github: unbound variable`
- Startup crash: `${!token_var}` was expanded unguarded in three places, so the menu could not render when a platform token was not exported
- `.gitignore` workflow accepted a free-text directory and could modify files outside `~/Projects`; it now uses the existing project picker and cannot receive a typed path
- Project roots are now derived from a single `PROJECT_ROOT` variable; default values are unchanged
- `_create_local_only` now validates the project name with `validate_project_name`, so `..` and `/` can no longer create directories outside `PROJECT_ROOT`
- `_prompt_project_name` now delegates to `validate_project_name` (one whitelist, one place) and `_create_local_only` uses it, so an invalid name re-asks instead of exiting
- `_clone_existing_remote` now sanitizes the URL-derived name with `safe_dir_name` (dots to underscores, other invalid characters to `_`), so `..` can no longer resolve the clone destination outside `REMOTE_ROOT`
- `warn_duplicate_repo_name` now searches `PROJECT_ROOT` instead of a hardcoded `$HOME/Projects`, `~/Work`, `~/Development`, `~/git` list
- `convert_remote_to_local_workflow` (unbind) now actually removes remotes before moving: the remote list is read into an array so confirmations read the terminal instead of the list, and the removal counter no longer trips `set -e` on the first remote
- `convert_local_to_remote_workflow` (bind) now aborts if the local file copy fails, and the cleanup `rm -rf`/backup `mv` go through `execute_dangerous` (preview, confirm, dry-run gate)
- `convert_local_to_remote_workflow` no longer carries the unreachable duplicate option-2 block, its dead `remote_url` assignment, or the unused `parsed_path`/`repo_name`/`parsed` values; the destination directory is created only after confirmation
- `convert_single_to_multi_platform` now creates the missing `Multi-server` parent before moving (git clone creates it, `mv` does not)
- `convert_single_to_multi_platform` gates the overwrite `rm -rf` and the move through `execute_dangerous`, and stops after the move in dry-run so the "NO CHANGES WERE MADE" banner is true
- `_select_project_from_dir` accepts an optional directory to exclude from its scan; other callers are unchanged
- `convert_single_to_multi_platform` no longer lists `Multi-server` projects and refuses them as a source, so the overwrite path can no longer delete a project that is already multi-platform; the unused `single_projects` scan was removed
- `convert_remote_to_local_workflow` (unbind) now resolves the destination before touching remotes, so declining the overwrite leaves the project and its remotes untouched
- `convert_remote_to_local_workflow` now actually replaces an existing destination instead of nesting the project inside it (`mv` into an existing directory creates `dest/project`), and the overwrite `rm -rf` is gated through `execute_dangerous`
- `convert_remote_to_local_workflow` no longer carries the unused `projects` scan, and both directory changes are guarded instead of exiting the script on failure
- `_delete_local_copy` now lists both local-only and bound projects (from `PROJECT_ROOT`) and warns for each case: a local-only project is the only copy, while a bound project keeps its remotes and can be re-cloned; the menu label no longer promises a kept remote for remote-less projects
- `_delete_both` now deletes every remote on its own platform (detected from the remote URL) instead of only the first one, so "DELETE EVERYTHING" no longer leaves other platform repositories alive
- `_delete_both` no longer crashes under `set -u` when the remote is named `origin`, keeps local files when a platform has no delete endpoint, and shows the dry-run previews it used to swallow
- `_delete_both` no longer lists `Multi-server` projects, since a multi-platform project has several remotes; they must be removed manually until a dedicated flow exists
- `_create_local_only` no longer changes the working directory; its git commands target the new folder explicitly and dry-run stops before any git write, so a preview can no longer commit files in whatever repository the script was launched from
- `_create_local_only` initialises on the configured default branch instead of the branch of the caller's repository
- `remove_existing_remotes` accepts a target directory (defaults to the current one) and runs its removal loop without a subshell; declining it no longer exits the script
- `_create_with_new_remote` now runs `_cleanup_failed_creation` when `git add`, `git commit`, or `git remote add` fails, so a failed creation no longer leaves an orphaned remote repository and a half-built local folder; the unused `local_created` flag was removed
- `_clone_existing_remote` now sends its progress messages to stderr and keeps stdout for the returned path only, so the binding caller no longer needs the `tail -n1` workaround and standalone mode no longer prints a stray path line
- `_clone_existing_remote` no longer pipes `git clone` through `head -30`, so error output is not truncated and `pipefail` cannot turn a closed pipe into a false clone failure
- `gitignore_maker` now actually appends the generic patterns when `curl` is missing or the template list cannot be fetched; the dead `source_choice=1` reassignment is gone
- `gitignore_maker` uses `git -C "$project_dir"` instead of `cd`, so configuring a project no longer changes the menu's working directory
- `gitignore_maker` downloads templates with `curl -fsS` and appends them only on success, so a failed fetch no longer writes an error body or a dangling header
- `gitignore_maker` writes `.gitignore.template` only in commit mode, reports an invalid mode choice honestly, and returns non-zero when the commit fails; the interactive wrapper keeps that from exiting the menu
- `work_dir` from `platforms.conf` is validated at load time as a single directory component (no `/`, not `.` or `..`), so a config value can no longer point project paths outside `REMOTE_ROOT`; a missing value now defaults to `repo_domain`, then to the platform name
- `list_remote_repos_workflow` no longer checks `$?` after `mapfile`, which is always 0; cancellation was already detected by the empty platform list, so the dead condition is gone
- `_create_with_new_remote` no longer changes the working directory; its git commands target the new folder with `git -C`, and the README is written by path, so the menu stays where it was
- `_cleanup_failed_creation` now uses the platform's `repo_delete_endpoint` and `repo_delete_method` instead of the check endpoint with a hardcoded `DELETE`, and reports whether the remote was actually removed
- `convert_local_to_remote_workflow` checks the `git add`/`git commit` result in both binding paths, so a failed commit no longer prints "Changes committed"; the files stay in place for a manual commit
- `convert_single_to_multi_platform` matches the platform directory with a trailing `/`, so a sibling such as `github.com-extra` can no longer be treated as the project's platform
- `convert_single_to_multi_platform` checks the remote rename and add results, and gives duplicate-platform URLs unique remote names (`github`, `github_2`, ...) instead of silently skipping them
- `convert_single_to_multi_platform` gives duplicate-platform URLs unique manifest keys instead of overwriting the previous entry, and no longer changes the working directory
- `warn_duplicate_remote_connections` no longer subtracts a phantom path, so two directories sharing one remote are actually reported; it now returns 0 because it is a warning, not a failure
- `warn_similar_remote_repos` returns 0 after reporting similar names, so a warning no longer aborts the bind workflow
- Menu actions now run in a subshell with `set -e` re-enabled inside, so a cancelled or failed action stops at that point and the menu is shown again instead of the script exiting; `confirm_action` also treats an unreadable prompt as "no" instead of reusing the previous answer
- `check_ssh_auth` no longer passes the configured `ssh_host` through `bash -c`; the host is validated as a DNS-name shape and passed to `ssh` as an argument, so config content can no longer run commands
- `_select_project_from_dir` resolves the root, the exclusion directory, and each candidate with `realpath`, and skips anything that resolves outside the root
- `is_safe_directory` now resolves the target and compares directory boundaries, so `/etcetera` is no longer rejected as `/etc`; `execute_dangerous` refuses `rm`/`mv` targets that resolve outside `PROJECT_ROOT` (including `..` escapes and the root itself)
- `_create_with_new_remote` refuses an existing destination before creating anything, so it can no longer overwrite a `README.md` or let `_cleanup_failed_creation` delete a folder it did not create; it also runs `warn_duplicate_repo_name` before creating
- `_create_local_only` runs `warn_duplicate_repo_name` before creating and returns non-zero when the destination already exists
- `sync_with_remote` now syncs the current branch only and never renames branches; it prints the push command for a branch that is missing on the remote, lists local-only and remote-only branches, and does not merge or rebase branches that are not checked out
- `sync_with_remote` treats a reachable but empty remote as accessible (the `ls-remote --exit-code` check failed for new repositories), and no longer prints the push command twice for the current branch
- `sync_with_remote` parses remote branches with `%(refname:lstrip=3)` and reads the remote default from the `ref:` line, so the remote name is no longer listed as a branch and the default is no longer `main\tHEAD`
- `convert_local_to_remote_workflow` offers `sync_with_remote` after a successful bind: after connecting to an existing remote (`origin`) and after creating a single-platform remote; cancel or skip returns to the menu
- README token instructions now point at the environment variables named by `token_var`, not at storing tokens in `platforms.conf`
- `check_local_exists` now uses `git rev-parse --git-dir` (so worktrees and submodules count) and is called by the bind workflow, which reports "not a git repository yet" instead of the false "Uncommitted changes present"
- The bind status block no longer claims "Local and remote are in sync" for a project with no remote or a branch with no upstream, and the ahead/behind comparison now matches git's tab-separated output (the old regex expected a space, so it never ran)
- Removed the unused `preview_action` helper (superseded by `execute_dangerous` dry-run output)
- `--dry-run` no longer clones in `_clone_existing_remote`; it reports the planned destination and returns without touching the network or filesystem
- `--dry-run` in the bind workflow no longer runs `rsync`/`cpio` or reaches the commit step; option 1 plans the copy, option 2 plans the clone, and both stop with the "NO CHANGES WERE MADE" banner
- `_bind_commit_changes` refuses to commit in dry-run
- Dry-run no longer prints false success lines after skipped operations in unbind, single→multi conversion, and the delete workflows

### Added
- Replaced the write-only `REMOTE_STATE.yml` with `repo-crafter.yml`, a human-owned intent manifest. Remote entries are built from `git remote -v`, so the declared `name` matches the real remote (`origin`, `github`, `github_2`, ...); this closes the open mapping item
- Manifest writes are atomic: one temporary file, validation (yq when present), `chmod 0644`, then `mv -f`. The 23 sequential `yq -i` writes are gone, and the schema is identical with or without yq
- Added `manifest_validate` (schema, duplicate names, required fields, primary role), `manifest_reconcile` (declared vs `git remote -v`: missing, extra, renamed, URL mismatch), and `manifest_migrate_legacy` (moves `REMOTE_STATE.yml` to `.git/repo-crafter/legacy/`, restores it if the new write fails)
- Menu option `10) 🧾 Project Manifest` checks, creates, migrates, or explicitly rewrites a project's manifest; the reader and reconciler never write
- Single-platform projects now receive a manifest with one remote, so bound projects have the same shape
- `parse_git_url` now preserves the owner for SSH URLs (`git@host:owner/repo.git`), which the manifest needs; existing repo-name callers are unchanged
- Unbind removes `repo-crafter.yml` and any legacy `REMOTE_STATE.yml`; `_delete_both` names both in its warning
- Removed the open manifest-key item; no open items remain under `[fix/tier0]`

### Changed
- `sync_with_remote` no longer executes `git push` anywhere. It fetches, reports ahead/behind, performs local rebase/merge only, and prints the exact command to run. This covers the new branch, identical, ahead, post-rebase, post-merge, divergent-skip, and other-local-branches cases
- After a rebase the printed command is `git push --force-with-lease`, with a warning that it rewrites the remote branch; after a merge it is a normal `git push -u`
- The divergent "skip" option now means "skip integration" and prints manual `git pull --rebase` and `git push` commands instead of force-pushing
- Push remains a deliberate user action, so a script run can no longer change a remote by accident
- `_select_project_from_dir` compares branch sets with associative arrays instead of nested loops, so the inventory is linear in the number of branches
- `warn_duplicate_remote_connections` uses `git -C` instead of `cd` in a subshell for every repository
- The bind workflow's duplicated copy and commit blocks are now `_bind_copy_files` and `_bind_commit_changes`; both bind paths share one implementation
- Version output now comes from one `SCRIPT_VERSION` constant (`1.1.2-beta`); the banner and project paths use `PROJECT_ROOT` instead of a hardcoded `$HOME/Projects`

### Removed
- `envsubst` from `required_tools`; it was declared but never used
- The unused `continue_workflow` flag in the bind workflow
- The per-project `du -sh` call in the project picker, which walked every tree just to show a size; the picker now shows only branch and remote state
- `git clone`, `git ls-remote`, `git remote add`, and `git remote set-url` now receive `--` before every URL, so an option-looking value cannot be parsed as a flag
- `_validate_git_url` rejects any value starting with `-` and only accepts `https://…`, `git@host:…`, or local filesystem paths; enforced at clone, `sync_with_remote`, `handle_existing_remote`, and the additional-remotes loop
- `validate_project_name` rejects names starting with `-` or `.`, preventing leading-dash/leading-dot option injection
- `select_platforms` validates menu input is numeric before any `$((…))` arithmetic, so malformed input no longer aborts the script under `set -e`
- The unreachable `command -v curl` branch in `gitignore_maker`; `curl` is already a required tool

## [1.1.2-beta] - 2026-02-05

### Fixed
- Fixed JSON payload corruption caused by bash brace interpretation in template defaults
- Fixed missing `Accept` header for GitHub API (required: `application/vnd.github+json`)
- Fixed hardcoded DELETE endpoint - now uses platform-specific `repo_delete_endpoint`
- Fixed unbound variable error in `urls` array handling
- Fixed manifest (`REMOTE_STATE.yml`) being created for single-platform projects
- Fixed menu prompts being captured by command substitution (now output to stderr with /dev/tty fallback)
- Fixed missing return statement causing execution continuation after errors
- Fixed syntax error in create_new_project_workflow() cancel handler
- Fixed sleep timing from 10s to 5s for better UX

### Added
- Unified `detect_platform_from_url()` helper function (replaces 3 duplicate implementations)
- Unified `extract_host_from_url()` helper function
- Conflict detection showing "Remote has X new commits" / "You have X local commits not pushed"
- Platform selection removed from test_platform_config() to avoid interactive prompts
- Added /dev/tty fallback for stdin in interactive functions

### Changed
- Improved error handling with better I/O separation
- Platform configuration now fully declarative (no hardcoded endpoints in code)
- Enhanced stdin handling in select_platforms() and _select_project_from_dir()

### Notes
- This version includes critical bug fixes for API interactions and I/O handling
- All platforms now require `accept_header` and `repo_delete_endpoint` in config

## [1.1.1-beta] - 2026-01-16

### Security
- Added comprehensive input validation to prevent command injection attacks
- Implemented project name sanitization with whitelist validation
- Added path traversal protection
- Enhanced SSH authentication timeout handling and error exit.

### Added
- Support for platform-specific authentication header names (`PLATFORM_AUTH_HEADER_NAME`)
- Support for authentication query parameters (`PLATFORM_AUTH_QUERY_PARAM`)
- Enhanced error messages with detailed debugging information
- Improved multi-platform selection with proper validation
- Added validation for numeric input in platform selection
- Better command line tool verification with optional/required tool distinction
- New workflow: Convert single-platform projects to multi-platform configuration

### Fixed
- Fixed bounds checking in multi-platform selection (used `$idx` instead of `$input`)
- Improved SSH connection test to handle GitHub's "no shell access" response (exit code 1)
- Enhanced git repository initialization with better error handling
- Fixed repository deletion endpoint to use platform-specific format instead of hardcoded GitHub style
- Improved remote repository listing workflow with proper array handling

### Changed
- Updated script size from 1,04,103 to 1,06,442 bytes (significant feature additions)
- Enhanced user interface with more descriptive error messages
- Improved safety checks across all operations

### Notes
- This version includes substantial security improvements and user experience enhancements
- Backward compatibility maintained with existing platforms.conf configuration

## [1.0.0-beta] - 2026-01-12

### Fizes
- Full revamp of api-calling, conversion workflows, etc.

### Changed
- Initial beta release with basic GitHub and GitLab platform support
- Initial version branding as v1.0.0-beta

## [0.1.1-beta] - 2026-01-11

### Fixed
- Various bug fixes and improvements

## [0.1.0-beta] - 2026-01-11

Initial beta release with core functionality.

---

This changelog follows Semantic Versioning guidelines for beta releases.

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

### Open (found, not fixed)
- `sync_with_remote` has no caller after the unreachable duplicate block was removed (integration pending)
- `work_dir` from `platforms.conf` is used in paths without validation
- `check_ssh_auth` passes `ssh_host` into `bash -c`, so config content can run commands
- Cancelling several interactive prompts returns non-zero and exits the script under `set -e`
- `warn_duplicate_repo_name` has no caller yet (integration pending)
- `warn_duplicate_remote_connections` returns 1 when duplicates exist, and both call sites are bare, so duplicates exit the script under `set -e`

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

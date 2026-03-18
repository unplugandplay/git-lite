# git-lite

A Git-like version control system backed by SQLite, built with mruby.

> Portable, single-binary VCS. No Ruby runtime required — compiles to mruby bitcode or a standalone native binary.

## Why git-lite?

**No server required.** Uses a single SQLite file for storage. Perfect for:

- Personal projects
- Embedded systems
- Quick experimentation
- Offline development

## Features

- **Git-familiar commands**: init, add, commit, log, diff, checkout, status, branch
- **SQLite storage**: Everything stored in a single `.git-lite/repo.db` file
- **Git import**: Import existing git repositories with full history
- **Compression**: zlib compression + delta compression via `gc`
- **SQL queryable**: Query your repository with SQL
- **mruby powered**: Compiles to bitcode (`.mrb`) or standalone binary — no CRuby needed

## Requirements

**Runtime (bitcode):**
- mruby 3.4+ with required gems (see `build_config.rb`)

**Build (standalone binary):**
- mruby 3.4+ source with: mruby-sqlite3, mruby-zlib, mruby-json, mruby-sha2, mruby-io, mruby-dir, mruby-dir-glob, mruby-env, mruby-errno, mruby-pack, mruby-time-strftime, mruby-stringio

## Installation

### Option 1: Run from bitcode

```bash
# Pre-compiled bitcode in release/bitcode/
mruby release/bitcode/git-lite.mrb --version
```

### Option 2: Run from source

```bash
chmod +x bin/git-lite
mruby -I lib bin/git-lite.rb --version
```

### Option 3: Compile standalone binary

```bash
# Set mruby source directory
export MRUBY_DIR=~/mruby

# Build (copies build_config.rb and compiles)
rake build
```

## Quick Start

```bash
# Initialize a new repository
git-lite init

# Configure user
git-lite config user.name "Your Name"
git-lite config user.email "you@example.com"

# Basic workflow
git-lite add .
git-lite commit -m "Initial commit"
git-lite log

# Import from git
git-lite import /path/to/git/repo --branch main

# Run garbage collection for delta compression
git-lite gc
```

## Commands

| Command | Description |
|---------|-------------|
| `init [path]` | Initialize new repository |
| `add <files>` | Stage files for commit |
| `rm <files>` | Remove files and stage deletion |
| `mv <src> <dst>` | Move/rename a file |
| `status` | Show working tree status |
| `commit -m "msg"` | Record changes |
| `log [-n N]` | Show commit history |
| `diff` | Show changes |
| `show <commit>` | Show commit details |
| `checkout <commit>` | Restore files |
| `branch [name]` | List or create branches |
| `reset` | Reset staging area |
| `import <path>` | Import from git repository |
| `clone <url> [dir]` | Clone a repository (init only) |
| `push` | Not implemented (copy .git-lite directly) |
| `pull` | Not implemented (copy .git-lite directly) |
| `remote` | Manage remotes (config only) |
| `stats` | Show repository statistics |
| `gc [--aggressive]` | Run garbage collection (delta compression) |
| `clean [-f]` | Remove untracked files |
| `sql <query>` | Run SQL queries |
| `config <key> [value]` | Get/set configuration |
| `version` | Show version |

## Build & Test

```bash
# Run all tests
rake test

# Run unit tests only
rake fast

# Run integration tests
rake integration

# Syntax check all lib files
rake lint

# Compile to bitcode
rake compile
```

## Compression

git-lite uses two levels of compression:

1. **zlib compression** - Applied during import for files > 100 bytes
2. **Delta compression** - Applied via `git-lite gc` command

Example:
```bash
# Import a git repository
git-lite import /path/to/repo --branch main

# Run garbage collection for delta compression
git-lite gc

# Check space savings
git-lite stats
```

## SQL Queries

Since everything is in SQLite, you can query directly:

```bash
# List all commits
git-lite sql "SELECT * FROM commits ORDER BY authored_at DESC LIMIT 10"

# Find most changed files
git-lite sql "SELECT path, COUNT(*) as changes FROM file_refs JOIN paths USING(path_id) GROUP BY path ORDER BY changes DESC"

# Search content
git-lite sql "SELECT p.path, c.data FROM content c JOIN paths p ON c.path_id = p.path_id WHERE CAST(c.data AS TEXT) LIKE '%TODO%'"
```

## Database Schema

### commits
- `id` (TEXT PRIMARY KEY) - ULID-like commit ID
- `parent_id` (TEXT) - Parent commit ID
- `tree_hash` (TEXT) - Hash of tree state
- `message` (TEXT) - Commit message
- `author_name`, `author_email` - Author info
- `authored_at` (TEXT ISO8601) - Author timestamp
- `committer_name`, `committer_email` - Committer info
- `committed_at` (TEXT ISO8601) - Commit timestamp

### paths
- `path_id` (INTEGER PRIMARY KEY)
- `group_id` (INTEGER) - For delta grouping
- `path` (TEXT UNIQUE) - File path

### file_refs
- `path_id` (INTEGER) - Reference to paths
- `commit_id` (TEXT) - Reference to commits
- `version_id` (INTEGER) - Version sequence
- `content_hash` (BLOB) - SHA256 hash
- `mode` (INTEGER) - File mode
- `is_symlink` (INTEGER) - Symlink flag
- `symlink_target` (TEXT) - Symlink target
- `is_binary` (INTEGER) - Binary flag

### content
- `path_id` (INTEGER) - Reference to paths
- `version_id` (INTEGER) - Version sequence
- `data` (BLOB) - File content (packed with flags byte)

### content_meta
- `path_id` (INTEGER) - Reference to paths
- `version_id` (INTEGER) - Version sequence
- `is_keyframe` (INTEGER) - 1 if keyframe, 0 if delta
- `base_version` (INTEGER) - Base version for deltas

### refs
- `name` (TEXT PRIMARY KEY) - Ref name (e.g., HEAD)
- `commit_id` (TEXT) - Commit ID

### metadata
- `key` (TEXT PRIMARY KEY)
- `value` (TEXT)

## mruby Compatibility Notes

This branch targets **mruby 3.4+** instead of CRuby. Key differences:

- No `require 'fileutils'`, `'json'`, `'digest'`, etc. — all provided by mruby gems or compatibility shims
- `mruby-sqlite3` (mattn) has a simpler API than the CRuby sqlite3 gem — wrapped via `SQLiteWrapper`
- JSON uses string keys (no `symbolize_names:`)
- Strings are byte strings — no `Encoding`, `force_encoding`, or `encode`
- `Dir.glob` replaced with recursive directory traversal
- `SecureRandom`, `FileUtils`, `Time.parse` provided by `mruby_compat.rb`
- Tests use `mruby-mtest` instead of Minitest

## Benchmarks

Importing [fzf](https://github.com/junegunn/fzf) (3,555 commits, 161 paths):

| Metric | git `gc --aggressive` | git-lite (import + gc) |
|--------|----------------------|------------------------|
| Size | 4.2 MB | 21 MB |
| Ratio | 1x | 5.0x |

Compression stages:
- Raw import: 112 MB
- After zlib: 33 MB (3.4x reduction)
- After delta GC: 21 MB (1.5x additional reduction)

## License

MIT

# git-lite

A Git-like version control system backed by SQLite.

> This is a Ruby implementation of the pgit concept, replacing PostgreSQL with SQLite for a lightweight, portable solution.

## Why git-lite?

**No server required.** Unlike pgit which requires Docker/Podman and PostgreSQL, git-lite uses a single SQLite file for storage. Perfect for:

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
- **Zero dependencies**: Just Ruby and sqlite3

## Installation

Requires:
- Ruby 2.6+ with sqlite3 gem

```bash
chmod +x bin/git-lite
./bin/git-lite --version
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

## Benchmarks

Importing [fzf](https://github.com/junegunn/fzf) (3,555 commits, 161 paths):

| Metric | git `gc --aggressive` | git-lite (import + gc) |
|--------|----------------------|------------------------|
| Size | 4.2 MB | 21 MB |
| Ratio | 1× | 5.0× |

Compression stages:
- Raw import: 112 MB
- After zlib: 33 MB (3.4× reduction)
- After delta GC: 21 MB (1.5× additional reduction)

## Comparison with pgit

| Feature | pgit | git-lite |
|---------|------|----------|
| Database | PostgreSQL + pg-xpatch | SQLite |
| Container | Docker/Podman required | None |
| Compression | Delta compression | zlib + delta |
| Remote push/pull | Full support | File-based only |
| Import from git | Yes | Yes |
| SQL queries | Yes | Yes |
| Size | Larger footprint | Single file |

## Differences from pgit

1. **Simpler compression**: zlib + delta instead of pg-xpatch
2. **No container required**: Direct SQLite file access
3. **No network remotes**: Copy `.git-lite/repo.db` directly
4. **Simplified schema**: Removed xpatch-specific tables

## License

MIT

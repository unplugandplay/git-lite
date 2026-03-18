# git-lite

A Git-like version control system backed by SQLite.

> This is an mruby implementation of the pgit concept, replacing PostgreSQL with SQLite for a lightweight, portable solution.

## Why git-lite?

**No server required.** Unlike pgit which requires Docker/Podman and PostgreSQL, git-lite uses a single SQLite file for storage. Perfect for:

- Personal projects
- Embedded systems
- Quick experimentation
- Offline development

## Features

- **Git-familiar commands**: init, add, commit, log, diff, checkout, status
- **SQLite storage**: Everything stored in a single `.git-lite/repo.db` file
- **Git import**: Import existing git repositories
- **SQL queryable**: Query your repository with SQL
- **Zero dependencies**: Just mruby and sqlite3

## Installation

Requires:
- mruby with sqlite3 gem
- Or standard Ruby with sqlite3 gem

```bash
# Using mruby
mrbc -Bgit_lite lib/git-lite.rb

# Or using standard Ruby
chmod +x bin/git-lite
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
| `log` | Show commit history |
| `diff` | Show changes |
| `show <commit>` | Show commit details |
| `checkout <commit>` | Restore files |
| `import <path>` | Import from git repository |
| `stats` | Show repository statistics |
| `sql <query>` | Run SQL queries |
| `config <key> [value]` | Get/set configuration |

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
- `content_hash` (BLOB) - BLAKE2b hash
- `mode` (INTEGER) - File mode
- `is_symlink` (INTEGER) - Symlink flag
- `symlink_target` (TEXT) - Symlink target
- `is_binary` (INTEGER) - Binary flag

### content
- `path_id` (INTEGER) - Reference to paths
- `version_id` (INTEGER) - Version sequence
- `data` (BLOB) - File content

### refs
- `name` (TEXT PRIMARY KEY) - Ref name (e.g., HEAD)
- `commit_id` (TEXT) - Commit ID

### metadata
- `key` (TEXT PRIMARY KEY)
- `value` (TEXT)

## Comparison with pgit

| Feature | pgit | git-lite |
|---------|------|----------|
| Database | PostgreSQL + pg-xpatch | SQLite |
| Container | Docker/Podman required | None |
| Compression | Delta compression | None (raw storage) |
| Remote push/pull | Full support | File-based only |
| Import from git | Yes | Yes |
| SQL queries | Yes | Yes |
| Size | Larger footprint | Single file |

## Differences from pgit

1. **No delta compression**: Content is stored as-is for simplicity
2. **No container required**: Direct SQLite file access
3. **No network remotes**: Copy `.git-lite/repo.db` directly
4. **Simplified schema**: Removed xpatch-specific tables

## License

MIT

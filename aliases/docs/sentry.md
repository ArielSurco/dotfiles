[← Back to README](../README.md)

# sentry — Sentry Issue Search

Search Sentry events by custom tags across projects with environment filtering and smart Serial Number detection.

## Commands

| Command | Description |
|---------|-------------|
| `sentry search` | Interactive search — select environment, project, tag, and view matching events |

## Quick Start

```zsh
# Launch the interactive search flow
sentry search
```

## Flow

1. **Environment** — select `production`, `staging`, or `sandbox`
2. **Project** — choose from your Sentry projects (priority projects appear first)
3. **Tag** — if the project has a `*.sn` tag, you're prompted for a Serial Number directly; otherwise, pick a tag from the list and enter a value
4. **Results** — events from the last 24 hours matching your criteria are displayed in a table with direct links

## Requirements

| Tool | Required | Install |
|------|----------|---------|
| [curl](https://curl.se/) | Yes | Included in macOS |
| [jq](https://jqlang.github.io/jq/) | Yes | `brew install jq` |
| [gum](https://github.com/charmbracelet/gum) | Yes | `brew install gum` |

### Configuration

You need a `~/.sentryclirc` file with your Sentry credentials:

```ini
[auth]
token=your-sentry-auth-token

[defaults]
url=https://your-sentry-instance.example.com
org=your-org-slug
```

## Results Format

Results are displayed as a table with the following columns:

| Column | Description |
|--------|-------------|
| EVENT ID | The unique Sentry event identifier |
| TITLE | Event title (truncated to 50 characters) |
| TIMESTAMP | When the event occurred |
| URL | Direct link to the event in Sentry |

Events are sorted by most recent first, limited to the last 24 hours (max 25 results).

## Tab Completion

The `search` subcommand is tab-completable.

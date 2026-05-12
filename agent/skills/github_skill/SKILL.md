---
name: github_skill
description: Fetch repository information from GitHub, including trending project search and repository detail lookup. Use this skill when you need GitHub project information.
---

# GitHub Skill

## Use Cases

Use this skill to fetch the following from GitHub:

- Search trending repositories by language
- Query details for a specific repository
- Get stars, forks, descriptions, and related metadata

## Steps

1. Decide the query type (search or repository detail).
2. Run `node scripts/github.js <command> [args]` from this skill directory.
3. The script returns JSON output.

## Commands

### Search Trending Repositories

```bash
node scripts/github.js search <language> [limit]
```

- `language`: language name, e.g. `elixir`, `javascript`, `python`
- `limit`: number of results to return, default is 10

### Get Repository Details

```bash
node scripts/github.js repo <owner>/<repo>
```

- `owner/repo`: full repository name, e.g. `phoenixframework/phoenix`

## Output Format

- Search: JSON array with repository name, description, stars, language, URL, etc.
- Repo detail: JSON object with full repository metadata
- Failure: error message

## Examples

```bash
# Search trending Elixir repositories
node scripts/github.js search elixir 10

# Search trending JavaScript repositories
node scripts/github.js search javascript 5

# Get Phoenix repository details
node scripts/github.js repo phoenixframework/phoenix
```

## Notes

- Uses GitHub public APIs with rate limits (60 requests/hour without auth)
- Authentication is not required for basic use
- You can configure a GitHub token in the script for higher quota

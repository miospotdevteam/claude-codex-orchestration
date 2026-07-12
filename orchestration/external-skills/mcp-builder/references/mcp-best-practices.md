# MCP Best Practices

Cross-language best practices for building production-quality MCP servers.
Read this before starting any MCP server implementation, regardless of
language choice.

---

## 1. Server Naming Conventions

- **Package name:** `mcp-server-{service}` (e.g., `mcp-server-github`,
  `mcp-server-slack`, `mcp-server-postgres`)
- **Lowercase kebab-case** for the package/directory name
- **Match the service name** — use the well-known name of the API you
  are wrapping, not your own branding

---

## 2. Tool Design

### One Tool Per API Operation

Each tool should map to a single, well-defined API operation. Do not
create "mega-tools" that accept a `mode` parameter to switch behavior.

**Good:**
```
list_issues        — List issues with optional filters
get_issue          — Get a single issue by number
create_issue       — Create a new issue
update_issue       — Update an existing issue
search_issues      — Full-text search across issues
add_issue_comment  — Add a comment to an issue
```

**Bad:**
```
manage_issues      — mode: "list" | "get" | "create" | "update" | "search"
```

### Tool Names

- Use `verb_noun` format: `list_repositories`, `create_issue`,
  `get_pull_request`, `search_code`
- Common verbs: `list`, `get`, `create`, `update`, `delete`, `search`,
  `run`, `execute`
- Keep names short but unambiguous
- Use underscores, not camelCase or kebab-case

### Tool Descriptions

Descriptions are critical — they are how the LLM decides which tool to
use and how to call it. Write descriptions as if explaining to a
competent developer who has never seen this API:

1. **What it does** — One sentence, active voice.
2. **When to use it** — Distinguish from similar tools.
3. **What it returns** — Brief description of the response format.
4. **Key constraints** — Rate limits, required permissions, pagination.

Example:
```
Search for GitHub issues and pull requests by query string. Returns up
to 30 results per page with title, number, state, author, and labels.
Use `list_issues` instead if you want all issues in a repository without
a search query. Requires `repo` scope for private repositories.
```

### Input Parameters

- Every parameter needs a `description` — not just a name and type
- Mark parameters as `required` vs `optional` explicitly
- Use enums for constrained values (e.g., `state: "open" | "closed" | "all"`)
- Provide sensible defaults for optional parameters and document them
- Use descriptive names: `repository_owner` not `owner`, `issue_number`
  not `num`

---

## 3. Response Formats

### Structured Text Over Raw JSON

LLMs process structured text much better than deeply nested JSON. Format
responses as human-readable text with clear structure:

**Good (structured text):**
```
Repository: octocat/Hello-World
Description: My first repository on GitHub!
Language: JavaScript | Stars: 1500 | Forks: 400
Default branch: main
Created: 2011-01-26 | Last pushed: 2025-01-15
Topics: javascript, github, hello-world
```

**Bad (raw JSON dump):**
```json
{"id":1296269,"node_id":"MDEwOlJlcG9zaXRvcnkxMjk2MjY5","name":"Hello-World","full_name":"octocat/Hello-World","private":false,"owner":{"login":"octocat","id":1},...}
```

### List Responses

For list operations, use numbered items with key fields:

```
Found 42 issues (showing 1-30):

1. #142: Fix authentication timeout (open)
   Author: alice | Labels: bug, auth | Created: 2025-01-15

2. #139: Add dark mode support (open)
   Author: bob | Labels: enhancement, ui | Created: 2025-01-14

...

Page 1 of 2. Use nextCursor: "abc123" to get the next page.
```

### Include Context Headers

Always start list responses with a summary line:
- "Found 42 issues (showing 1-30)"
- "3 repositories match 'react'"
- "No issues found matching 'authentication'"

This tells the LLM the total count and current page scope without
parsing the entire response.

### Markdown Formatting

Use Markdown sparingly in responses — it helps with readability:
- Bold for field names in detailed views
- Code backticks for identifiers, file paths, branch names
- Avoid tables (they consume many tokens for little benefit)
- Avoid headers (the response is already scoped to one tool call)

---

## 4. Pagination

### Cursor-Based Pagination

Implement cursor-based pagination for all list operations:

- Accept an optional `cursor` parameter (string)
- Return `nextCursor` in the response when more results exist
- Include a `hasMore` indicator (boolean or text like "Page 1 of 5")
- Default page size: 20-30 items (reasonable for LLM context windows)
- Allow overriding page size with a `limit` or `per_page` parameter

### Pagination in Response Text

End paginated responses with clear navigation guidance:

```
Showing 1-30 of 142 results.
Next page: use cursor "eyJwYWdlIjoyLCJsaW1pdCI6MzB9"
```

Or for the last page:
```
Showing 121-142 of 142 results. This is the last page.
```

---

## 5. Error Handling

### MCP Error Response Structure

When a tool encounters an error, return it in the MCP response with
`isError: true`:

```json
{
  "content": [
    {
      "type": "text",
      "text": "Error: Repository 'owner/nonexistent' not found. Verify the repository name and that your token has access to it."
    }
  ],
  "isError": true
}
```

### Error Message Guidelines

- **Be specific** — "Repository 'owner/repo' not found" not "Not found"
- **Include the input** — Echo back what was requested so the LLM can
  see what went wrong
- **Suggest remediation** — "Check that the repository name is correct"
  or "This endpoint requires admin permissions"
- **Include HTTP status codes** for API errors — they help with debugging
- **Never expose stack traces** — Internal errors should say "An internal
  error occurred" with enough context to diagnose

### Error Categories

| Category | HTTP Status | How to handle |
|----------|------------|---------------|
| Validation | N/A | Return clear message about what is wrong with the input |
| Not found | 404 | Echo back the resource identifier, suggest checking the name |
| Auth failure | 401/403 | Indicate the token may be invalid or missing required scopes |
| Rate limited | 429 | Include retry-after time if available |
| Server error | 500+ | Say the upstream API is having issues, suggest retrying |
| Network error | N/A | Indicate a connection failure, suggest checking if the service is up |

---

## 6. Transport

### stdio (Local / Claude Desktop)

- Default transport for local MCP servers
- Server reads JSON-RPC from stdin, writes to stdout
- **Never write non-protocol output to stdout** — use stderr for logging
- Ideal for: personal tools, local development, Claude Desktop integration

### Streamable HTTP (Remote / Multi-Client)

- HTTP-based transport for remote deployment
- Supports multiple concurrent clients
- Requires proper CORS and authentication headers
- Ideal for: shared team servers, cloud deployment, multi-user scenarios

### Transport Selection

| Scenario | Transport | Why |
|----------|-----------|-----|
| Local tool for one user | stdio | Simple, no HTTP setup, works with Claude Desktop |
| Team-shared server | Streamable HTTP | Multiple users, centralized deployment |
| Both local and remote | Both | Detect via CLI flag or environment variable |

Always implement stdio first — it is simpler and covers the most common
use case. Add streamable HTTP when needed for remote access.

---

## 7. Security

### Input Validation

- **Validate every parameter** against the declared schema before using it
- **Reject unexpected fields** — do not pass unknown parameters to the API
- **Sanitize strings** — escape or reject strings that could cause
  injection in downstream systems (SQL, shell commands, URLs)
- **Enforce length limits** — reject unreasonably long strings before
  they reach the API

### Output Sanitization

- **Strip sensitive data** from API responses before returning them:
  API keys, internal IDs, email addresses (unless requested), stack traces
- **Limit response size** — Truncate very long responses with a note:
  "Response truncated (showing first 5000 characters). Use more specific
  filters to narrow results."

### Authentication

- **Read tokens from environment variables** — never hardcode
- **Document required env vars** in the README with example names
- **Support multiple auth methods** if the API does (token, OAuth, API key)
- **Never log tokens** — even to stderr for debugging

### Rate Limiting

- **Implement client-side rate limiting** to protect the target API
- **Respect rate limit headers** from API responses (X-RateLimit-Remaining,
  Retry-After)
- **Queue requests** if the API has strict limits rather than failing
  immediately
- **Report rate limiting to the LLM** — "Rate limited. The API allows
  60 requests per minute. Try again in 45 seconds."

---

## 8. Tool Annotations

Tool annotations help MCP clients (like Claude Desktop) understand tool
behavior without reading the description. Set them accurately:

| Annotation | Type | When to set |
|-----------|------|-------------|
| `readOnlyHint` | boolean | `true` for tools that only read data (list, get, search) |
| `destructiveHint` | boolean | `true` for tools that delete data or have irreversible effects |
| `idempotentHint` | boolean | `true` for tools that produce the same result when called multiple times with the same input (PUT-like updates) |
| `openWorldHint` | boolean | `true` for tools that interact with external services (almost all API wrappers) |

**Default safe combination for read tools:** `readOnlyHint: true`,
`destructiveHint: false`, `idempotentHint: true`, `openWorldHint: true`

**Default for write tools:** `readOnlyHint: false`,
`destructiveHint: false`, `idempotentHint: false`, `openWorldHint: true`

**Delete tools:** `readOnlyHint: false`, `destructiveHint: true`,
`idempotentHint: true`, `openWorldHint: true`

---

## 9. Resource vs Tool Decision

MCP has two primitives for exposing data: Resources and Tools.

### Use Resources When:

- The data has a **stable URI pattern** (e.g., `repo://{owner}/{name}`)
- The operation is **read-only** with no side effects
- The LLM might want to **browse or discover** available data
- The data is **relatively static** (config files, schemas, templates)

### Use Tools When:

- The operation **requires dynamic parameters** beyond a URI
- The operation **creates side effects** (write, update, delete)
- The operation involves **search or filtering** with complex criteria
- The LLM needs **structured input validation** (schemas with types,
  required fields, enums)

### Hybrid Approach

Some entities work well as both:
- **Resource:** `repo://{owner}/{name}` — returns repository overview
- **Tool:** `get_repository` — same data but with options for including
  specific fields, stats, or related data

When in doubt, use a Tool — they are more flexible and better supported
across MCP clients.

---

## 10. README and Documentation

Every MCP server needs a README with:

1. **What it does** — One paragraph, which API it wraps, what tools it
   provides
2. **Setup** — How to install, required environment variables, example
   config
3. **Tool reference** — Table of all tools with name, description, and
   key parameters
4. **Examples** — 2-3 example prompts showing what the tools can do
5. **Claude Desktop config** — Copy-pasteable JSON for
   `claude_desktop_config.json`
6. **Development** — How to build, test, and run locally

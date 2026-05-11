---
name: mcp-builder
description: "Build production-quality MCP (Model Context Protocol) servers that expose APIs, databases, and services as tools for LLMs. Use this skill whenever the user asks for: MCP server, Model Context Protocol, building MCP tools, MCP tool integration, MCP resource provider, creating tools for Claude, tool server, LLM tool API wrapper, exposing an API as MCP tools, MCP transport setup, stdio server, streamable HTTP server, MCP Inspector testing, or any request to build a server that makes external services available to AI assistants via the Model Context Protocol. Do NOT use when: using existing MCP tools without modification, calling MCP tools from client code, non-MCP API integrations (REST/GraphQL clients), general backend development without MCP, or configuring MCP servers in claude_desktop_config.json — this skill is for building MCP servers, not consuming them."
---

# MCP Builder

Build MCP servers that wrap APIs, databases, and services into tools that
LLMs can use reliably. A well-built MCP server has clear tool boundaries,
validated inputs, structured responses optimized for LLM consumption, and
thorough error handling.

The difference between an MCP server that works and one that works well is
tool design: each tool does one thing, descriptions tell the LLM exactly
when and how to use it, responses are structured text (not raw JSON dumps),
and errors guide the LLM toward recovery rather than confusion.

**Announce at start:** "I'm using the mcp-builder skill to build this MCP
server."

---

## Prerequisites

This skill operates within the conductor's Step 1-3:

- **Phase 1** (Research) runs during Step 1 (Explore).
- **Phase 2** (Implement) runs during Step 3 (Execute).
- **Phase 3** (Review & Test) runs after implementation.
- **Phase 4** (Evaluate) runs as a final quality gate.

Read the appropriate language reference before starting implementation:
- TypeScript server: `references/mcp-typescript.md`
- Python server: `references/mcp-python.md`
- Both languages: `references/mcp-best-practices.md` (always read this)

---

## Integration with Other Skills

**With engineering-discipline:** All MCP servers are code — the standard
engineering discipline rules apply. Explore before editing, track blast
radius, verify after changes.

**With test-driven-development:** If the project uses TDD, write tool
handler tests before implementing the handlers. Mock the external API
and verify the MCP response format.

**With systematic-debugging:** When an MCP tool returns unexpected results
or the Inspector shows errors, use systematic-debugging's root cause
tracing to isolate whether the issue is in input validation, API call,
response formatting, or transport.

---

## Phase 1: Research

**Entry criteria:** User has asked to build an MCP server or wrap an API.
**Exit criteria:** You have a clear list of tools to implement, their
inputs/outputs, and which API endpoints they map to.

### Step 1.1: Understand the Target API

Before writing any code, fully understand what you are wrapping:

1. **Read the API documentation.** Identify all endpoints, their
   parameters, authentication method, rate limits, and error responses.
2. **Identify the core operations.** Group endpoints by category:
   - Read operations (list, get, search) — these become tools or resources
   - Write operations (create, update, delete) — these become tools
   - Batch operations — decide if they warrant dedicated tools
3. **Check for existing MCP servers.** Search for `mcp-server-{service}`
   on npm and PyPI. If one exists, evaluate whether it covers the needed
   operations before building from scratch.

### Step 1.2: Map API Operations to MCP Primitives

Decide what becomes a tool vs. a resource:

```
Is it read-only data retrieval with a stable URI pattern?
├── YES → Consider making it a Resource
│   ├── Does the LLM need to discover and browse it? → Resource
│   └── Does the LLM need to pass dynamic parameters? → Tool
│
└── NO (creates side effects, requires complex parameters)
    └── Make it a Tool
```

**Naming convention:** `{verb}_{noun}` — e.g., `list_issues`,
`create_comment`, `get_pull_request`, `search_repositories`.

### Step 1.3: Plan Tool Schemas

For each tool, define before writing any code:

| Field | What to specify |
|-------|----------------|
| Name | `verb_noun`, lowercase with underscores |
| Description | When to use, what it returns, any caveats |
| Input schema | Every parameter with type, description, required/optional |
| Output format | What the structured text response looks like |
| Error cases | What can go wrong, how the LLM should handle it |
| Annotations | readOnlyHint, destructiveHint, idempotentHint, openWorldHint |

See `references/mcp-best-practices.md` for annotation guidance.

---

## Phase 2: Implement

**Entry criteria:** Tool list and schemas are defined from Phase 1.
**Exit criteria:** All tools are registered, handle errors, return
structured text, and the server starts without errors.

### Step 2.1: Server Scaffolding

Choose language and set up the project:

**TypeScript:**
```bash
mkdir mcp-server-{name} && cd mcp-server-{name}
npm init -y
npm install @modelcontextprotocol/sdk zod
npm install -D typescript @types/node
npx tsc --init
```

**Python:**
```bash
mkdir mcp-server-{name} && cd mcp-server-{name}
uv init  # or: python -m venv .venv && source .venv/bin/activate
uv add mcp  # or: pip install mcp
```

See `references/mcp-typescript.md` or `references/mcp-python.md` for
complete scaffolding including tsconfig, project structure, and entry
points.

### Step 2.2: Tool Registration

Register each tool with:

1. **Clear name** — `verb_noun` pattern, matches the API operation
2. **Detailed description** — Tell the LLM when to use this tool, what
   parameters do, and what the response contains. Be specific: "Search
   for GitHub issues by query string. Returns up to 30 results with
   title, number, state, and author. Use `list_issues` instead if you
   want all issues for a repository."
3. **Input schema with validation** — Every parameter has a type and
   description. Use Zod (TypeScript) or Pydantic (Python) for validation.
   Never trust raw input.
4. **Annotations** — Set tool annotations to help clients understand
   tool behavior:
   - `readOnlyHint: true` for GET-like operations
   - `destructiveHint: true` for DELETE or irreversible operations
   - `idempotentHint: true` for PUT-like operations
   - `openWorldHint: true` if the tool accesses external services

### Step 2.3: Response Formatting

Format responses for LLM consumption, not raw API passthrough:

- **Structured text over raw JSON.** LLMs read text better than nested
  JSON. Format list results as numbered items with key fields.
- **Include context.** Add headers like "Found 42 issues (showing first
  30)" so the LLM knows there are more results.
- **Pagination metadata.** Always include `hasMore` and `nextCursor`
  (or equivalent) when results are paginated.
- **Error messages that guide.** Instead of `{"error": "404"}`, return
  "Repository 'owner/repo' not found. Check that the repository exists
  and is accessible with the current authentication."

Example response format:
```
Found 3 issues matching "bug":

1. #42: Login button not responding (open)
   Author: alice | Labels: bug, priority-high
   Created: 2025-01-15 | Comments: 5

2. #38: Dashboard data not loading (closed)
   Author: bob | Labels: bug, resolved
   Created: 2025-01-10 | Comments: 3

3. #35: Mobile layout broken on Safari (open)
   Author: carol | Labels: bug, frontend
   Created: 2025-01-08 | Comments: 2

Showing 3 of 3 results. No more pages.
```

### Step 2.4: Error Handling

Every tool handler must catch and handle errors:

1. **Input validation errors** — Return immediately with a clear message
   about what is wrong and what the correct format is.
2. **API errors** — Catch HTTP errors, translate status codes to
   human-readable messages. Include the status code for debugging.
3. **Rate limiting** — Detect 429 responses, include retry-after info
   in the error message.
4. **Authentication failures** — Detect 401/403, tell the LLM the token
   may be invalid or missing permissions.
5. **Network errors** — Catch connection failures, timeouts. Suggest the
   LLM retry or check if the service is available.

Use the `isError: true` flag in the MCP response to signal errors.

### Step 2.5: Transport Configuration

Configure at least one transport:

- **stdio** — Default for local use with Claude Desktop. The server reads
  from stdin and writes to stdout. No HTTP setup needed.
- **Streamable HTTP** — For remote deployment or multi-client scenarios.
  Runs an HTTP server on a configurable port.

Most MCP servers should support stdio at minimum. Add streamable HTTP
if the server will be deployed remotely.

See language-specific references for transport setup code.

### Step 2.6: Security

- **Validate all inputs** against the schema. Never pass raw user input
  to API calls or shell commands.
- **Sanitize outputs** — Strip sensitive data (tokens, internal IDs,
  stack traces) from responses.
- **Handle auth tokens securely** — Read from environment variables, never
  hardcode. Document required env vars.
- **Rate limiting** — Implement client-side rate limiting to avoid
  overwhelming the target API.
- **No shell injection** — If the server executes any commands, use
  parameterized execution, never string interpolation.

---

## Phase 3: Review & Test

**Entry criteria:** All tools are implemented and the server starts.
**Exit criteria:** Every tool has been tested with valid input, invalid
input, and error scenarios. MCP Inspector shows clean results.

### Step 3.1: MCP Inspector Testing

Use the MCP Inspector to verify every tool:

```bash
npx @modelcontextprotocol/inspector
```

For each tool:
1. **Valid input** — Call with correct parameters, verify response format.
2. **Missing required parameters** — Verify the error message is clear.
3. **Invalid parameter types** — Pass a string where a number is expected.
4. **Edge cases** — Empty strings, very long inputs, special characters.
5. **API error scenarios** — Invalid auth token, non-existent resource.

### Step 3.2: Manual Verification with Claude Desktop

Add the server to `claude_desktop_config.json` and test with real prompts:

```json
{
  "mcpServers": {
    "your-server": {
      "command": "node",
      "args": ["path/to/dist/index.js"],
      "env": {
        "API_TOKEN": "your-token"
      }
    }
  }
}
```

Test with prompts that exercise the tools naturally:
- "List the open issues in my repository"
- "Search for issues about authentication"
- "Create a new issue titled 'Fix login bug'"
- "What are the most recent pull requests?"

### Step 3.3: Schema Validation

Verify that all tool schemas are complete:

- Every parameter has a `description`
- Required vs optional parameters are correctly marked
- Enum values are specified where applicable
- Default values are documented

---

## Phase 4: Evaluate

**Entry criteria:** All tools pass Inspector testing and manual
verification.
**Exit criteria:** Eval prompts exercise all tools and produce
correct, well-formatted results.

### Step 4.1: Create Eval Prompts

Write 5-10 evaluation prompts that exercise the full tool surface:

1. **Single tool, happy path** — "List all repositories for user X"
2. **Single tool, edge case** — "Search for issues with an empty query"
3. **Multi-tool workflow** — "Find the most recent open issue and add a
   comment summarizing it"
4. **Error recovery** — "Get details for issue #99999 in a repo that
   doesn't exist" (should produce a clear error, not a crash)
5. **Pagination** — "List all 50+ issues in this repository" (should
   paginate correctly)

### Step 4.2: Run and Verify

For each eval prompt:
1. Run it against the MCP server via Claude
2. Verify the response is well-formatted structured text
3. Verify the LLM can interpret the response and take follow-up actions
4. Verify errors are handled gracefully

### Step 4.3: Quality Checklist

Before declaring the server complete, verify:

- [ ] All tools have clear, specific descriptions
- [ ] All input parameters are validated with schemas
- [ ] All responses use structured text, not raw JSON
- [ ] Pagination is implemented for list operations
- [ ] Errors include guidance for the LLM
- [ ] Error responses use `isError: true`
- [ ] Auth tokens are read from environment variables
- [ ] The server starts cleanly with both stdio and HTTP transports
- [ ] Tool annotations are set correctly
- [ ] README documents all tools, required env vars, and setup steps

---

## Reference Files

| Reference | When to read |
|-----------|-------------|
| `references/mcp-best-practices.md` | Always — covers naming, tool design, responses, security |
| `references/mcp-typescript.md` | Building a TypeScript MCP server |
| `references/mcp-python.md` | Building a Python MCP server |

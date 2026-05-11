# MCP TypeScript Reference

Complete reference for building MCP servers in TypeScript using the
official `@modelcontextprotocol/sdk` package. Covers server setup, tool
registration, resource handling, transports, and testing.

---

## 1. Package Setup

```bash
mkdir mcp-server-myservice && cd mcp-server-myservice
npm init -y
npm install @modelcontextprotocol/sdk zod
npm install -D typescript @types/node
```

**tsconfig.json:**
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "declaration": true
  },
  "include": ["src/**/*"]
}
```

**package.json additions:**
```json
{
  "type": "module",
  "bin": {
    "mcp-server-myservice": "./dist/index.js"
  },
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "tsc --watch"
  }
}
```

**Project structure:**
```
src/
  index.ts          # Entry point — creates server, connects transport
  server.ts         # McpServer instance and tool registration
  tools/            # One file per tool or per tool group
    list-items.ts
    get-item.ts
    create-item.ts
  api/              # API client wrapper
    client.ts       # HTTP client with auth, rate limiting
    types.ts        # API response types
  utils/
    formatting.ts   # Response formatting helpers
    errors.ts       # Error handling utilities
```

---

## 2. McpServer Class

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";

const server = new McpServer({
  name: "mcp-server-myservice",
  version: "1.0.0",
});
```

The `McpServer` class is the high-level API. It handles protocol
negotiation, capability declaration, and request routing. You register
tools and resources on this instance.

---

## 3. Registering Tools with Zod Schemas

Use `server.tool()` to register each tool. The method signature:

```typescript
server.tool(
  name: string,
  description: string,
  inputSchema: ZodObject,
  handler: (input, extra) => Promise<CallToolResult>,
  options?: { annotations?: ToolAnnotations }
)
```

### Basic Tool Registration

```typescript
import { z } from "zod";

server.tool(
  "list_items",
  "List all items with optional filtering by status. Returns up to 30 items per page with title, status, and creation date. Use the cursor parameter for pagination.",
  {
    status: z.enum(["active", "archived", "all"]).optional()
      .describe("Filter by item status. Defaults to 'active'."),
    cursor: z.string().optional()
      .describe("Pagination cursor from a previous response."),
    limit: z.number().min(1).max(100).optional()
      .describe("Number of items per page. Defaults to 30, max 100."),
  },
  async ({ status = "active", cursor, limit = 30 }) => {
    const result = await apiClient.listItems({ status, cursor, limit });

    const lines = result.items.map((item, i) => {
      const idx = (result.offset || 0) + i + 1;
      return `${idx}. ${item.title} (${item.status})\n   ID: ${item.id} | Created: ${item.createdAt}`;
    });

    let footer = `\nShowing ${result.items.length} of ${result.total} items.`;
    if (result.nextCursor) {
      footer += `\nNext page: use cursor "${result.nextCursor}"`;
    } else {
      footer += "\nThis is the last page.";
    }

    return {
      content: [{ type: "text", text: lines.join("\n\n") + footer }],
    };
  },
  {
    annotations: {
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: true,
    },
  }
);
```

### Tool with Error Handling

```typescript
server.tool(
  "get_item",
  "Get detailed information about a single item by ID. Returns the item's full details including description, tags, and activity history.",
  {
    item_id: z.string().describe("The unique identifier of the item."),
  },
  async ({ item_id }) => {
    try {
      const item = await apiClient.getItem(item_id);

      const text = [
        `**${item.title}** (${item.status})`,
        `ID: ${item.id}`,
        `Created: ${item.createdAt} by ${item.author}`,
        "",
        item.description || "(No description)",
        "",
        `Tags: ${item.tags.length > 0 ? item.tags.join(", ") : "none"}`,
        `Comments: ${item.commentCount}`,
      ].join("\n");

      return { content: [{ type: "text", text }] };
    } catch (error) {
      if (error instanceof ApiNotFoundError) {
        return {
          content: [{
            type: "text",
            text: `Item '${item_id}' not found. Check that the ID is correct and you have access to it.`,
          }],
          isError: true,
        };
      }
      if (error instanceof ApiAuthError) {
        return {
          content: [{
            type: "text",
            text: `Authentication failed. Check that your API token is valid and has the required permissions.`,
          }],
          isError: true,
        };
      }
      throw error; // Let MCP SDK handle unexpected errors
    }
  },
  {
    annotations: {
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: true,
    },
  }
);
```

### Write Tool with Destructive Annotation

```typescript
server.tool(
  "delete_item",
  "Permanently delete an item by ID. This action cannot be undone. The item and all its comments will be removed.",
  {
    item_id: z.string().describe("The unique identifier of the item to delete."),
    confirm: z.boolean().describe("Must be true to confirm deletion."),
  },
  async ({ item_id, confirm }) => {
    if (!confirm) {
      return {
        content: [{
          type: "text",
          text: "Deletion not confirmed. Set confirm to true to proceed with deleting the item.",
        }],
        isError: true,
      };
    }

    try {
      await apiClient.deleteItem(item_id);
      return {
        content: [{
          type: "text",
          text: `Item '${item_id}' has been permanently deleted.`,
        }],
      };
    } catch (error) {
      if (error instanceof ApiNotFoundError) {
        return {
          content: [{
            type: "text",
            text: `Item '${item_id}' not found. It may have already been deleted.`,
          }],
          isError: true,
        };
      }
      throw error;
    }
  },
  {
    annotations: {
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true,
    },
  }
);
```

---

## 4. Resource Registration

Resources provide read-only data with stable URI patterns:

```typescript
import { ResourceTemplate } from "@modelcontextprotocol/sdk/server/mcp.js";

// Static resource
server.resource(
  "server-info",
  "info://server",
  "Server configuration and status information",
  async () => ({
    contents: [{
      uri: "info://server",
      text: `Server: mcp-server-myservice v1.0.0\nAPI endpoint: ${API_BASE_URL}\nStatus: connected`,
      mimeType: "text/plain",
    }],
  })
);

// Dynamic resource with URI template
server.resource(
  "item-detail",
  new ResourceTemplate("items://{item_id}", { list: undefined }),
  "Detailed view of a specific item",
  async (uri, { item_id }) => {
    const item = await apiClient.getItem(item_id as string);
    return {
      contents: [{
        uri: uri.href,
        text: formatItemDetail(item),
        mimeType: "text/plain",
      }],
    };
  }
);
```

---

## 5. Transport Setup

### stdio Transport (Default)

```typescript
#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

const server = new McpServer({
  name: "mcp-server-myservice",
  version: "1.0.0",
});

// ... register tools ...

const transport = new StdioServerTransport();
await server.connect(transport);
```

Add the shebang `#!/usr/bin/env node` at the top of the entry point so
it can be executed directly. Make the file executable after building:
```bash
chmod +x dist/index.js
```

### Streamable HTTP Transport

```typescript
import express from "express";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";

const app = express();
app.use(express.json());

const server = new McpServer({
  name: "mcp-server-myservice",
  version: "1.0.0",
});

// ... register tools ...

const transport = new StreamableHTTPServerTransport({
  sessionIdGenerator: () => crypto.randomUUID(),
});

app.post("/mcp", async (req, res) => {
  await transport.handleRequest(req, res, req.body);
});

app.get("/mcp", async (req, res) => {
  await transport.handleRequest(req, res);
});

app.delete("/mcp", async (req, res) => {
  await transport.handleRequest(req, res);
});

await server.connect(transport);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.error(`MCP server listening on port ${PORT}`);
});
```

### Dual Transport (CLI Flag)

```typescript
#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

const server = createServer(); // Your server creation function

const transportArg = process.argv[2];

if (transportArg === "--http") {
  const { default: express } = await import("express");
  const { StreamableHTTPServerTransport } = await import(
    "@modelcontextprotocol/sdk/server/streamableHttp.js"
  );

  const app = express();
  app.use(express.json());

  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: () => crypto.randomUUID(),
  });

  app.post("/mcp", async (req, res) => {
    await transport.handleRequest(req, res, req.body);
  });
  app.get("/mcp", async (req, res) => {
    await transport.handleRequest(req, res);
  });
  app.delete("/mcp", async (req, res) => {
    await transport.handleRequest(req, res);
  });

  await server.connect(transport);

  const port = parseInt(process.env.PORT || "3000", 10);
  app.listen(port, () => {
    console.error(`MCP HTTP server on port ${port}`);
  });
} else {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}
```

---

## 6. API Client Pattern

Wrap the target API in a typed client class:

```typescript
// src/api/client.ts

interface ApiClientOptions {
  baseUrl: string;
  token: string;
  maxRequestsPerMinute?: number;
}

export class ApiClient {
  private baseUrl: string;
  private token: string;
  private requestCount = 0;
  private resetTime = Date.now();
  private maxRpm: number;

  constructor(options: ApiClientOptions) {
    this.baseUrl = options.baseUrl;
    this.token = options.token;
    this.maxRpm = options.maxRequestsPerMinute ?? 60;
  }

  private async throttle(): Promise<void> {
    const now = Date.now();
    if (now > this.resetTime + 60_000) {
      this.requestCount = 0;
      this.resetTime = now;
    }
    if (this.requestCount >= this.maxRpm) {
      const waitMs = this.resetTime + 60_000 - now;
      await new Promise((resolve) => setTimeout(resolve, waitMs));
      this.requestCount = 0;
      this.resetTime = Date.now();
    }
    this.requestCount++;
  }

  private async request<T>(path: string, options: RequestInit = {}): Promise<T> {
    await this.throttle();

    const url = `${this.baseUrl}${path}`;
    const response = await fetch(url, {
      ...options,
      headers: {
        "Authorization": `Bearer ${this.token}`,
        "Content-Type": "application/json",
        ...options.headers,
      },
    });

    if (!response.ok) {
      const body = await response.text().catch(() => "");
      if (response.status === 404) throw new ApiNotFoundError(path, body);
      if (response.status === 401 || response.status === 403) {
        throw new ApiAuthError(response.status, body);
      }
      if (response.status === 429) {
        const retryAfter = response.headers.get("Retry-After");
        throw new ApiRateLimitError(retryAfter);
      }
      throw new ApiError(response.status, body);
    }

    return response.json() as Promise<T>;
  }

  async listItems(params: {
    status?: string;
    cursor?: string;
    limit?: number;
  }) {
    const query = new URLSearchParams();
    if (params.status) query.set("status", params.status);
    if (params.cursor) query.set("cursor", params.cursor);
    if (params.limit) query.set("limit", String(params.limit));
    return this.request<ListItemsResponse>(`/items?${query}`);
  }

  async getItem(id: string) {
    return this.request<Item>(`/items/${encodeURIComponent(id)}`);
  }

  async createItem(data: CreateItemInput) {
    return this.request<Item>("/items", {
      method: "POST",
      body: JSON.stringify(data),
    });
  }

  async deleteItem(id: string) {
    return this.request<void>(`/items/${encodeURIComponent(id)}`, {
      method: "DELETE",
    });
  }
}
```

### Custom Error Classes

```typescript
// src/api/errors.ts

export class ApiError extends Error {
  constructor(public status: number, public body: string) {
    super(`API error ${status}: ${body}`);
    this.name = "ApiError";
  }
}

export class ApiNotFoundError extends ApiError {
  constructor(path: string, body: string) {
    super(404, body);
    this.name = "ApiNotFoundError";
    this.message = `Resource not found: ${path}`;
  }
}

export class ApiAuthError extends ApiError {
  constructor(status: number, body: string) {
    super(status, body);
    this.name = "ApiAuthError";
    this.message = `Authentication failed (${status}): ${body}`;
  }
}

export class ApiRateLimitError extends ApiError {
  public retryAfter: string | null;
  constructor(retryAfter: string | null) {
    super(429, "Rate limited");
    this.name = "ApiRateLimitError";
    this.retryAfter = retryAfter;
    this.message = retryAfter
      ? `Rate limited. Retry after ${retryAfter} seconds.`
      : "Rate limited. Try again later.";
  }
}
```

---

## 7. Testing with MCP Inspector

The MCP Inspector provides a web UI for testing your server interactively:

```bash
npx @modelcontextprotocol/inspector
```

This opens a browser UI where you can:
1. Connect to your server via stdio or HTTP
2. List all registered tools and resources
3. Call tools with custom inputs
4. View raw protocol messages
5. Verify response formats

### Automated Testing

For CI/CD, use the MCP SDK's client to test programmatically:

```typescript
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";

// Create linked in-memory transports
const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();

// Connect server
const server = createServer();
await server.connect(serverTransport);

// Connect client
const client = new Client({ name: "test-client", version: "1.0.0" });
await client.connect(clientTransport);

// Test a tool
const result = await client.callTool({
  name: "list_items",
  arguments: { status: "active" },
});

// Assert on result
assert(result.content[0].type === "text");
assert(result.content[0].text.includes("Found"));
assert(!result.isError);
```

---

## 8. Quality Checklist

Before shipping a TypeScript MCP server, verify:

### Tool Quality
- [ ] Every tool has a detailed description (not just a name)
- [ ] All input parameters use Zod schemas with `.describe()` on each field
- [ ] Required vs optional parameters are correct
- [ ] Enum values are used where inputs are constrained
- [ ] Tool annotations (readOnlyHint, destructiveHint, etc.) are set

### Response Quality
- [ ] Responses use structured text, not raw JSON
- [ ] List responses include a count/summary header
- [ ] Pagination includes nextCursor and hasMore indicators
- [ ] Very long responses are truncated with a note

### Error Handling
- [ ] Every tool handler is wrapped in try/catch
- [ ] API errors are caught and translated to helpful messages
- [ ] Error responses use `isError: true`
- [ ] Auth errors, not-found errors, and rate limits have distinct messages
- [ ] Unexpected errors are re-thrown (not swallowed)

### Security
- [ ] API tokens read from `process.env`, never hardcoded
- [ ] All string inputs are validated/sanitized before use in URLs or queries
- [ ] No sensitive data in responses (tokens, internal IDs, stack traces)
- [ ] Rate limiting is implemented in the API client

### Infrastructure
- [ ] `package.json` has correct `bin` field for CLI usage
- [ ] Entry point has `#!/usr/bin/env node` shebang
- [ ] TypeScript compiles cleanly with strict mode
- [ ] Both stdio and HTTP transports work (if both are implemented)
- [ ] README documents all tools, env vars, and setup

---

## 9. Examples

### Minimal Echo Server

A complete, working MCP server in one file:

```typescript
#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({
  name: "mcp-server-echo",
  version: "1.0.0",
});

server.tool(
  "echo",
  "Echo back the provided message. Useful for testing MCP connectivity.",
  {
    message: z.string().describe("The message to echo back."),
  },
  async ({ message }) => ({
    content: [{ type: "text", text: `Echo: ${message}` }],
  })
);

const transport = new StdioServerTransport();
await server.connect(transport);
```

### Complete API Wrapper Pattern

A production-quality server wrapping a hypothetical task management API:

```typescript
#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const API_BASE = process.env.TASKS_API_URL || "https://api.tasks.example.com";
const API_TOKEN = process.env.TASKS_API_TOKEN;

if (!API_TOKEN) {
  console.error("Error: TASKS_API_TOKEN environment variable is required.");
  process.exit(1);
}

const server = new McpServer({
  name: "mcp-server-tasks",
  version: "1.0.0",
});

// --- Helper: API request with error handling ---

async function apiRequest<T>(
  path: string,
  options: RequestInit = {}
): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${API_TOKEN}`,
      "Content-Type": "application/json",
      ...options.headers,
    },
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw { status: response.status, body };
  }

  return response.json() as Promise<T>;
}

function apiErrorMessage(error: unknown, context: string): string {
  if (typeof error === "object" && error !== null && "status" in error) {
    const err = error as { status: number; body: string };
    switch (err.status) {
      case 404:
        return `${context} not found. Check that the identifier is correct.`;
      case 401:
      case 403:
        return `Authentication failed. Check that TASKS_API_TOKEN is valid and has the required permissions.`;
      case 429:
        return `Rate limited by the Tasks API. Wait a moment and try again.`;
      default:
        return `Tasks API error (${err.status}): ${err.body || "Unknown error"}`;
    }
  }
  return `Unexpected error: ${String(error)}`;
}

// --- Tools ---

server.tool(
  "list_tasks",
  "List tasks with optional filtering by status and assignee. Returns up to 30 tasks per page with title, status, assignee, and due date.",
  {
    status: z.enum(["todo", "in_progress", "done", "all"]).optional()
      .describe("Filter by task status. Defaults to 'all'."),
    assignee: z.string().optional()
      .describe("Filter by assignee username."),
    cursor: z.string().optional()
      .describe("Pagination cursor from a previous response."),
  },
  async ({ status, assignee, cursor }) => {
    try {
      const params = new URLSearchParams();
      if (status && status !== "all") params.set("status", status);
      if (assignee) params.set("assignee", assignee);
      if (cursor) params.set("cursor", cursor);

      const result = await apiRequest<{
        tasks: Array<{
          id: string;
          title: string;
          status: string;
          assignee: string;
          dueDate: string | null;
        }>;
        total: number;
        nextCursor: string | null;
      }>(`/tasks?${params}`);

      if (result.tasks.length === 0) {
        return {
          content: [{
            type: "text",
            text: "No tasks found matching the specified filters.",
          }],
        };
      }

      const lines = result.tasks.map((task, i) => {
        const due = task.dueDate ? ` | Due: ${task.dueDate}` : "";
        return `${i + 1}. ${task.title} (${task.status})\n   ID: ${task.id} | Assignee: ${task.assignee}${due}`;
      });

      let text = `Found ${result.total} tasks (showing ${result.tasks.length}):\n\n`;
      text += lines.join("\n\n");

      if (result.nextCursor) {
        text += `\n\nMore results available. Use cursor: "${result.nextCursor}"`;
      }

      return { content: [{ type: "text", text }] };
    } catch (error) {
      return {
        content: [{ type: "text", text: apiErrorMessage(error, "Tasks") }],
        isError: true,
      };
    }
  },
  {
    annotations: {
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: true,
    },
  }
);

server.tool(
  "create_task",
  "Create a new task with a title, optional description, and optional assignee. Returns the created task's details including its generated ID.",
  {
    title: z.string().min(1).max(200)
      .describe("Task title. Required, 1-200 characters."),
    description: z.string().max(5000).optional()
      .describe("Task description. Optional, max 5000 characters."),
    assignee: z.string().optional()
      .describe("Username to assign the task to."),
    due_date: z.string().optional()
      .describe("Due date in YYYY-MM-DD format."),
  },
  async ({ title, description, assignee, due_date }) => {
    try {
      const task = await apiRequest<{
        id: string;
        title: string;
        status: string;
        assignee: string | null;
        dueDate: string | null;
        createdAt: string;
      }>("/tasks", {
        method: "POST",
        body: JSON.stringify({
          title,
          description,
          assignee,
          dueDate: due_date,
        }),
      });

      const text = [
        `Task created successfully.`,
        ``,
        `ID: ${task.id}`,
        `Title: ${task.title}`,
        `Status: ${task.status}`,
        task.assignee ? `Assignee: ${task.assignee}` : "Assignee: unassigned",
        task.dueDate ? `Due: ${task.dueDate}` : "Due: not set",
        `Created: ${task.createdAt}`,
      ].join("\n");

      return { content: [{ type: "text", text }] };
    } catch (error) {
      return {
        content: [{ type: "text", text: apiErrorMessage(error, "Task creation") }],
        isError: true,
      };
    }
  },
  {
    annotations: {
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: true,
    },
  }
);

// --- Start server ---

const transport = new StdioServerTransport();
await server.connect(transport);
```

# MCP Python Reference

Complete reference for building MCP servers in Python using the official
`mcp` package (PyPI). Covers FastMCP server creation, tool decorators,
Pydantic validation, resource handling, transports, and testing.

---

## 1. Package Setup

```bash
mkdir mcp-server-myservice && cd mcp-server-myservice

# Using uv (recommended)
uv init
uv add mcp

# Or using pip
python -m venv .venv
source .venv/bin/activate  # Linux/macOS
pip install mcp
```

For HTTP transport, also install the HTTP dependencies:
```bash
uv add "mcp[cli]"  # Includes Starlette and uvicorn
# or: pip install "mcp[cli]"
```

**Project structure:**
```
mcp-server-myservice/
  __init__.py
  server.py           # FastMCP instance and tool definitions
  main.py             # Entry point
  api/
    __init__.py
    client.py          # API client with auth and rate limiting
    types.py           # Pydantic models for API responses
  utils/
    __init__.py
    formatting.py      # Response formatting helpers
    errors.py          # Error handling utilities
  pyproject.toml
```

**pyproject.toml:**
```toml
[project]
name = "mcp-server-myservice"
version = "1.0.0"
description = "MCP server for MyService API"
requires-python = ">=3.10"
dependencies = [
    "mcp",
]

[project.scripts]
mcp-server-myservice = "mcp_server_myservice.main:main"
```

---

## 2. FastMCP Class

FastMCP is the high-level API for building MCP servers in Python. It
handles protocol negotiation, tool/resource registration, and transport:

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP(
    name="mcp-server-myservice",
)
```

---

## 3. Tool Registration with @mcp.tool()

### Basic Tool

```python
@mcp.tool()
async def list_items(
    status: str = "active",
    cursor: str | None = None,
    limit: int = 30,
) -> str:
    """List all items with optional filtering by status.

    Returns up to 30 items per page with title, status, and creation date.
    Use the cursor parameter for pagination.

    Args:
        status: Filter by item status. One of: active, archived, all.
                Defaults to 'active'.
        cursor: Pagination cursor from a previous response.
        limit: Number of items per page. Defaults to 30, max 100.
    """
    result = await api_client.list_items(
        status=status, cursor=cursor, limit=min(limit, 100)
    )

    if not result.items:
        return "No items found matching the specified filters."

    lines = []
    for i, item in enumerate(result.items, start=1):
        lines.append(
            f"{i}. {item.title} ({item.status})\n"
            f"   ID: {item.id} | Created: {item.created_at}"
        )

    text = f"Found {result.total} items (showing {len(result.items)}):\n\n"
    text += "\n\n".join(lines)

    if result.next_cursor:
        text += f'\n\nMore results available. Use cursor: "{result.next_cursor}"'

    return text
```

The `@mcp.tool()` decorator registers the function as an MCP tool.
FastMCP infers the tool name from the function name and the input
schema from the function signature and docstring.

### Pydantic Models for Complex Inputs

For tools with complex or validated inputs, use Pydantic BaseModel:

```python
from pydantic import BaseModel, Field


class CreateItemInput(BaseModel):
    """Create a new item."""

    title: str = Field(
        ...,
        min_length=1,
        max_length=200,
        description="Item title. Required, 1-200 characters.",
    )
    description: str | None = Field(
        None,
        max_length=5000,
        description="Item description. Optional, max 5000 characters.",
    )
    assignee: str | None = Field(
        None,
        description="Username to assign the item to.",
    )
    tags: list[str] = Field(
        default_factory=list,
        description="Tags to apply to the item.",
    )


@mcp.tool()
async def create_item(input: CreateItemInput) -> str:
    """Create a new item with a title, optional description, assignee, and tags.

    Returns the created item's details including its generated ID.
    """
    item = await api_client.create_item(
        title=input.title,
        description=input.description,
        assignee=input.assignee,
        tags=input.tags,
    )

    return (
        f"Item created successfully.\n\n"
        f"ID: {item.id}\n"
        f"Title: {item.title}\n"
        f"Status: {item.status}\n"
        f"Assignee: {item.assignee or 'unassigned'}\n"
        f"Tags: {', '.join(item.tags) if item.tags else 'none'}\n"
        f"Created: {item.created_at}"
    )
```

### Tool with Error Handling

```python
from mcp.server.fastmcp import Context


@mcp.tool()
async def get_item(item_id: str, ctx: Context) -> str:
    """Get detailed information about a single item by ID.

    Returns the item's full details including description, tags, and
    activity history.

    Args:
        item_id: The unique identifier of the item.
    """
    try:
        item = await api_client.get_item(item_id)
    except ApiNotFoundError:
        raise ValueError(
            f"Item '{item_id}' not found. Check that the ID is correct "
            f"and you have access to it."
        )
    except ApiAuthError:
        raise ValueError(
            "Authentication failed. Check that your API token is valid "
            "and has the required permissions."
        )

    lines = [
        f"**{item.title}** ({item.status})",
        f"ID: {item.id}",
        f"Created: {item.created_at} by {item.author}",
        "",
        item.description or "(No description)",
        "",
        f"Tags: {', '.join(item.tags) if item.tags else 'none'}",
        f"Comments: {item.comment_count}",
    ]

    return "\n".join(lines)
```

When a tool raises a `ValueError` or returns an error string, FastMCP
automatically converts it to an MCP error response with `isError: true`.

### Explicit Error Responses

For more control over error responses, return a list of content items
or raise specific exceptions:

```python
from mcp.types import TextContent


@mcp.tool()
async def delete_item(item_id: str, confirm: bool) -> str:
    """Permanently delete an item by ID. This action cannot be undone.

    Args:
        item_id: The unique identifier of the item to delete.
        confirm: Must be True to confirm deletion.
    """
    if not confirm:
        raise ValueError(
            "Deletion not confirmed. Set confirm to True to proceed "
            "with deleting the item."
        )

    try:
        await api_client.delete_item(item_id)
        return f"Item '{item_id}' has been permanently deleted."
    except ApiNotFoundError:
        raise ValueError(
            f"Item '{item_id}' not found. It may have already been deleted."
        )
```

---

## 4. Resource Registration

Resources provide read-only data with URI patterns:

```python
@mcp.resource("info://server")
async def server_info() -> str:
    """Server configuration and status information."""
    return (
        f"Server: mcp-server-myservice v1.0.0\n"
        f"API endpoint: {API_BASE_URL}\n"
        f"Status: connected"
    )


@mcp.resource("items://{item_id}")
async def item_detail(item_id: str) -> str:
    """Detailed view of a specific item."""
    item = await api_client.get_item(item_id)
    return format_item_detail(item)
```

---

## 5. Transport Setup

### stdio Transport (Default)

The default transport. Use this for Claude Desktop integration:

```python
# main.py
from mcp_server_myservice.server import mcp


def main():
    mcp.run()  # Defaults to stdio transport


if __name__ == "__main__":
    main()
```

Or from the command line:
```bash
python -m mcp_server_myservice.main
# or if using project.scripts:
mcp-server-myservice
```

### Streamable HTTP Transport

For remote deployment with HTTP:

```python
# main.py
import argparse
from mcp_server_myservice.server import mcp


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--transport",
        choices=["stdio", "streamable-http"],
        default="stdio",
        help="Transport type (default: stdio)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=3000,
        help="Port for HTTP transport (default: 3000)",
    )
    args = parser.parse_args()

    if args.transport == "streamable-http":
        mcp.run(
            transport="streamable-http",
            host="0.0.0.0",
            port=args.port,
        )
    else:
        mcp.run()  # stdio


if __name__ == "__main__":
    main()
```

### Manual Starlette Setup (Advanced)

For full control over the HTTP server:

```python
from starlette.applications import Starlette
from starlette.routing import Mount
from mcp.server.streamable_http import StreamableHTTPServerTransport
import uvicorn

from mcp_server_myservice.server import mcp


async def create_app():
    transport = StreamableHTTPServerTransport(
        mcp_session_id_generator=lambda: str(uuid.uuid4()),
    )
    server = mcp._mcp_server  # Access the underlying low-level server

    app = Starlette(
        routes=[
            Mount("/mcp", app=transport.handle_request),
        ],
    )

    await server.connect(transport)
    return app


app = create_app()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=3000)
```

---

## 6. API Client Pattern

Wrap the target API in an async client class:

```python
# api/client.py
import asyncio
import os
import time
from dataclasses import dataclass, field

import httpx

from .types import Item, ListItemsResponse


API_BASE_URL = os.environ.get("MYSERVICE_API_URL", "https://api.myservice.com")
API_TOKEN = os.environ.get("MYSERVICE_API_TOKEN", "")


class ApiError(Exception):
    def __init__(self, status: int, body: str):
        self.status = status
        self.body = body
        super().__init__(f"API error {status}: {body}")


class ApiNotFoundError(ApiError):
    def __init__(self, path: str, body: str = ""):
        super().__init__(404, body)
        self.path = path
        self.message = f"Resource not found: {path}"


class ApiAuthError(ApiError):
    def __init__(self, status: int, body: str = ""):
        super().__init__(status, body)
        self.message = f"Authentication failed ({status})"


class ApiRateLimitError(ApiError):
    def __init__(self, retry_after: str | None = None):
        super().__init__(429, "Rate limited")
        self.retry_after = retry_after


@dataclass
class ApiClient:
    base_url: str = field(default_factory=lambda: API_BASE_URL)
    token: str = field(default_factory=lambda: API_TOKEN)
    max_rpm: int = 60
    _request_count: int = field(default=0, init=False, repr=False)
    _reset_time: float = field(default_factory=time.time, init=False, repr=False)
    _client: httpx.AsyncClient | None = field(default=None, init=False, repr=False)

    @property
    def client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                base_url=self.base_url,
                headers={
                    "Authorization": f"Bearer {self.token}",
                    "Content-Type": "application/json",
                },
                timeout=30.0,
            )
        return self._client

    async def _throttle(self) -> None:
        now = time.time()
        if now > self._reset_time + 60:
            self._request_count = 0
            self._reset_time = now
        if self._request_count >= self.max_rpm:
            wait = self._reset_time + 60 - now
            await asyncio.sleep(wait)
            self._request_count = 0
            self._reset_time = time.time()
        self._request_count += 1

    async def _request(self, method: str, path: str, **kwargs) -> httpx.Response:
        await self._throttle()
        response = await self.client.request(method, path, **kwargs)

        if response.status_code == 404:
            raise ApiNotFoundError(path, response.text)
        if response.status_code in (401, 403):
            raise ApiAuthError(response.status_code, response.text)
        if response.status_code == 429:
            retry_after = response.headers.get("Retry-After")
            raise ApiRateLimitError(retry_after)
        if not response.is_success:
            raise ApiError(response.status_code, response.text)

        return response

    async def list_items(
        self,
        status: str = "active",
        cursor: str | None = None,
        limit: int = 30,
    ) -> ListItemsResponse:
        params = {"status": status, "limit": limit}
        if cursor:
            params["cursor"] = cursor
        response = await self._request("GET", "/items", params=params)
        return ListItemsResponse(**response.json())

    async def get_item(self, item_id: str) -> Item:
        response = await self._request("GET", f"/items/{item_id}")
        return Item(**response.json())

    async def create_item(self, **data) -> Item:
        response = await self._request("POST", "/items", json=data)
        return Item(**response.json())

    async def delete_item(self, item_id: str) -> None:
        await self._request("DELETE", f"/items/{item_id}")
```

### Pydantic Models for API Types

```python
# api/types.py
from pydantic import BaseModel


class Item(BaseModel):
    id: str
    title: str
    status: str
    description: str | None = None
    author: str
    assignee: str | None = None
    tags: list[str] = []
    comment_count: int = 0
    created_at: str
    updated_at: str | None = None


class ListItemsResponse(BaseModel):
    items: list[Item]
    total: int
    next_cursor: str | None = None
```

---

## 7. Testing with MCP Inspector

The MCP Inspector provides a web UI for interactive testing:

```bash
npx @modelcontextprotocol/inspector
```

Configure the Inspector to run your Python server:
- Command: `python` (or `uv run python`)
- Arguments: `-m mcp_server_myservice.main`
- Environment variables: Set your API tokens

### Automated Testing with pytest

```python
# tests/test_tools.py
import pytest
from unittest.mock import AsyncMock, patch

from mcp.server.fastmcp import FastMCP


@pytest.fixture
def mcp_server():
    """Create a fresh MCP server for testing."""
    # Import your server module which registers tools on the global mcp instance
    from mcp_server_myservice.server import mcp
    return mcp


@pytest.mark.asyncio
async def test_list_items_empty(mcp_server):
    """Test list_items with no results."""
    with patch("mcp_server_myservice.server.api_client") as mock_client:
        mock_client.list_items = AsyncMock(
            return_value=ListItemsResponse(items=[], total=0)
        )

        # Call the tool function directly
        result = await mcp_server.call_tool("list_items", {"status": "active"})

        assert "No items found" in result[0].text


@pytest.mark.asyncio
async def test_list_items_with_results(mcp_server):
    """Test list_items returns formatted text."""
    mock_items = [
        Item(
            id="1",
            title="First item",
            status="active",
            author="alice",
            created_at="2025-01-15",
        ),
    ]

    with patch("mcp_server_myservice.server.api_client") as mock_client:
        mock_client.list_items = AsyncMock(
            return_value=ListItemsResponse(
                items=mock_items, total=1, next_cursor=None
            )
        )

        result = await mcp_server.call_tool("list_items", {"status": "active"})

        assert "Found 1 items" in result[0].text
        assert "First item" in result[0].text


@pytest.mark.asyncio
async def test_get_item_not_found(mcp_server):
    """Test get_item with non-existent ID returns error."""
    with patch("mcp_server_myservice.server.api_client") as mock_client:
        mock_client.get_item = AsyncMock(
            side_effect=ApiNotFoundError("/items/nonexistent")
        )

        # When a tool raises ValueError, FastMCP returns isError: true
        with pytest.raises(ValueError, match="not found"):
            await mcp_server.call_tool("get_item", {"item_id": "nonexistent"})
```

---

## 8. Quality Checklist

Before shipping a Python MCP server, verify:

### Tool Quality
- [ ] Every tool has a detailed docstring (FastMCP uses it as the description)
- [ ] All parameters have type hints and descriptions in the docstring
- [ ] Required vs optional parameters are correct (use `= None` for optional)
- [ ] Pydantic models are used for complex inputs with Field descriptions
- [ ] Tool names follow `verb_noun` convention

### Response Quality
- [ ] Responses use structured text, not raw JSON
- [ ] List responses include a count/summary header
- [ ] Pagination includes next_cursor and total count
- [ ] Very long responses are truncated with a note

### Error Handling
- [ ] Every tool handler uses try/except for API calls
- [ ] API errors are caught and re-raised as ValueError with helpful messages
- [ ] Auth errors, not-found errors, and rate limits have distinct messages
- [ ] Unexpected errors propagate naturally (not swallowed)

### Security
- [ ] API tokens read from `os.environ`, never hardcoded
- [ ] All string inputs are validated before use in URLs or queries
- [ ] No sensitive data in responses (tokens, internal IDs, stack traces)
- [ ] Rate limiting is implemented in the API client
- [ ] httpx client uses a timeout

### Infrastructure
- [ ] `pyproject.toml` has correct entry point in `[project.scripts]`
- [ ] Package installs cleanly with `pip install -e .` or `uv add -e .`
- [ ] Both stdio and HTTP transports work (if both are implemented)
- [ ] Python 3.10+ type hints are used throughout
- [ ] README documents all tools, env vars, and setup

---

## 9. Examples

### Minimal Echo Server

A complete, working MCP server in one file:

```python
# server.py
from mcp.server.fastmcp import FastMCP

mcp = FastMCP(name="mcp-server-echo")


@mcp.tool()
async def echo(message: str) -> str:
    """Echo back the provided message. Useful for testing MCP connectivity.

    Args:
        message: The message to echo back.
    """
    return f"Echo: {message}"


if __name__ == "__main__":
    mcp.run()
```

Run it:
```bash
python server.py
```

Test it:
```bash
npx @modelcontextprotocol/inspector
# Connect with command: python, args: server.py
```

### Complete API Wrapper Pattern

A production-quality server wrapping a hypothetical task management API:

```python
# server.py
import os

from mcp.server.fastmcp import FastMCP
from pydantic import BaseModel, Field

API_BASE = os.environ.get("TASKS_API_URL", "https://api.tasks.example.com")
API_TOKEN = os.environ.get("TASKS_API_TOKEN", "")

if not API_TOKEN:
    raise RuntimeError("TASKS_API_TOKEN environment variable is required.")

mcp = FastMCP(name="mcp-server-tasks")


# --- Pydantic models ---


class CreateTaskInput(BaseModel):
    """Input for creating a new task."""

    title: str = Field(
        ..., min_length=1, max_length=200,
        description="Task title. Required, 1-200 characters.",
    )
    description: str | None = Field(
        None, max_length=5000,
        description="Task description. Optional, max 5000 characters.",
    )
    assignee: str | None = Field(
        None,
        description="Username to assign the task to.",
    )
    due_date: str | None = Field(
        None,
        description="Due date in YYYY-MM-DD format.",
    )


# --- API client (simplified for example) ---

import httpx

client = httpx.AsyncClient(
    base_url=API_BASE,
    headers={"Authorization": f"Bearer {API_TOKEN}"},
    timeout=30.0,
)


async def api_get(path: str, params: dict | None = None) -> dict:
    response = await client.get(path, params=params)
    if response.status_code == 404:
        raise ValueError(f"Resource not found: {path}")
    if response.status_code in (401, 403):
        raise ValueError("Authentication failed. Check TASKS_API_TOKEN.")
    if response.status_code == 429:
        raise ValueError("Rate limited. Wait and try again.")
    response.raise_for_status()
    return response.json()


async def api_post(path: str, data: dict) -> dict:
    response = await client.post(path, json=data)
    if response.status_code in (401, 403):
        raise ValueError("Authentication failed. Check TASKS_API_TOKEN.")
    response.raise_for_status()
    return response.json()


# --- Tools ---


@mcp.tool()
async def list_tasks(
    status: str = "all",
    assignee: str | None = None,
    cursor: str | None = None,
) -> str:
    """List tasks with optional filtering by status and assignee.

    Returns up to 30 tasks per page with title, status, assignee,
    and due date.

    Args:
        status: Filter by task status. One of: todo, in_progress, done, all.
                Defaults to 'all'.
        assignee: Filter by assignee username.
        cursor: Pagination cursor from a previous response.
    """
    params = {}
    if status != "all":
        params["status"] = status
    if assignee:
        params["assignee"] = assignee
    if cursor:
        params["cursor"] = cursor

    result = await api_get("/tasks", params=params)
    tasks = result.get("tasks", [])
    total = result.get("total", len(tasks))
    next_cursor = result.get("nextCursor")

    if not tasks:
        return "No tasks found matching the specified filters."

    lines = []
    for i, task in enumerate(tasks, start=1):
        due = f" | Due: {task['dueDate']}" if task.get("dueDate") else ""
        lines.append(
            f"{i}. {task['title']} ({task['status']})\n"
            f"   ID: {task['id']} | Assignee: {task.get('assignee', 'unassigned')}{due}"
        )

    text = f"Found {total} tasks (showing {len(tasks)}):\n\n"
    text += "\n\n".join(lines)

    if next_cursor:
        text += f'\n\nMore results available. Use cursor: "{next_cursor}"'

    return text


@mcp.tool()
async def get_task(task_id: str) -> str:
    """Get detailed information about a single task by ID.

    Returns the task's full details including description, assignee,
    and status history.

    Args:
        task_id: The unique identifier of the task.
    """
    task = await api_get(f"/tasks/{task_id}")

    due = task.get("dueDate", "not set")
    return (
        f"**{task['title']}** ({task['status']})\n"
        f"ID: {task['id']}\n"
        f"Assignee: {task.get('assignee', 'unassigned')}\n"
        f"Due: {due}\n"
        f"Created: {task['createdAt']}\n\n"
        f"{task.get('description', '(No description)')}"
    )


@mcp.tool()
async def create_task(input: CreateTaskInput) -> str:
    """Create a new task with a title, optional description, and assignee.

    Returns the created task's details including its generated ID.
    """
    task = await api_post("/tasks", {
        "title": input.title,
        "description": input.description,
        "assignee": input.assignee,
        "dueDate": input.due_date,
    })

    return (
        f"Task created successfully.\n\n"
        f"ID: {task['id']}\n"
        f"Title: {task['title']}\n"
        f"Status: {task['status']}\n"
        f"Assignee: {task.get('assignee', 'unassigned')}\n"
        f"Due: {task.get('dueDate', 'not set')}\n"
        f"Created: {task['createdAt']}"
    )


# --- Entry point ---

if __name__ == "__main__":
    mcp.run()
```

Claude Desktop configuration:
```json
{
  "mcpServers": {
    "tasks": {
      "command": "python",
      "args": ["-m", "mcp_server_tasks.server"],
      "env": {
        "TASKS_API_TOKEN": "your-token-here"
      }
    }
  }
}
```

Or with uv:
```json
{
  "mcpServers": {
    "tasks": {
      "command": "uv",
      "args": ["run", "python", "-m", "mcp_server_tasks.server"],
      "env": {
        "TASKS_API_TOKEN": "your-token-here"
      }
    }
  }
}
```

"""Heartwood Craft JobTread MCP Server.

Wraps the JobTread PAVE API behind typed MCP tool definitions using FastMCP.
Supports stdio (default) and SSE (--sse) transports.
"""

import sys

from app import mcp

# Register all tool modules — each module decorates tools onto `mcp`
from tools import accounts  # noqa: F401, E402
from tools import budget  # noqa: F401, E402
from tools import comments  # noqa: F401, E402
from tools import contacts  # noqa: F401, E402
from tools import custom_fields  # noqa: F401, E402
from tools import daily_logs  # noqa: F401, E402
from tools import dashboards  # noqa: F401, E402
from tools import documents  # noqa: F401, E402
from tools import files  # noqa: F401, E402
from tools import jobs  # noqa: F401, E402
from tools import locations  # noqa: F401, E402
from tools import org  # noqa: F401, E402
from tools import payments  # noqa: F401, E402
from tools import tasks  # noqa: F401, E402
from tools import time_entries  # noqa: F401, E402


def main():
    if "--sse" in sys.argv:
        mcp.run(transport="sse", port=8200)
    else:
        mcp.run(transport="stdio")


if __name__ == "__main__":
    main()

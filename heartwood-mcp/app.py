"""FastMCP application instance — imported by all tool modules."""

from mcp.server.fastmcp import FastMCP

mcp = FastMCP(
    "Heartwood JobTread",
    description="JobTread PAVE API tools for Heartwood Craft LLC",
)

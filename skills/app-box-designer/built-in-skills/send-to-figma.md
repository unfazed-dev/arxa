---
name: "send-to-figma"
description: "Send to Figma\nExport as an editable Figma design"
---
# Send to Figma

Export the current design to Figma using a Figma MCP server. (This is the export direction — to **import** a local `.fig` file, see [import-from-figma.md](import-from-figma.md).)

**This requires a Figma MCP server configured in the harness** — its tools appear as `mcp__*`. If no Figma MCP tools are available in this session, tell the user that a Figma MCP server must be configured first, and stop.

This only works with static designs; if you have a deck or prototype, you will need to duplicate the file and reformat it as a horizontal scroll of fixed-size frames for each slide or screen.

## Process

1. **Identify the design file** the user wants to send (the currently open HTML file).
2. **Read the file** so you have the full content.
3. **If not static**, duplicate the file and reformat it as a horizontal scroll of fixed-size frames for each slide or screen.
4. **Call the Figma MCP export tool** (e.g. `mcp__*generate_figma_design`, exact name depends on the configured server) to export it into Figma.
   - Pass the design content / structure as the tool expects.
   - If Figma is not connected, tell the user to connect/authenticate it in their Figma MCP server configuration first.
5. The tool may ask you to embed a code snippet in the page and open it with a specific hash. Once you've embedded the snippet, serve the file over HTTP and give the user the URL **including the requested hash** (e.g. `index.html#figmacapture=…`) — the capture script only runs when the page loads in the user's browser, and the harness has no user-visible preview pane, so the user must open that URL themselves.
6. Don't sleep or poll for status — the capture runs in the user's browser, not yours, so you won't see its output. Leave the URL with the user so they can continue the flow.

## Notes

- If the tool is not available, explain that a configured Figma MCP server is required.

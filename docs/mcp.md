## vsrocq MCP server

It is possible to use the vsrocqtop as an MCP server – giving an LLM the ability to interact with Rocq on its own. The MCP server implementation uses stdio as transport type.

To run the MCP server, use the `-mcp` flag. Additionally, one also has to provide the `-coqlib` flag, which points to the Rocq library directory. (You can find your Rocq lib by running `vsrocqtop -where`).

Configuring the MCP server depends on your setup. e.g. if you want to use vsrocq mcp in VSCode, the config will look like this:

```json
// .vscode/mcp.json
{
	"servers": {
		"vsrocqmcp (or some other name)": {
			"type": "stdio",
			"command": "vsrocqtop",
			"args": [
				"-mcp",
				"-coqlib",
				"your coqlib location"
			]
		}
	}
}
```

### Available tools

| Tool | Description |
|------|-------------|
| `open_document` | Open a `.v` file for proving. Must be called before other operations. |
| `close_document` | Close a document and free resources. |
| `step_forward` | Execute the next sentence/command. |
| `step_backward` | Undo the last executed sentence. |
| `interpret_to_point` | Execute up to a specific line/character position. |
| `interpret_to_end` | Execute the entire document. |
| `get_proof_state` | Get current goals and hypotheses without executing. |
| `edit_line` | Replace entire lines (startLine to endLine, inclusive, 0-indexed) with new text. |
| `update_proof` | Re-parse the document and re-execute to the current position. Use this after applying edits externally. |
| `apply_edit` | Character-level range edit. **Warning:** LLMs are bad at counting character offsets, which leads to buffer corruption. Prefer `edit_line`. |

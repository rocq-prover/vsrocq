## vsrocq MCP server

It is possible to use the vsrocqtop as an MCP server – giving an LLM the ability to interact with Rocq on its own. The MCP server implementation uses stdio as transport type.

To run the MCP server, use the `-mcp` flag. Additionally, one also has to provide the `-coqlib` flag, which points to the Rocq library directory. (You can find your Rocq lib by running `vsrocqtop -where`).

### Setup

Configuring the MCP server depends on your setup.

#### Claude Code

```
claude mcp add --transport stdio vsrocqmcp_or_some_other_name -- vsrocqtop -mcp -coqlib your_coqlib_location
```

#### VSCode Copilot

If you want to use vsrocq mcp in VSCode (with copilot), the config will look like this:

```json
// .vscode/mcp.json
{
	"servers": {
		"vsrocqmcp_or_some_other_name": {
			"type": "stdio",
			"command": "vsrocqtop",
			"args": [
				"-mcp",
				"-coqlib",
				"your_coqlib_location"
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
| `query` | Execute a query on the document. Supported types: `search`, `print`, `locate`, `about`. Position defaults to the current proof state position. |

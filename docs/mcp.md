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

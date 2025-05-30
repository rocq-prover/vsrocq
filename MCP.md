# PoC MCP support

### How to use it

#### Installation

If there is a `.vsix` file in the root of the repository, you can install it in your VSCode instance.

Otherwise, to be able to use MCP with VsCoq, clone this repository and build the extension locally.

```
yarn run build:all && yarn run compile && yarn run package && vsce package
```

Once, you get the `.vsix` file, you can install it in your VSCode instance.

#### Enabling MCP support

Once you open a Coq project in VSCode, go to settings and enable the MCP support, by checking the `Use VsCoq MCP Server` option.

This might require resterting VsCode. (action: `Developer: Reload Window` from the command palette (Ctrl+Shift+P))

#### Starting the MCP server

An `mcp.json` file should be present in the `.vscode` folder of your project. Once you open it there should be a button to start the MCP server.

Otherwise, you can start the MCP server by running the action `MCP: List Servers` from the command palette (Ctrl+Shift+P) -> select the server you want to start -> Start Server.

#### Using the MCP server

Now the server should be running and you can use it with e.g. copilot agent mode.

*Make sure that you are using Agent Mode*

#### Tips for writing prompts

Make sure to explicitly ask the agent to use the MCP server. Specify that in order to validate the proof, it should interpret the file to the end using the MCP tools.

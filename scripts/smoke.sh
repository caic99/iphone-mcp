#!/bin/bash
# Speaks raw JSON-RPC to the binary: initialize, initialized, tools/list. Prints the tool names.
set -euo pipefail
BIN="${1:-.build/release/iphone-mcp}"
{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  sleep 2
} | "$BIN" | grep -o '"name":"[a-z_-]*"' | sort -u

# Optional host build adapters (not required for just build)

These are **build hosts** under `Tooling/HostBuild/`. They are not the OneCart product backend (CloudKit lives in `Data/CloudKit`).

## Apple xcode-tools (Cursor)

Enable the built-in Xcode MCP in Cursor. Keep Xcode open with `OneCart/OneCart.xcodeproj` for a healthy toolset.

Runtime still builds via `xcodebuild` when tools are empty or Xcode is closed.

## XcodeBuildMCP (optional)

Third-party CLI MCP for simulator workflows without Xcode UI. Never required for `just build`.

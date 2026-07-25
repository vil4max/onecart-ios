# Tooling

Engineering Runtime (ios-agent-harness). **Not** the OneCart product backend.

| Path | Role |
|------|------|
| `justfile` | Recipe definitions — imported by the root `justfile` |
| `Brewfile` | CLI deps (`just`, `swiftlint`, `swiftformat`, `xcbeautify`, …) |
| `runtime.yml` | Scheme / project / simulator / lint-format flags |
| `runtime.local.yml.example` | Copy to `runtime.local.yml` for local overrides (gitignored) |
| `runtime.manifest.json` | Declared Runtime commands / capabilities |
| `.harness-version` | Installed harness slice version |
| `.swiftformat` | SwiftFormat config |
| `.swiftlint.yml` | SwiftLint config |
| `scripts/` | Shell wrappers invoked by `just` |
| `HostBuild/` | Optional host **build adapters** (`xcodebuild`, MCP, xcode-tools) |

Product sync and sharing live in `OneCart/Data/CloudKit` (CloudKit + private `CKShare`), not here.

From the **repo root**:

```bash
brew bundle --file=Tooling/Brewfile
just doctor
just build
just test
just verify
```

Optional host adapters (xcode-tools MCP, XcodeBuildMCP): keep Xcode open with `OneCart/OneCart.xcodeproj` for a healthy toolset. Runtime still builds via `xcodebuild` when tools are empty. Never required for `just build`.

`just harness-update` refreshes this slice from `~/Developer/GitHub/ios-agent-harness`.

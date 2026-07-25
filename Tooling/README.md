# Tooling

Engineering Runtime (ios-agent-harness). **Not** the OneCart product backend.

| Path | Role |
|------|------|
| `scripts/` | `just doctor` / `build` / `test` / `verify` wrappers |
| `HostBuild/` | Host **build adapters** (`xcodebuild`, MCP, xcode-tools). Name intentionally avoids “backend” = CloudKit / API |

Product sync and sharing live in `Data/CloudKit` (CloudKit + private `CKShare`), not here.

```bash
just doctor
just build
just test
```

`just harness-update` refreshes this slice from `~/Developer/GitHub/ios-agent-harness`. After update, re-check that adapters still live under `Tooling/HostBuild` (upstream still uses the word `backend` for build hosts).

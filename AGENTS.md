# AGENTS.md — MiniMaxQuota

macOS menu-bar SwiftUI app (`LSUIElement=true`, no Dock icon) that polls the
`mmx` CLI for MiniMax token quota. Single executable SwiftPM target, no
external Swift dependencies.

## Build & run

| Task | Command | Notes |
|---|---|---|
| Local debug | `swift build` then `./bundle.sh` | Produces `./MiniMaxQuota.app` from `.build/debug/MiniMaxQuota`. `bundle.sh` errors if you forgot `swift build`. |
| Release zip | `./distribute.sh` | Produces `MiniMaxQuota-v<ver>.zip`. **Bypasses `swift build`** on purpose — uses raw `xcrun swiftc` because SwiftPM's `sandbox-exec` manifest wrapper fails in nested sandboxes. |
| Run bundled app | `open ./MiniMaxQuota.app` | Both scripts ad-hoc sign (`codesign --sign -`). No Apple Developer ID. |
| Uninstall | `./uninstall.sh` | Removes `.app` from `/Applications` and `~/Applications`. Does **not** touch `mmx` or `~/.mmx/config.json`. |

`distribute.sh` hardcodes `-target arm64-apple-macosx13.0`. If a universal/Intel
build is ever needed, this is the line to change — not `Package.swift`.

`Package.swift` deployment target is macOS 13. Don't lower it without checking
`MenuBarExtra` (13+) and other SwiftUI 4 APIs used.

## App icon

App icon lives at `Sources/MiniMaxQuota/Resources/MiniMaxQuota.icns` (programmatically
generated — see makefile at `/tmp/gen_icon.swift`). Both `bundle.sh` and `distribute.sh`
copy it into `Contents/Resources/` and set `CFBundleIconFile` in `Info.plist`.
When adding a new icon or updating the existing one, regenerate the `.icns`, update
both scripts, and update the version string in `distribute.sh`.

## Tests

**There is no SwiftPM test target.** `swift test` is a no-op / failure.
`Tests/ParseTest.swift` is a standalone smoke script — read its header:

```bash
swiftc -parse-as-library Tests/ParseTest.swift Sources/MiniMaxQuota/QuotaModel.swift -o /tmp/parsetest && /tmp/parsetest
```

It hits the **real** `mmx` CLI on the host and prints decoded quota. Requires
`mmx auth login` to have succeeded. There are no unit tests, no fixtures, no
mocks. If you add tests, add a `testTarget` to `Package.swift` first.

## Architecture (the non-obvious bits)

Three files, all under `Sources/MiniMaxQuota/`:

- `App.swift` — `@main`, `MenuBarExtra` scene, popup view.
- `QuotaModel.swift` — `ModelQuota` / `QuotaResponse` Codable, `QuotaFetcher`
  (subprocess + parsing + `mmx` discovery), `QuotaStore` (`@MainActor`
  ObservableObject + polling timer).
- `FloatingWindow.swift` — borderless always-on-top draggable card mirroring
  the popup.

### Things that will bite you

- **One `QuotaStore` instance, shared.** `App.swift` creates a single
  `sharedStore` and injects it into both the menu popup and
  `FloatingWindowController`. A prior bug introduced a separate
  `QuotaStore.shared` whose `start()` was never called, freezing the floating
  window. **Do not reintroduce a singleton or a second store.**
- **`QuotaStore.start()` is called eagerly** from the static initializer so the
  UI is never blank on first open. Calling `start()` again just re-arms the
  timer (safe).
- **`mmx` JSON is snake_case, decoded with explicit `CodingKeys`** — *not*
  `JSONDecoder.convertFromSnakeCase`, because that would lowercase the leading
  "Interval" prefix on Swift-side property names we want to keep capitalized.
  When adding a field, add its `CodingKey` mapping explicitly.
- **Timestamps are unix milliseconds** (Int64), decoded via the custom
  `dateDecodingStrategy` at the bottom of `QuotaModel.swift`. Not ISO-8601.
- **`mmx` discovery walks a hardcoded probe list** (`locateMmx()`): absolute
  Homebrew/npm paths, `~/.nvm/versions/node/*/bin`, then process `PATH`.
  `PATH` is unreliable for launchd-launched GUI apps, hence the absolute
  probes. **Don't replace this with `/usr/bin/which`** — same PATH problem.
  When adding a new install location, add an absolute path to `absoluteProbe`.
- **The CLI is invoked with `--non-interactive`.** Without it, `mmx` can prompt
  on stdin and hang the subprocess forever.
- **`video` bucket is filtered out** in `QuotaStore.refresh()` — intentional,
  not displayed. Adding new model buckets to the UI may require revisiting
  this filter.
- **`mmxMissing` is its own error case**, separate from generic fetch failures,
  so the UI can render the first-run install prompt (`InstallCommand.primary`)
  instead of a red error.

## Security / privacy contract (don't break)

The app **never reads, writes, or transmits the API key**. Auth lives entirely
in `mmx` (`~/.mmx/config.json`). All access is via spawning `mmx` as a
subprocess and parsing its stdout. The README makes this an explicit promise to
users. Do not add direct HTTP calls to the MiniMax API, do not read
`~/.mmx/config.json`, do not log stdout/stderr that might contain tokens.

## Style

Existing code uses concise, comment-heavy Swift with rationale ("why" comments
for every non-obvious decision — see `QuotaModel.swift` for the dominant
style). When adding code, keep this voice. No emoji in source. No `print()` in
release paths.

UI strings are Chinese (zh-CN). Match existing tone if you add strings.

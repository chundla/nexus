# Live Session surface baseline note — 2026-05-31

Release benchmark harness baseline captured on:
- host: `IBMMacBookski`
- macOS: `26.5 (25F71)`
- Xcode / Instruments: `16.0 (17F42)`

## Scenario fixture table

| Scenario | Surface | Loop shape |
| --- | --- | --- |
| `mac-terminal-busy` | terminal | 48 frames, 34 rows, 118 columns, 140ms step |
| `mac-structured-streaming` | structured | 18 frames, 350ms step, growing activity feed with approval + extension UI |
| `iphone-terminal-busy` | terminal | Same terminal fixture rendered through `RemoteSessionScreenView` |
| `iphone-structured-streaming` | structured | Same structured fixture rendered through `RemoteSessionScreenView` |

## macOS Time Profiler excerpts

The macOS traces were recorded with:

```bash
xcrun xctrace record \
  --template 'Time Profiler' \
  --time-limit 20s \
  --window 10s \
  --env NEXUS_BENCHMARK_SCENARIO=<scenario> \
  --output <trace-path> \
  --launch -- <Release nexus binary>
```

### `mac-terminal-busy`

| rows | leaf frame |
| ---: | --- |
| 3 | `<deduplicated_symbol>` |
| 3 | `dyld3::MachOFile::trieWalk(Diagnostics&, unsigned char const*, unsigned char const*, char const*)` |
| 2 | `_platform_strcmp_noMTE` |
| 2 | `__kdebug_trace64` |
| 2 | `__open` |
| 2 | `__close_nocancel` |
| 2 | `getMethodNoSuper_nolock(objc_class*, objc_selector*)` |
| 2 | `__bzero` |

### `mac-structured-streaming`

| rows | leaf frame |
| ---: | --- |
| 5 | `mach_msg2_trap` |
| 3 | `getMethodNoSuper_nolock(objc_class*, objc_selector*)` |
| 3 | `__open_nocancel` |
| 2 | `objc::StringHashTable::tryGetIndex(char const*) const` |
| 2 | `close` |
| 2 | `__CFStringEqual` |
| 2 | `__CFStringHash` |
| 1 | `dyld4::PrebuiltLoader::dependent(dyld4::RuntimeState const&, unsigned int, mach_o::LinkedDylibAttributes*) const` |

## SwiftUI template note

The Release benchmark harness also produces macOS `SwiftUI` template trace bundles, but the CLI exporter on this machine reported zero `swiftui-updates` rows even though the traces were recorded successfully. Keep those trace bundles for manual inspection in Instruments.app.

## iPhone Remote Client note

The iPhone benchmark scenarios launch correctly on Simulator and can be screenshotted deterministically, but CLI `xctrace` runs did not finalize reliably when targeting the simulator process on this machine. Use the recipe in `docs/performance/live-session-surface-baseline.md` to collect the iPhone `Time Profiler` and `SwiftUI` traces in Instruments.app, then attach the screenshots or short call-tree notes to issue #164.

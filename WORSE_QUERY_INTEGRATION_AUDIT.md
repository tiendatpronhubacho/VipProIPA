# TienDat — worse_query integration audit

Audit date: 2026-11-22

## Result

The supplied `TienDat_WorseQuery_Upgrade.zip` already contains a wired `worse_query` backend. No second copy of the upstream exploit source was merged, because doing so would duplicate and potentially conflict with the existing adapted implementation.

## Source alignment

- `forcequitOS/worse_query`: upstream attribution and the native backend are present under `ThreeOneOSFive/exploit/`.
- `kolbicz/WQFiles`: the TienDat implementation identifies its cache-swap recovery, marker, and open-verification helpers as adaptations from WQFiles.
- `QuinnTang74/3106`: the project follows the same backend-selection model and has the corresponding Swift access layer, app-group entitlement, and Xcode source membership.

## Existing integration points verified

- Native API: `worse_query.h` / `worse_query.m`.
- Swift bridge and backend selection: `helpers/SandboxAccess.swift`.
- Startup recovery and status: `helpers/KernelExploit.swift` and `App.swift`.
- App Group entitlement: `TienDat.entitlements`.
- Xcode source membership: `ThreeOneOSFive.xcodeproj/project.pbxproj` includes `worse_query.m` and the entitlement file.
- Regression guardrails: `Tests/run_worse_query_guardrails.sh`.
- Packaging hook: `build_esign_ready_ipa.sh` runs the guardrails before invoking Xcode.

## Verification

Command:

```sh
bash Tests/run_worse_query_guardrails.sh
```

Result: PASS — native API/recovery contracts, Swift probe/retry/diagnostics wiring, App Groups entitlement, and Xcode source membership.

## Not verified in this environment

- Xcode/iOS compilation: `xcodebuild` is not installed in this environment.
- Device runtime behavior on a physical supported iPhone/iOS build.
- Whether the eventual signing profile actually authorizes one of the App Group identifiers in `TienDat.entitlements`.

The static guardrails are source checks only; they do not establish runtime compatibility or signing authorization.


## 2026-11-22 synchronization update

The app-facing compatibility layer was previously a separate, minimal implementation: it repeated the private `container_query` exchange and cached a token under arbitrary path keys. It is now bridged to `worse_query_grant` / `worse_query_grant_ex`, so both the Swift sandbox service and WQFiles-facing APIs use the same native token cache, flag negotiation, durable cache swap/recovery, and verification logic.

Additional changes:

- Added `wq_grant_writable` for callers that need a verified write grant.
- `wq_list` now opens directories through `WQOpenDirectoryNoLinks` and enumerates from the verified descriptor.
- `wq_read` now opens only verified regular files beneath a no-symlink parent descriptor.
- Container metadata xattrs are read through a verified directory descriptor.
- Expanded static guardrails to reject a second private `container_query` implementation in the WQFiles shim.

The existing WQFiles `WQAccessSafety.h` is byte-identical to the supplied upstream file and remains the source of the descriptor-safety helpers. The native `worse_query.m` / `.h` and Swift backend were already aligned with the supplied 3106 implementation; they were not duplicated or replaced.

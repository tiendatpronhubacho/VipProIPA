# TienDat — worse_query synchronization report

Date: 2026-11-22

## What changed

1. `ThreeOneOSFive/helpers/WQCombined.m`
   - Removed the duplicate private `container_query` implementation and the per-path cache that could associate unrelated paths with one App Group token.
   - Routed `wq_app_group()` to `worse_query_app_group()`.
   - Routed `wq_grant()` to `worse_query_grant()` and added `wq_grant_writable()` using `worse_query_grant_ex(..., 1)`.
   - Reworked directory listing to enumerate from a directory descriptor opened with `WQOpenDirectoryNoLinks`.
   - Reworked file reading to use `WQOpenRegularAt` under a verified, no-symlink parent descriptor.
   - Reworked container metadata lookup to use `fgetxattr` on a verified directory descriptor.

2. `ThreeOneOSFive/WQAccess.h`
   - Exposed `wq_grant_writable()` to Objective-C and Swift callers.

3. `Tests/run_worse_query_guardrails.sh`
   - Added checks for the unified backend bridge, write verification, no-symlink directory traversal, regular-file-only reads, descriptor-based xattr access, and absence of a second private query implementation.

4. `CHANGELOG.md` and `WORSE_QUERY_INTEGRATION_AUDIT.md`
   - Recorded the synchronization and its verification limits.

## Source alignment

- `exploit/worse_query.m` and `.h` were already aligned with the supplied 3106-derived implementation, including flag negotiation, token LRU, durable Library/Caches recovery, and read/write verification. They were retained rather than copied a second time.
- `WQAccessSafety.h` in TienDat is byte-identical to the supplied WQFiles file and is reused for descriptor-safe path handling.
- The upstream worse_query and WQFiles GPL-3.0-or-later attributions remain in the source.

## Verification

- `bash Tests/run_worse_query_guardrails.sh`: PASS (all five guardrail groups).
- ZIP integrity: checked after packaging.
- Xcode build: NOT RUN; `xcodebuild` is not installed in this environment.
- Physical iPhone/iOS runtime: NOT VERIFIED.
- Entitlement signing: the source entitlement contains App Groups, but the final provisioning profile must actually authorize the configured group identifier(s).

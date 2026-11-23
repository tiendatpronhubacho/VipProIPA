#!/usr/bin/env bash
# Static regression checks for TienDat's worse_query integration.
# This script intentionally validates wiring/contracts only; it does not run
# the sandbox-exchange or kernel-exploit code.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/ThreeOneOSFive"
PROJECT="$ROOT/ThreeOneOSFive.xcodeproj/project.pbxproj"
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# Native API contract and recovery entry points.
grep -q 'worse_query_grant_ex(const char \*path, int require_write)' "$SRC/exploit/worse_query.h" || fail 'write-aware grant declaration missing'
grep -q 'worse_query_reset_access_cache(void)' "$SRC/exploit/worse_query.h" || fail 'manual cache reset declaration missing'
grep -q 'worse_query_invalidate_caches(void)' "$SRC/exploit/worse_query.h" || fail 'identity-cache invalidation declaration missing'
grep -q 'worse_query_grant_ex' "$SRC/exploit/worse_query.m" || fail 'write-aware grant implementation missing'
grep -q 'WQPathWriteProbe' "$SRC/exploit/worse_query.m" || fail 'write verification probe missing'
grep -q 'worse_query_reset_access_cache' "$SRC/exploit/worse_query.m" || fail 'cache reset implementation missing'
pass 'native API and recovery contracts'

# Swift must not report access solely because an App Group entitlement exists.
grep -q 'probeCached' "$SRC/helpers/SandboxAccess.swift" || fail 'cached real-access probe missing'
grep -q 'writable: true' "$SRC/helpers/SandboxAccess.swift" || fail 'writable grant probe missing'
grep -q 'handle == -5' "$SRC/helpers/SandboxAccess.swift" || fail 'broken-cache recovery branch missing'
grep -q 'worse_query_reset_access_cache' "$SRC/helpers/SandboxAccess.swift" || fail 'Swift cache-reset bridge missing'
grep -q 'SandboxDiagnostics.record' "$SRC/helpers/SandboxAccess.swift" || fail 'grant diagnostics recording missing'
if grep -q 'return SandboxAccess.hasAppGroup' "$SRC/helpers/KernelExploit.swift"; then
  fail 'access status regressed to entitlement-only check'
fi
pass 'Swift probe, recovery, and diagnostics wiring'

# Retry behavior and project linkage.
grep -q 'withRetry' "$SRC/helpers/GrantRetry.swift" || fail 'permission-denial retry primitive missing'
grep -q 'worse_query.m in Sources' "$PROJECT" || fail 'worse_query.m is not compiled by Xcode'
grep -q 'TienDat.entitlements' "$PROJECT" || fail 'target entitlements are not configured'
grep -q 'com.apple.security.application-groups' "$SRC/TienDat.entitlements" || fail 'App Groups entitlement key missing'
pass 'retry and Xcode project wiring'

# The app-facing WQFiles shim must use the same hardened worse_query backend.
WQ_IMPL="$SRC/helpers/WQCombined.m"
WQ_HEADER="$SRC/WQAccess.h"
grep -q 'worse_query_grant(path.fileSystemRepresentation)' "$WQ_IMPL" || fail 'WQFiles grant shim is not routed through worse_query'
grep -q 'worse_query_grant_ex(path.fileSystemRepresentation, 1)' "$WQ_IMPL" || fail 'writable grant shim is missing'
grep -q 'WQOpenDirectoryNoLinks(dir)' "$WQ_IMPL" || fail 'directory listing is not symlink-safe'
grep -q 'WQOpenRegularAt(parent, leaf.fileSystemRepresentation' "$WQ_IMPL" || fail 'file reads are not restricted to verified regular files'
grep -q 'fgetxattr(fd' "$WQ_IMPL" || fail 'container metadata is not read from a verified descriptor'
grep -q 'wq_grant_writable(NSString \*path)' "$WQ_HEADER" || fail 'writable grant API is not exposed'
if grep -q 'container_query_create' "$WQ_IMPL"; then
  fail 'duplicate private container-query implementation remains in WQCombined.m'
fi
pass 'WQFiles shim shares worse_query tokens and descriptor-safe reads'

echo 'PASS: all worse_query integration guardrails'

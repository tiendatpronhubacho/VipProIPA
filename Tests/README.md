# TienDat Worse Query guardrails

Run from the project root:

```sh
Tests/run_worse_query_guardrails.sh
```

The unsigned-IPA build script runs this suite before invoking Xcode. It checks
source-level integration contracts only: native declarations/implementations,
write verification, access-cache recovery, the Swift probe/retry path,
diagnostics recording, App Groups configuration, and Xcode source membership.

These checks do not execute the sandbox exchange, do not validate a signing
identity or entitlement authorization, and do not replace a build on macOS/Xcode
or a runtime test on a supported physical device.

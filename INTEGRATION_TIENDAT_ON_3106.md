# TIENDAT UI integration on 3106

Base: `3106-main 3(1).zip`
Source UI/assets/license: `Top1-Make 7.zip`

## Integrated in this pass
- Preserved the 3106 app entry point, sandbox/MCM/worse_query, entitlement configuration, app state, and core services. The 3106 first-run onboarding overlay is suppressed so the TIENDAT activation and home screens remain the visible entry flow.
- Added the TIENDAT tab shell, home screen, feature catalogue, settings screen, animated license backdrop, and activation screen.
- Kept the TIENDAT local Keychain activation flow as supplied.
- Bundled the three TIENDAT background images and background music.
- Bundled the nine AIM `.3105` payloads and added a first-launch copy into the 3106 PatchProjects library; the 3106 package codec remains responsible for parsing them.
- Adapted the AIM/MOD screen to open the 3106 Patch Projects manager. The old direct `applyPatch` / `restorePatch` toggle API is not present in 3106 and was not copied over.
- Kept the 3106 bundle identifier, entitlements, and sandbox implementation. Display name changed to TIENDAT.

## Not included / requires follow-up
- The five MOD entries referenced by the TIENDAT screen do not have matching `.3105` payloads in the supplied archive; they remain listed but are unavailable until those packages are provided.
- This is source integration only. An Xcode build, signing/provisioning check, and on-device regression test were not possible in this environment.
- The local LicenseManager accepts the literal key `TienDat` as in the supplied source; it is not server-side license verification and should not be treated as tamper-resistant licensing.

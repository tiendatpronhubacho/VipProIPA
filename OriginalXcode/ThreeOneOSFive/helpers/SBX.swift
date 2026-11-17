import Foundation

/// Private sandbox-extension APIs are not used by the standard iOS build.
/// Access must come from an entitlement or a user-selected security-scoped URL.
func sandbox_extension_consume(_ token: String) -> Int64? {
    _ = token
    return nil
}

func sandbox_extension_issue_file(path: String) -> String? {
    _ = path
    return nil
}

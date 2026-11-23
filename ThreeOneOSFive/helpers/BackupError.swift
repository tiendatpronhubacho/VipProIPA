import Foundation

enum BackupError: Error {
    case writeFailed(String)
    case readFailed(String)
}
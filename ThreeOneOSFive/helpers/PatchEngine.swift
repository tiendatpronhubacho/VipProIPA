import Foundation
import UIKit

class PatchEngine {
    
    static let shared = PatchEngine()
    
    // Hàm thực hiện Patch trực tiếp lên file đích trong game
    // Mày cần truyền vào đường dẫn TUYỆT ĐỐI của file trong thư mục game (nếu biết UUID)
    // Hoặc dùng hàm lấy path bên dưới.
    func applyPatchFromFile(targetFilePath: String, sourcePatchPath: String, completion: @escaping (Bool, String) -> Void) {
        
        // 1. Cấp quyền truy cập vào thư mục chứa file đích
        let targetDir = (targetFilePath as NSString).deletingLastPathComponent
        let granted = wq_grant(targetDir)
        
        if !granted {
            completion(false, "Không thể lấy quyền sandbox cho thư mục: \(targetDir). Kiểm tra App Group!")
            return
        }
        
        // 2. Dùng hàm của WQFiles để ghi đè file (nó tự động backup file cũ)
        var errorText: NSString? = nil
        let success = wq_write_from_file(targetFilePath, sourcePatchPath, &errorText)
        
        if success {
            completion(true, "Patch thành công! Hãy khởi động lại game.")
        } else {
            let errMsg = errorText as String? ?? "Lỗi không xác định"
            completion(false, "Lỗi khi ghi file patch: \(errMsg)")
        }
    }
    
    // Hàm dò tìm đường dẫn game (Dựa vào enumerate)
    // Hàm này quét thư mục Data/Application để tìm thư mục có bundle ID của game
    // Sửa lại hàm này trong PatchEngine.swift
func findGameContainerPath(bundleID: String) -> String? {
    let parentDir = "/var/mobile/Containers/Data/Application"
    
    guard let uuids = wq_list(parentDir, nil) as? [String] else {
        return nil
    }
    
    for uuid in uuids {
        let appDir = "\(parentDir)/\(uuid)"
        let plistPath = "\(appDir)/.com.apple.mobile_container_manager.metadata.plist"
        
        if let data = wq_read(plistPath, 1024 * 1024, nil) as? Data {
            if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                if let id = plist["MCMMetadataIdentifier"] as? String, id == bundleID {
                    return appDir // Trả về thư mục gốc (chứa Documents, Library, v.v.)
                }
            }
        }
    }
    return nil
}
}

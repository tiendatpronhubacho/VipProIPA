# Tích hợp Tiến Đạt → 3106

## Nguyên tắc tích hợp

- `ThreeOneOSSix.xcodeproj` và toàn bộ source Swift/Objective-C của 3106 được giữ làm project nền.
- Không thay `App.swift`, `ContentView.swift`, các view, helpers, exploit backend, entitlements hoặc Info.plist bằng bản TienDat cũ.
- Các gói patch `.3105` từ hai thư mục patch trong source Tiến Đạt được đưa vào `ThreeOneOSSix/Patches` (23 file nguồn).
- `PatchProjectLibrary` chỉ seed các gói hợp lệ vào `Application Support/PatchProjects` khi load lần đầu; không ghi đè gói người dùng đã có và bỏ qua package ID trùng.
- Thêm shared Xcode scheme `3106` và workflow Codemagic tương ứng. Không sử dụng script cũ tự tái tạo `project.pbxproj` của target `TienDat`.

## Codemagic

Có hai workflow:

1. `ios-3106-unsigned`: tạo IPA unsigned, không cần certificate/provisioning profile.
2. `ios-3106-signed`: ký Development IPA bằng certificate/profile cấu hình trong Codemagic.

Để workflow signed hoạt động, cấu hình signing asset trong Codemagic cho bundle ID `com.qingtang.3106`. Provisioning profile phải cấp đúng App Group mà ứng dụng cần; việc chỉ thêm entitlement vào file không thể thay thế quyền được profile ký cấp.

## Kiểm tra đã chạy trong môi trường đóng gói

- `plutil -lint ThreeOneOSSix.xcodeproj/project.pbxproj`: PASS.
- `swiftc -frontend -parse` cho `PatchProjectLibrary.swift`: PASS.
- `Tests/run_sandbox_static_tests.sh`: PASS.
- `Tests/check_strings_alignment.sh`: PASS (1.579 keys mỗi ngôn ngữ, đủ 4 ngôn ngữ).
- Đã kiểm tra 23 patch package: header và plist metadata hợp lệ; 22 package ID duy nhất (một ID trùng được xử lý bằng cơ chế seed chỉ nhập một lần).
- XML của shared scheme `3106.xcscheme`: PASS.

Giới hạn môi trường:
- `Tests/run_policy_tests.sh` chưa chạy hết vì môi trường Linux thiếu `/usr/libexec/PlistBuddy`.
- `Tests/run_migration_tests.sh` chưa chạy được vì Swift Linux không có module `CryptoKit`.
- Không có `xcodebuild`, nên chưa thể thực hiện build iOS, ký IPA hoặc kiểm thử trên iPhone. Cần xác nhận build thực tế bằng Codemagic.

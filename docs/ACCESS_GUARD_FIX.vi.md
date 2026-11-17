# Sửa trạng thái lỗi truy cập — 17/11/2026

## Nguyên nhân đã xác nhận

- `AppState.isSupported` luôn là `false` trong bản build hiện tại.
- `KernelExploit.hasSandboxAccess()` luôn là `false`.
- Hai file `MCMBridge.m` trong cây Swift Package và Xcode đều là stub; `MCMBridgeAvailable()` trả `NO`.
- Vì vậy `DevicePatchService` trả `containerAccessUnavailable` cho `com.garena.ffvn`. Đây là giới hạn quyền sandbox của build, không phải lỗi tải gói `.3105`.

## Thay đổi trong bản này

1. Đồng bộ `ContentView.swift` ở `Sources/TienDatApp` và `OriginalXcode/ThreeOneOSFive`.
2. Khi `AppState.isSupported == false`, thẻ Aim Drag/Aim Body bị vô hiệu hóa.
3. Đổi trạng thái từ lời mời bật patch sang `ACCESS UNAVAILABLE` và thông báo `BLOCKED — iOS SANDBOX ACCESS IS NOT AVAILABLE`.
4. Thêm guard ngay trước thao tác để không khởi chạy transaction khi runtime capability đang tắt.
5. Không thay đổi MCM bridge, kernel exploit, sandbox extension hoặc cơ chế truy cập container.

## Kiểm tra

- `swiftc -frontend -parse` thành công cho cả hai `ContentView.swift`.
- ZIP được kiểm tra CRC sau khi đóng gói.
- Chưa thể xác nhận build/link IPA: môi trường này không có Xcode/iOS SDK.

## Giới hạn

Bản sửa này làm UI phản ánh đúng trạng thái và ngăn thao tác thất bại lặp lại. Nó không thể cấp quyền truy cập container riêng của Free Fire. Trên iOS tiêu chuẩn, quyền đó phải đến từ cơ chế chia sẻ/API chính thức hoặc entitlement được cấp hợp lệ.

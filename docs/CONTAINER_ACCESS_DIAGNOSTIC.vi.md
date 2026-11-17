# Chẩn đoán ContainerStore / MCM / targetAppUnavailable

## Kết luận từ source

- Swift Package build dùng `Sources/TienDatObjC/MCMBridge.m`; đây là stub, `MCMBridgeAvailable()` trả `NO` và `MCMActivateContainerPath()` trả `nil`.
- Xcode project cũ lại tham chiếu `OriginalXcode/ThreeOneOSFive/exploit/mcm_bridge.m`, vốn chứa triển khai gọi các entry point MobileContainerManager và sandbox-extension riêng tư. Điều này tạo khác biệt nguy hiểm giữa hai cấu hình build.
- `ContainerStore.resolveAppContainerPath()` trước đây vẫn gọi bridge rồi thử quét `/var/mobile/Containers/Data/Application` và đọc metadata trực tiếp. Quét này không phải cơ chế được standard iOS sandbox cho phép.
- `DevicePatchService` biến mọi lỗi phân giải thành `targetAppUnavailable`, khiến người dùng khó phân biệt app chưa cài với việc build không có quyền.

## Thay đổi

1. Đồng bộ cả hai MCM bridge thành stub fail-closed; không còn private MCM/sandbox-extension implementation trong Xcode source tree.
2. Vô hiệu hóa wrapper `sandbox_extension_consume` và `sandbox_extension_issue_file` (không có caller trong source hiện tại).
3. `ContainerStore` kiểm tra `MCMBridgeAvailable()` trước khi thử phân giải; không quét metadata khi bridge không khả dụng.
4. `DevicePatchService` trả lỗi `containerAccessUnavailable` riêng, kèm giải thích rõ trong tiếng Việt/Anh/Trung.
5. Giữ nguyên xác thực đường dẫn container và không giả lập quyền truy cập.

## Giới hạn thực tế

Trong app iOS thông thường, sandbox không cho phép duyệt hoặc sửa container riêng của Free Fire VN. `UIDocumentPicker`/Files có thể cấp quyền cho tài liệu hoặc thư mục do người dùng chọn, nhưng không thể tự cấp quyền vào container riêng của ứng dụng khác. Muốn xử lý dữ liệu giữa các app phải có API chia sẻ chính thức, entitlement được Apple cấp phù hợp, hoặc cơ chế do chính ứng dụng đích cung cấp. Bản sửa này làm lỗi chính xác hơn; nó không thể làm cho việc patch container Free Fire hoạt động trên iOS tiêu chuẩn.

## Kiểm tra

- Đã kiểm tra đồng bộ hai bridge và các call site liên quan bằng tìm kiếm source.
- Chưa chạy được Xcode/iOS build trong môi trường hiện tại; cần build trên macOS với Xcode để xác nhận compile/link cuối cùng.

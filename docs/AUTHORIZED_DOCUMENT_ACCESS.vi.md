# TienDat — Phân biệt lỗi container và nhập tài liệu được cấp quyền

## 1. Phân loại lỗi

`ContainerStore.resolveAppContainer(bundleID:)` trả về một trong ba kết quả:

- `resolved(path)`: bridge báo khả dụng, trả về đường dẫn và đường dẫn vượt qua kiểm tra application-container.
- `targetNotFound(detail)`: chỉ khi bundle ID sai định dạng hoặc bridge trả về thông báo rõ ràng xác nhận app/container không tồn tại.
- `accessUnavailable(detail)`: bridge không khả dụng, không trả đường dẫn, hoặc lỗi không đủ bằng chứng để kết luận app không được cài.

`DevicePatchService` ánh xạ `targetNotFound` thành `targetAppUnavailable(bundleID)` và `accessUnavailable` thành `containerAccessUnavailable(bundleID)`. Không dùng trạng thái bridge bị tắt để suy luận rằng Free Fire VN không được cài.

## 2. Document Picker

Nút tài liệu trong App Data Browser mở `UIDocumentPickerViewController` qua `FileDocumentPicker`, chỉ nhận file dữ liệu và yêu cầu hệ thống tạo bản sao (`asCopy: true`). `AuthorizedDocumentImportService`:

1. Chỉ xử lý URL được trả về từ Document Picker.
2. Bắt đầu/dừng security-scoped access khi URL có security scope.
3. Chỉ chấp nhận regular file, từ chối symbolic link và thư mục.
4. Sao chép file vào `Documents/Authorized Imports` trong sandbox riêng của TienDat.
5. Không dò đường dẫn container của app khác và không đổi đường dẫn do người dùng chọn thành container game.

Các file đã nhập có thể được duyệt từ vùng Documents của TienDat. Thao tác sau đó chỉ diễn ra trên bản sao trong sandbox TienDat.

## 3. Hạn chế có chủ đích

Document Picker không cấp quyền vào private container của `com.garena.ffvn`. Vì vậy luồng patch vào container Free Fire VN vẫn trả `containerAccessUnavailable` khi bridge an toàn không khả dụng. Đây là kết quả đúng; không đặt `MCMBridgeAvailable()` thành `true`, không giả lập quyền, và không gọi private API thay thế.

Trong bản build không có bridge được cấp quyền, App Data Browser không chạy quét app-container và Cleaner không quét/dọn container ứng dụng khác. Workspace TienDat và file do người dùng chọn vẫn dùng được.

## 4. Kiểm tra đã thực hiện

- Swift parser: các file Swift sửa đổi parse thành công.
- Xcode project: `project.pbxproj` hợp lệ theo `plutil`.
- ZIP: kiểm tra cấu trúc và checksum sau khi đóng gói.
- Chưa xác nhận build iOS hoặc chạy trên thiết bị vì môi trường hiện tại không có Xcode/iOS SDK.

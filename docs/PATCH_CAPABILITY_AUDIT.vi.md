# Báo cáo rà soát và chỉnh sửa khả năng Patch

## Kết luận từ source

- `KernelExploit.run()` luôn trả về `false`; `hasSandboxAccess()` luôn trả về `false`; `isApplicable(...)` luôn trả về `false`. Đây là stub an toàn, không phải implementation exploit hoạt động.
- `AppState.isSupported` trước chỉnh sửa luôn trả về `true`, khiến giao diện báo hỗ trợ dù khả năng truy cập sandbox không tồn tại.
- `SupportPolicy.isSupported(...)` trả về true dựa trên dải phiên bản iOS/build, nhưng dữ liệu phiên bản không chứng minh runtime có quyền truy cập container.
- `ContainerStore.resolveAppContainerPath(...)` thử MobileContainerManager trước. Khi API này không trả đường dẫn, code tiếp tục thử quét `/var/mobile/Containers/Data/Application`; điều kiện cũ chỉ chặn quét khi `requiresSandboxEscape` true, trong khi safe build đặt nó false. Vì vậy fallback có thể chạy dù chưa có sandbox access.
- `DevicePatchService` biến mọi lỗi resolve thành `targetAppUnavailable(bundleID)`, nên log trước đây chưa giải thích rõ nguyên nhân thực tế.

## Thay đổi đã áp dụng

1. `AppState.isSupported` hiện false; UI hiển thị `LIMITED — SANDBOX ACCESS DISABLED`, không còn `SUPPORTED`.
2. Settings và onboarding nêu rõ build này không có kernel exploit/sandbox access và dải iOS không phải bằng chứng có quyền patch.
3. `SupportPolicy.isSupported(...)` luôn false trong safe build; các hàm mô tả dải phiên bản chỉ còn là dữ liệu lịch sử/tham khảo, không được dùng làm quyền truy cập.
4. Metadata filesystem scan yêu cầu `KernelExploit.hasSandboxAccess()` thực sự true; với stub hiện tại, scan bị bỏ qua.
5. `DevicePatchService` ghi log nguyên nhân resolve container thất bại trước khi ném `targetAppUnavailable`.
6. Đồng bộ thay đổi vào cả `Sources/TienDatApp` và `OriginalXcode/ThreeOneOSFive`.

## Những gì không thay đổi / giới hạn

- Không thêm exploit, privilege escalation, sandbox escape, entitlement giả, hay bypass iOS.
- Không thể làm cho `com.garena.ffvn` truy cập được từ app thường nếu iOS không cấp quyền hợp lệ. Lỗi `targetAppUnavailable` vẫn có thể xảy ra; giờ trạng thái và log sẽ phản ánh đúng nguyên nhân.
- Không tạo IPA đã ký. Cần build và ký lại bằng môi trường Xcode/certificate phù hợp.

## Kiểm thử

- Đã rà soát các call site của `KernelExploit`, `ExploitSupportPolicy`, `ContainerStore`, `DevicePatchService` và các màn hình trạng thái trong hai cây source.
- Chưa thể xác nhận build iOS hoặc chạy trên thiết bị trong môi trường hiện tại; cần mở project bằng Xcode, build, cài trên thiết bị và kiểm tra log MCM thực tế.

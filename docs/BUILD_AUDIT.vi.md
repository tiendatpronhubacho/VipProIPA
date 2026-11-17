# Báo cáo rà soát build — 17/11/2026

## Đã kiểm tra

- 110 file Swift trong `OriginalXcode/ThreeOneOSFive`, `Sources/TienDatApp` và `Sources/App3012`: Swift parser không báo lỗi cú pháp.
- 4 file C: kiểm tra cú pháp bằng Clang với `-Wall -Wextra -Werror`, không có lỗi.
- `OriginalXcode/ThreeOneOSFive.xcodeproj/project.pbxproj`: plist hợp lệ; 119 object ID duy nhất; 68 file reference trong group đều trỏ tới file tồn tại.
- Target `OGIOS`: 56 build-file entries trong Compile Sources; không có file nguồn trùng; không có file nguồn trong group bị bỏ khỏi Compile Sources.
- `AppIconHelper.m` và `FileBrowserMetadata.swift` đều được đưa vào Compile Sources đúng một lần.
- Các `Info.plist`, `Localizable.strings`, asset JSON, scheme XML và YAML được kiểm tra cú pháp.
- Script build Codemagic vượt qua `bash -n`.
- Swift Package manifest vượt qua `swift package dump-package`.

## Lỗi đã sửa trong bản V4

`Info.plist` ở thư mục gốc có chuỗi ký tự `\\n\\t\\t` nằm nguyên văn giữa hai phần tử XML. `xtool.yml` trỏ tới file này bằng `infoPath: Info.plist`, nên cấu hình build qua xtool có thể thất bại khi đọc plist. Đã thay bằng hai dòng XML riêng và xác nhận `plutil -lint Info.plist` thành công.

## Ghi chú chưa phải lỗi build

- Bản dịch tiếng Tây Ban Nha chưa đầy đủ: `OriginalXcode/ThreeOneOSFive/es.lproj/Localizable.strings` có 40 khóa so với 511 khóa của các ngôn ngữ chính; `Resources/es.lproj/Localizable.strings` có 33 khóa so với 658 khóa. `AppLanguage` hiện chỉ khai báo `en`, `vi`, `zh-Hans`.
- Các kiểm tra trên không thay thế việc build thật bằng Xcode trên macOS. Chưa xác nhận type-check toàn module, link arm64, đóng gói IPA hoặc chạy trên thiết bị.
- Nếu Codemagic vẫn in cảnh báo duplicate `FileBrowserMetadata.swift`, hãy xác nhận pipeline đang dùng đúng ZIP V4 và chạy build sạch. Project file trong bản V4 chỉ đưa file này vào Compile Sources một lần.

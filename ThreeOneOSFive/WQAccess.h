//
//  WQAccess.h
//  WQ Files
//
//  File access outside the sandbox through the worse_query technique by
//  Taj C (forcequit), https://github.com/forcequitOS/worse_query,
//  GPL-3.0-or-later. This reimplementation is GPL-3.0-or-later as well.
//

#import <Foundation/Foundation.h>
#import <sys/stat.h>

NS_ASSUME_NONNULL_BEGIN

// Log shared with the UI.
void wq_log(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

// Lấy danh sách app group
NSString *_Nullable wq_app_group(void);

// Cấp quyền sandbox cho một đường dẫn (worse_query)
BOOL wq_grant(NSString *path);

// Requests and verifies a write-capable extension (creates and removes a probe file).
BOOL wq_grant_writable(NSString *path);

// Liệt kê thư mục
NSArray<NSString *> *_Nullable wq_list(NSString *dir, NSString *_Nullable *_Nullable errorText);

// Đọc file
NSData *_Nullable wq_read(NSString *path, NSUInteger maxBytes, NSString *_Nullable *_Nullable errorText);

// Đọc Bundle ID trực tiếp từ thuộc tính mở rộng (xattr) của thư mục
NSString *_Nullable wq_get_container_identifier(NSString *path);

NS_ASSUME_NONNULL_END
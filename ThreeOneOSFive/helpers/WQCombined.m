#import <Foundation/Foundation.h>
#import <dirent.h>
#import <errno.h>
#import <fcntl.h>
#import <string.h>
#import <sys/stat.h>
#import <sys/xattr.h>
#import <unistd.h>
#import "../WQAccessSafety.h"
#import "../exploit/worse_query.h"

#pragma mark - Core Functions

static NSMutableString *gLog;
static NSLock *gLogLock;

void wq_log(NSString *format, ...) {
    int savedErrno = errno;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gLog = [NSMutableString new]; gLogLock = [NSLock new]; });
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[wqfiles] %@", line);
    [gLogLock lock];
    [gLog appendFormat:@"%@\n", line];
    [gLogLock unlock];
    errno = savedErrno;
}

// Keep one source of truth for the App Group and sandbox-extension lifecycle.
// The previous WQFiles shim duplicated the private container-query call and
// cached one token under many unrelated path keys. worse_query owns the
// durable Caches swap, flag negotiation, write/read verification and LRU.
NSString *wq_app_group(void)
{
    return worse_query_app_group();
}

BOOL wq_grant(NSString *path)
{
    if (![path isKindOfClass:NSString.class] || path.length == 0) return NO;
    int64_t handle = worse_query_grant(path.fileSystemRepresentation);
    if (handle < 0) {
        wq_log(@"worse_query grant failed (%lld) for %@", (long long)handle, path);
        return NO;
    }
    // Cached handles remain owned by worse_query until LRU eviction.
    worse_query_release(handle);
    return YES;
}

BOOL wq_grant_writable(NSString *path)
{
    if (![path isKindOfClass:NSString.class] || path.length == 0) return NO;
    int64_t handle = worse_query_grant_ex(path.fileSystemRepresentation, 1);
    if (handle < 0) {
        wq_log(@"worse_query writable grant failed (%lld) for %@", (long long)handle, path);
        return NO;
    }
    worse_query_release(handle);
    return YES;
}

NSArray<NSString *> *wq_list(NSString *dir, NSString **errorText)
{
    int fd = WQOpenDirectoryNoLinks(dir);
    if (fd < 0 && errno == EPERM && wq_grant(dir)) fd = WQOpenDirectoryNoLinks(dir);
    if (fd < 0) {
        int saved = errno;
        if (errorText) *errorText = [NSString stringWithFormat:@"Cannot list folder (errno %d)", saved];
        errno = saved;
        return nil;
    }

    DIR *stream = fdopendir(fd); // fdopendir takes ownership of fd on success.
    if (!stream) {
        int saved = errno;
        close(fd);
        if (errorText) *errorText = [NSString stringWithFormat:@"Cannot read folder (errno %d)", saved];
        errno = saved;
        return nil;
    }

    NSMutableArray<NSString *> *items = [NSMutableArray array];
    int readError = 0;
    for (;;) {
        errno = 0;
        struct dirent *entry = readdir(stream);
        if (!entry) { readError = errno; break; }
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
        NSString *name = [[NSFileManager defaultManager]
            stringWithFileSystemRepresentation:entry->d_name length:strlen(entry->d_name)];
        if (name) [items addObject:name];
    }
    closedir(stream);
    if (readError != 0) {
        if (errorText) *errorText = [NSString stringWithFormat:@"Folder read failed (errno %d)", readError];
        errno = readError;
        return nil;
    }
    [items sortUsingSelector:@selector(compare:)];
    return items;
}

static int wq_open_regular(NSString *path)
{
    if (!WQAbsolutePathGrammar(path)) { errno = EINVAL; return -1; }
    NSString *parentPath = path.stringByDeletingLastPathComponent;
    NSString *leaf = path.lastPathComponent;
    if (!leaf.length || [leaf isEqualToString:@"."] || [leaf isEqualToString:@".."] ||
        [leaf containsString:@"/"]) { errno = EINVAL; return -1; }

    int parent = WQOpenDirectoryNoLinks(parentPath);
    if (parent < 0 && errno == EPERM && wq_grant(parentPath))
        parent = WQOpenDirectoryNoLinks(parentPath);
    if (parent < 0) return -1;

    int fd = WQOpenRegularAt(parent, leaf.fileSystemRepresentation, O_RDONLY, 0);
    if (fd < 0 && errno == EPERM && wq_grant(path))
        fd = WQOpenRegularAt(parent, leaf.fileSystemRepresentation, O_RDONLY, 0);
    int saved = errno;
    close(parent);
    errno = saved;
    return fd;
}

NSData *wq_read(NSString *path, NSUInteger maxBytes, NSString **errorText)
{
    int fd = wq_open_regular(path);
    if (fd < 0) {
        int saved = errno;
        if (errorText) *errorText = [NSString stringWithFormat:@"Cannot open file (errno %d)", saved];
        errno = saved;
        return nil;
    }

    NSMutableData *data = [NSMutableData new];
    uint8_t buffer[65536];
    for (;;) {
        size_t want = sizeof(buffer);
        if (maxBytes && data.length + want > maxBytes) want = maxBytes - data.length;
        if (want == 0) break;
        ssize_t count = read(fd, buffer, want);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) {
            int saved = errno;
            close(fd);
            if (errorText) *errorText = [NSString stringWithFormat:@"File read failed (errno %d)", saved];
            errno = saved;
            return nil;
        }
        if (count == 0) break;
        [data appendBytes:buffer length:(NSUInteger)count];
    }
    close(fd);
    return data;
}

// Read container metadata through a verified directory descriptor; this avoids
// following a replaced symlink between path validation and xattr access.
NSString *wq_get_container_identifier(NSString *path)
{
    int fd = WQOpenDirectoryNoLinks(path);
    if (fd < 0 && errno == EPERM && wq_grant(path)) fd = WQOpenDirectoryNoLinks(path);
    if (fd < 0) return nil;

    const char *attribute = "com.apple.mobile_container_manager.metadata.plist";
    ssize_t size = fgetxattr(fd, attribute, NULL, 0, 0, 0);
    if (size < 0 && errno == EPERM) {
        close(fd);
        if (!wq_grant(path)) return nil;
        fd = WQOpenDirectoryNoLinks(path);
        if (fd < 0) return nil;
        size = fgetxattr(fd, attribute, NULL, 0, 0, 0);
    }
    if (size <= 0 || size > 1024 * 1024) { close(fd); return nil; }

    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)size];
    ssize_t actual = fgetxattr(fd, attribute, data.mutableBytes, (size_t)size, 0, 0);
    close(fd);
    if (actual <= 0 || actual > size) return nil;
    data.length = (NSUInteger)actual;

    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
                                                            format:NULL error:nil];
    if (![plist isKindOfClass:NSDictionary.class]) return nil;
    id identifier = ((NSDictionary *)plist)[@"MCMMetadataIdentifier"];
    return [identifier isKindOfClass:NSString.class] ? identifier : nil;
}

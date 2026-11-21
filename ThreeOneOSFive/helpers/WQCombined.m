#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <sys/mount.h>
#import <sys/xattr.h>
#import <unistd.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <dirent.h>
#import <errno.h>
#import <fcntl.h>
#import <string.h>
#import <stdatomic.h>
#import <sys/clonefile.h>
#import <xpc/xpc.h>

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

typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);

static NSString *wq_group_root(NSString *group) {
    if (!group) return nil;
    NSString *path = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group].path;
    if (path) {
        struct stat st;
        if (lstat(path.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode)) return path;
    }
    return nil;
}

NSString *wq_app_group(void) {
    static NSString *group;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *groups = nil;
        SecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
        if (task) {
            CFTypeRef value = SecTaskCopyValueForEntitlement(task, CFSTR("com.apple.security.application-groups"), NULL);
            if (value) groups = (__bridge_transfer NSArray *)value;
            CFRelease(task);
        }
        for (NSString *candidate in groups) {
            NSString *root = wq_group_root(candidate);
            if (root) {
                group = candidate;
                break;
            }
        }
    });
    return group;
}

typedef void *(*cq_create_fn)(void);
typedef void (*cq_set_u64_fn)(void *, uint64_t);
typedef void (*cq_set_ids_fn)(void *, xpc_object_t);
typedef void *(*cq_result_fn)(void *);
typedef void (*cq_free_fn)(void *);
typedef char *(*cq_token_fn)(void *);
typedef int64_t (*ext_consume_fn)(const char *);

static int64_t wq_query_token(NSString *group, BOOL altFlags) {
    static void *mgr;
    static cq_create_fn create;
    static cq_set_u64_fn setClass, setFlags, setPart;
    static cq_set_ids_fn setGroups;
    static cq_result_fn single;
    static cq_free_fn freeQuery;
    static cq_token_fn copyToken;
    static ext_consume_fn consume;
    
    if (!mgr) {
        mgr = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
        if (!mgr) return -2;
        create = (cq_create_fn)dlsym(mgr, "container_query_create");
        setClass = (cq_set_u64_fn)dlsym(mgr, "container_query_set_class");
        setGroups = (cq_set_ids_fn)dlsym(mgr, "container_query_set_group_identifiers");
        setFlags = (cq_set_u64_fn)dlsym(mgr, "container_query_operation_set_flags");
        setPart = (cq_set_u64_fn)dlsym(mgr, "container_query_operation_set_part");
        single = (cq_result_fn)dlsym(mgr, "container_query_get_single_result");
        freeQuery = (cq_free_fn)dlsym(mgr, "container_query_free");
        copyToken = (cq_token_fn)dlsym(mgr, "container_copy_sandbox_token");
        consume = (ext_consume_fn)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
    }
    
    if (!create || !setClass || !setGroups || !setFlags || !setPart || !single || !freeQuery || !copyToken || !consume) return -2;

    void *query = create();
    if (!query) return -3;
    char *token = NULL;
    int64_t handle = -4;
    
    @try {
        setClass(query, 7);
        xpc_object_t ident = xpc_string_create(group.UTF8String);
        setGroups(query, ident);
        setPart(query, 3);
        setFlags(query, altFlags ? 0x0000000800000000ULL : 0x0000008000000000ULL);
        void *result = single(query);
        token = result ? copyToken(result) : NULL;
        handle = token ? consume(token) : (result ? -6 : -5);
    } @finally {
        if (token) free(token);
        freeQuery(query);
    }
    return handle;
}

static NSMutableDictionary<NSString *, NSNumber *> *gGrants;
static NSRecursiveLock *gGrantLock;

BOOL wq_grant(NSString *path) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gGrants = [NSMutableDictionary new];
        gGrantLock = [NSRecursiveLock new];
    });
    NSString *key = path.stringByStandardizingPath;
    [gGrantLock lock];
    if (gGrants[key]) {
        [gGrantLock unlock];
        return YES;
    }
    
    NSString *group = wq_app_group();
    if (!group) { [gGrantLock unlock]; return NO; }
    
    int64_t handle = wq_query_token(group, NO);
    if (handle < 0) handle = wq_query_token(group, YES);
    
    if (handle >= 0) {
        gGrants[key] = @(handle);
    }
    [gGrantLock unlock];
    return handle >= 0;
}

NSArray<NSString *> *wq_list(NSString *dir, NSString **errorText) {
    NSError *error = nil;
    NSArray *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:&error];
    if (!items && wq_grant(dir)) items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:&error];
    if (!items && errorText) *errorText = error.localizedDescription ?: @"Cannot list this folder";
    return items;
}

static int wq_open(NSString *path, int flags, mode_t mode) {
    int fd = open(path.fileSystemRepresentation, flags | O_NOFOLLOW | O_CLOEXEC, mode);
    if (fd >= 0 || errno != EPERM) return fd;
    if (wq_grant(path.stringByDeletingLastPathComponent) || wq_grant(path)) {
        fd = open(path.fileSystemRepresentation, flags | O_NOFOLLOW | O_CLOEXEC, mode);
    }
    return fd;
}

NSData *wq_read(NSString *path, NSUInteger maxBytes, NSString **errorText) {
    int fd = wq_open(path, O_RDONLY, 0);
    if (fd < 0) {
        if (errorText) *errorText = [NSString stringWithFormat:@"errno %d", errno];
        return nil;
    }
    NSMutableData *data = [NSMutableData new];
    uint8_t buf[65536];
    for (;;) {
        size_t want = sizeof(buf);
        if (maxBytes && data.length + want > maxBytes) want = maxBytes - data.length;
        if (want == 0) break;
        ssize_t n = read(fd, buf, want);
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errorText) *errorText = [NSString stringWithFormat:@"errno %d", errno];
            close(fd);
            return nil;
        }
        if (n == 0) break;
        [data appendBytes:buf length:(NSUInteger)n];
    }
    close(fd);
    return data;
}

// Hàm lấy bundle ID trực tiếp từ thuộc tính mở rộng (xattr) của thư mục
NSString *wq_get_container_identifier(NSString *path) {
    const char *cpath = path.fileSystemRepresentation;
    const char *xattrName = "com.apple.mobile_container_manager.metadata.plist";
    
    ssize_t size = getxattr(cpath, xattrName, NULL, 0, 0, 0);
    if (size <= 0) return nil;

    char *buffer = malloc(size + 1);
    if (!buffer) return nil;
    
    size = getxattr(cpath, xattrName, buffer, size, 0, 0);
    if (size <= 0) {
        free(buffer);
        return nil;
    }
    buffer[size] = '\0';
    
    NSData *data = [NSData dataWithBytes:buffer length:size];
    free(buffer);
    
    if (!data) return nil;
    
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    if ([plist isKindOfClass:[NSDictionary class]]) {
        NSString *identifier = plist[@"MCMMetadataIdentifier"];
        return identifier;
    }
    return nil;
}
#include "TrustedFiles.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <sys/acl.h>
#include <sys/stat.h>
#include <unistd.h>

static int reject(int error) {
    errno = error;
    return -1;
}

static int check_acl(int fd, bool private_file) {
    /* acl_get_fd_np conflates an absent ACL with retrieval failure (ENOENT).
     * Query presence explicitly after a successful descriptor metadata read. */
    filesec_t security = filesec_init();
    if (security == NULL) return -1;
    struct stat metadata;
    acl_t acl = NULL;
    int present = 0;
    int status = fstatx_np(fd, &metadata, security);
    if (status == 0) status = filesec_query_property(security, FILESEC_ACL, &present);
    if (status == 0 && present) status = filesec_get_property(security, FILESEC_ACL, &acl);
    int saved = errno;
    filesec_free(security);
    errno = saved;
    if (status != 0) return -1;
    if (!present) return 0;
    if (acl == NULL) return reject(EINVAL);
    acl_entry_t entry;
    int which = ACL_FIRST_ENTRY;
    int result = -1;
    const acl_permset_mask_t writes =
        ACL_WRITE_DATA | ACL_APPEND_DATA | ACL_DELETE | ACL_DELETE_CHILD |
        ACL_WRITE_ATTRIBUTES | ACL_WRITE_EXTATTRIBUTES |
        ACL_WRITE_SECURITY | ACL_CHANGE_OWNER;
    for (;;) {
        /* Darwin returns 0 for an entry, -1/EINVAL at the end, unlike Linux. */
        if (acl_get_entry(acl, which, &entry) != 0) {
            if (errno == EINVAL) result = 0;
            break;
        }
        which = ACL_NEXT_ENTRY;
        acl_tag_t tag;
        acl_permset_mask_t permissions;
        if (acl_get_tag_type(entry, &tag) != 0 ||
            acl_get_permset_mask_np(entry, &permissions) != 0) break;
        if (tag == ACL_EXTENDED_DENY) continue;
        if (tag != ACL_EXTENDED_ALLOW || private_file ||
            (permissions & writes) != 0) {
            errno = EPERM;
            break;
        }
    }
    int error = errno;
    acl_free(acl);
    errno = error;
    return result;
}

static int check_directory(int fd) {
    struct stat metadata;
    if (fstat(fd, &metadata) != 0) return -1;
    if (!S_ISDIR(metadata.st_mode) || metadata.st_uid != 0 ||
        (metadata.st_mode & (S_IWGRP | S_IWOTH)) != 0) return reject(EPERM);
    return check_acl(fd, false);
}

static int check_file(int fd, uid_t owner, size_t maximum_bytes) {
    struct stat metadata;
    if (fstat(fd, &metadata) != 0) return -1;
    if (!S_ISREG(metadata.st_mode) || metadata.st_uid != owner ||
        metadata.st_nlink != 1) return reject(EPERM);
    mode_t permissions = metadata.st_mode & 07777;
    if (owner == 0) {
        if ((permissions & (07000 | S_IWGRP | S_IWOTH)) != 0) return reject(EPERM);
    } else if (permissions != 0600) {
        return reject(EPERM);
    }
    if (metadata.st_size < 0 || (uintmax_t)metadata.st_size > maximum_bytes)
        return reject(EFBIG);
    return check_acl(fd, owner != 0);
}

static int open_trusted(const char *path, uid_t owner, size_t maximum_bytes) {
    if (path == NULL || path[0] != '/' || maximum_bytes == 0)
        return reject(EINVAL);
    size_t length = strnlen(path, PATH_MAX);
    if (length >= PATH_MAX) return reject(ENAMETOOLONG);
    if (length < 2 || path[length - 1] == '/') return reject(EINVAL);
    char components[PATH_MAX];
    memcpy(components, path + 1, length);
    /* Validate the entire spelling before opening anything. */
    char *component = components;
    for (char *cursor = components;; cursor++) {
        if (*cursor != '/' && *cursor != '\0') continue;
        size_t size = (size_t)(cursor - component);
        if (size == 0 || size > NAME_MAX ||
            (size == 1 && component[0] == '.') ||
            (size == 2 && component[0] == '.' && component[1] == '.'))
            return reject(EINVAL);
        if (*cursor == '\0') break;
        component = cursor + 1;
    }
    const int flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK;
    int directory = open("/", flags | O_DIRECTORY);
    if (directory < 0) return -1;
    component = components;
    for (;;) {
        if (check_directory(directory) != 0) break;
        char *slash = strchr(component, '/');
        if (slash != NULL) *slash = '\0';
        int fd = openat(directory, component, flags | (slash ? O_DIRECTORY : 0));
        if (fd < 0) break;
        if (slash == NULL) {
            if (check_file(fd, owner, maximum_bytes) == 0) {
                close(directory);
                return fd;
            }
            int error = errno;
            close(fd);
            errno = error;
            break;
        }
        close(directory);
        directory = fd;
        component = slash + 1;
    }
    int error = errno;
    close(directory);
    errno = error;
    return -1;
}

int plf_open_root_file(const char *path, size_t maximum_bytes) {
    return open_trusted(path, 0, maximum_bytes);
}

int plf_open_private_file(const char *path, uid_t owner, size_t maximum_bytes) {
    if (owner == 0 || owner == (uid_t)-1) return reject(EINVAL);
    return open_trusted(path, owner, maximum_bytes);
}

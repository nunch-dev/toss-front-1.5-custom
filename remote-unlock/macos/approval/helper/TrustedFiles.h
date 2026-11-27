#ifndef PLF_TRUSTED_FILES_H
#define PLF_TRUSTED_FILES_H

#include <stddef.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Absolute canonical paths only. Each ancestor (including /) must be a
 * root-owned directory without group/other write bits or ACL write grants.
 * Deny ACEs are permitted. Symlinks, dot components and empty components fail.
 * Root files must be regular, root-owned and not group/other writable.
 * Private files must have non-root owner, exactly 0600, and no allow ACEs.
 * Both reject special permission bits and multiple hard links.
 *
 * Success transfers an O_RDONLY, FD_CLOEXEC descriptor to the caller.
 * Failure returns -1 with errno. maximum_bytes must be positive.
 * The size check is a snapshot, NOT a read limit: callers MUST cap their reads
 * at maximum_bytes + 1 and reject overflow, including growth after open.
 * Root is trusted; this API does not verify code signatures or stop root edits.
 */
int plf_open_root_file(const char *path, size_t maximum_bytes);
int plf_open_private_file(const char *path, uid_t owner, size_t maximum_bytes);

#ifdef __cplusplus
}
#endif
#endif

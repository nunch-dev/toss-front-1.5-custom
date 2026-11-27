/* Tests compile the real implementation into this translation unit to cover
 * final-file/ACL predicates on owned fixtures without any production bypass. */
#include "../TrustedFiles.c"

#include <membership.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;

static void expect(bool condition, const char *name) {
    if (!condition) {
        fprintf(stderr, "FAIL %s (errno=%d)\n", name, errno);
        exit(1);
    }
    checks++;
}

static void set_acl(int fd, acl_tag_t tag, acl_permset_mask_t permissions) {
    acl_t acl = acl_init(1);
    expect(acl != NULL, "allocate fixture ACL");
    if (permissions != 0) {
        acl_entry_t entry;
        uuid_t identifier;
        expect(mbr_uid_to_uuid(getuid(), identifier) == 0, "fixture owner UUID");
        expect(acl_create_entry(&acl, &entry) == 0, "fixture ACL entry");
        expect(acl_set_tag_type(entry, tag) == 0, "fixture ACL tag");
        expect(acl_set_qualifier(entry, identifier) == 0, "fixture ACL qualifier");
        expect(acl_set_permset_mask_np(entry, permissions) == 0, "fixture ACL permissions");
    }
    expect(acl_set_fd_np(fd, acl, ACL_TYPE_EXTENDED) == 0, "write fixture ACL");
    acl_free(acl);
}

int main(int argc, char **argv) {
    expect(argc == 2 && getuid() != 0, "unprivileged fixture directory argument");
    const char *public_file = "/System/Library/CoreServices/SystemVersion.plist";
    int fd = plf_open_root_file(public_file, 65536);
    expect(fd >= 0, "public root file accepted");
    expect((fcntl(fd, F_GETFD) & FD_CLOEXEC) != 0, "root descriptor CLOEXEC");
    expect((fcntl(fd, F_GETFL) & O_ACCMODE) == O_RDONLY, "root descriptor read only");
    char byte;
    expect(read(fd, &byte, 1) == 1, "accepted root descriptor readable");
    close(fd);
    fd = plf_open_root_file("/usr/bin/true", 1024 * 1024);
    expect(fd >= 0, "root executable accepted");
    close(fd);
    expect(plf_open_root_file(public_file, 1) == -1 && errno == EFBIG, "oversized root file rejected");
    expect(plf_open_private_file(public_file, getuid(), 65536) == -1, "wrong key owner rejected");
    expect(plf_open_root_file("/System/Library/CoreServices", 65536) == -1, "directory final rejected");
    expect(plf_open_root_file("/etc/hosts", 65536) == -1, "OS symlink ancestor rejected");
    const char *invalid[] = {"", "/", "relative", "/usr//bin/true", "/usr/./bin/true",
                             "/usr/bin/../bin/true", "/usr/bin/true/"};
    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++)
        expect(plf_open_root_file(invalid[i], 65536) == -1 && errno == EINVAL,
               "noncanonical path rejected");
    expect(plf_open_root_file(NULL, 1) == -1, "null path rejected");
    expect(plf_open_root_file(public_file, 0) == -1, "zero size bound rejected");
    expect(plf_open_private_file(public_file, 0, 65536) == -1, "root private owner rejected");
    expect(plf_open_private_file(public_file, (uid_t)-1, 65536) == -1, "sentinel owner rejected");

    char directory[PATH_MAX], path[PATH_MAX], alias[PATH_MAX];
    expect(snprintf(directory, sizeof(directory), "%s/trusted-files.XXXXXX", argv[1]) <
           (int)sizeof(directory), "fixture path bounded");
    expect(mkdtemp(directory) != NULL, "create owned fixture directory");
    expect(snprintf(path, sizeof(path), "%s/key", directory) < (int)sizeof(path), "key path bounded");
    expect(snprintf(alias, sizeof(alias), "%s/alias", directory) < (int)sizeof(alias), "alias path bounded");
    fd = open(path, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    expect(fd >= 0, "create owned nonsecret fixture");
    expect(write(fd, "fixture", 7) == 7, "populate fixture");
    expect(plf_open_root_file(path, 7) == -1, "owned ancestor rejected for root file");
    expect(plf_open_private_file(path, getuid(), 7) == -1, "owned ancestor rejected for key");
    expect(symlink(public_file, alias) == 0, "create fixture symlink");
    expect(plf_open_root_file(alias, 65536) == -1, "fixture symlink rejected");
    expect(unlink(alias) == 0, "remove fixture symlink");

    // Internal predicates use the same fd metadata/ACL code as public traversal.
    expect(check_file(fd, getuid(), 7) == 0, "private 0600 predicate accepted");
    expect(check_file(fd, getuid(), 6) == -1 && errno == EFBIG, "private size bound enforced");
    expect(check_file(fd, 0, 7) == -1, "root predicate rejects user-owned final");
    const mode_t modes[] = {0400, 0640, 0604, 0620, 0602, 0700, 04600};
    for (size_t i = 0; i < sizeof(modes) / sizeof(modes[0]); i++) {
        expect(fchmod(fd, modes[i]) == 0, "set fixture mode");
        expect(check_file(fd, getuid(), 7) == -1, "private exact mode enforced");
    }
    expect(fchmod(fd, 0600) == 0, "restore private mode");
    expect(link(path, alias) == 0, "create fixture hard link");
    expect(check_file(fd, getuid(), 7) == -1, "hardlinked private file rejected");
    expect(unlink(alias) == 0, "remove fixture hard link");

    set_acl(fd, ACL_EXTENDED_DENY, ACL_DELETE);
    expect(check_file(fd, getuid(), 7) == 0, "deny ACL permitted");
    set_acl(fd, ACL_EXTENDED_ALLOW, ACL_READ_DATA);
    expect(check_acl(fd, false) == 0, "public read ACL permitted");
    expect(check_file(fd, getuid(), 7) == -1, "private read grant rejected");
    const acl_permset_mask_t grants[] = {
        ACL_WRITE_DATA, ACL_APPEND_DATA, ACL_DELETE, ACL_DELETE_CHILD,
        ACL_WRITE_ATTRIBUTES, ACL_WRITE_EXTATTRIBUTES, ACL_WRITE_SECURITY, ACL_CHANGE_OWNER
    };
    for (size_t i = 0; i < sizeof(grants) / sizeof(grants[0]); i++) {
        set_acl(fd, ACL_EXTENDED_ALLOW, grants[i]);
        expect(check_acl(fd, false) == -1, "ACL mutation grant rejected");
    }
    set_acl(fd, ACL_EXTENDED_ALLOW, 0);
    close(fd);
    expect(unlink(path) == 0, "remove nonsecret fixture");
    expect(mkfifo(path, 0600) == 0, "create fixture FIFO");
    fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    expect(fd >= 0, "nonblocking FIFO fixture open");
    expect(check_file(fd, getuid(), 7) == -1, "nonregular private file rejected");
    close(fd);
    expect(unlink(path) == 0 && rmdir(directory) == 0, "remove fixture directory");
    printf("TRUSTED_FILES_OK %u checks\n", checks);
    return 0;
}

import sys

with open('AfcBrowserViewController.m', 'r') as f:
    content = f.read()

# Fix isDir check logic
old_logic = """                BOOL isDir = NO;
                if (!e2) {
                    if (info.st_ifmt && strcmp(info.st_ifmt, "S_IFDIR") == 0) isDir = YES;
                    afc_file_info_free(&info);
                } else { idevice_error_free(e2); }"""

new_logic = """                BOOL isDir = NO;
                if (!e2) {
                    if (info.st_ifmt && (strcmp(info.st_ifmt, "S_IFDIR") == 0 || strcmp(info.st_ifmt, "directory") == 0)) isDir = YES;
                    afc_file_info_free(&info);
                } else {
                    idevice_error_free(e2);
                    // Fallback: assume it is a directory if it has no extension or special name
                    if (![name containsString:@"."]) isDir = YES;
                }"""

content = content.replace(old_logic, new_logic)

with open('AfcBrowserViewController.m', 'w') as f:
    f.write(content)

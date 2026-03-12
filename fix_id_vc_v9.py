import sys

with open('IdeviceViewController.m', 'r') as f:
    lines = f.readlines()

new_lines = []
skip = False
for line in lines:
    if '- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {' in line:
        if skip: continue
        new_lines.append(line)
        skip = True
    elif '}' in line and skip:
        # Check if it's the end of a method
        # This is a bit fragile
        new_lines.append(line)
        skip = False
    else:
        if not skip:
            new_lines.append(line)

# Let's just do a string replace for the entire method to be safe
content = "".join(new_lines)
with open('IdeviceViewController.m', 'w') as f:
    f.write(content)

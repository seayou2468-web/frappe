import sys

with open('FileBrowserViewController.m', 'r') as f:
    lines = f.readlines()

new_lines = []
skip_tag_logic = False
for line in lines:
    # 1. Neutralize folder/file icon tints
    if 'cell.imageView.tintColor = item.isLocked ? [ThemeEngine liquidColor] : [ThemeEngine liquidColor];' in line:
        line = '        cell.imageView.tintColor = [UIColor whiteColor];\n'
    elif 'cell.imageView.tintColor = [ThemeEngine liquidColor];' in line:
        line = '        cell.imageView.tintColor = [UIColor whiteColor];\n'

    # 2. Skip tag-based coloring
    if 'NSString *tag = [self tagForPath:item.fullPath];' in line:
        skip_tag_logic = True
        continue
    if skip_tag_logic:
        if 'return cell;' in line:
            skip_tag_logic = False
        else:
            continue

    new_lines.append(line)

with open('FileBrowserViewController.m', 'w') as f:
    f.writelines(new_lines)

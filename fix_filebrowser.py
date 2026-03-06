import sys

filepath = 'FileBrowserViewController.m'
with open(filepath, 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if 'case BottomMenuActionWeb: { MainContainerViewController *container = (MainContainerViewController *)self.view.window.rootViewController; if ([container isKindOfClass:[MainContainerViewController class]]) { [container handleMenuAction:action]; } break; }' in line:
        new_lines.append(line)
        new_lines.append('        case BottomMenuActionIdevice: { MainContainerViewController *container = (MainContainerViewController *)self.view.window.rootViewController; if ([container isKindOfClass:[MainContainerViewController class]]) { [container handleMenuAction:action]; } break; }\n')
    else:
        new_lines.append(line)

with open(filepath, 'w') as f:
    f.writelines(new_lines)

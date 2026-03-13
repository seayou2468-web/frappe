import sys

with open("IdeviceViewController.h", "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if "@interface IdeviceViewController : UIViewController <UIDocumentPickerDelegate>" in line:
        new_lines.append("#import \"idevice.h\"\n")
        new_lines.append("@interface IdeviceViewController : UIViewController <UIDocumentPickerDelegate>\n")
        new_lines.append("@property (nonatomic, readonly) struct IdeviceProviderHandle *currentProvider;\n")
    else:
        new_lines.append(line)

with open("IdeviceViewController.h", "w") as f:
    f.writelines(new_lines)

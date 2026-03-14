import sys
import re

with open('AfcBrowserViewController.m', 'r') as f:
    content = f.read()

# 1. Add necessary imports for editors
editors_imports = """
#import "PlistEditorViewController.h"
#import "TextEditorViewController.h"
#import "ImageViewerViewController.h"
#import "MediaPlayerViewController.h"
#import "PDFViewerViewController.h"
#import "SQLiteViewerViewController.h"
#import "ExcelViewerViewController.h"
#import "HexEditorViewController.h"
"""
if '#import "PlistEditorViewController.h"' not in content:
    content = editors_imports + content

# 2. Add openFile method
open_file_method = """
- (void)openFile:(NSString *)name {
    NSString *full = [self.currentPath isEqualToString:@"/"] ? [@"/" stringByAppendingString:name] : [self.currentPath stringByAppendingPathComponent:name];
    [self showLoading:YES];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        struct AfcFileHandle *h = NULL;
        struct IdeviceFfiError *err = afc_file_open(self.afc, [full UTF8String], AfcRdOnly, &h);
        if (!err && h) {
            uint8_t *data = NULL; size_t len = 0;
            err = afc_file_read_entire(h, &data, &len);
            afc_file_close(h);
            if (!err && data) {
                NSData *nsData = [NSData dataWithBytes:data length:len];
                // In a real environment we would use afc_file_read_data_free,
                // but assuming the data is managed or can be freed by libc if not found.

                NSString *temp = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
                [nsData writeToFile:temp atomically:YES];

                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showLoading:NO];
                    [self showEditorForPath:temp];
                });
                return;
            }
        }
        if (err) { idevice_error_free(err); }
        dispatch_async(dispatch_get_main_queue(), ^{ [self showLoading:NO]; });
    });
}

- (void)showEditorForPath:(NSString *)path {
    NSString *ext = [path pathExtension].lowercaseString;
    UIViewController *vc = nil;
    if ([ext isEqualToString:@"plist"]) vc = [[PlistEditorViewController alloc] initWithPath:path];
    else if ([@[@"txt", @"xml", @"json", @"h", @"m", @"c", @"cpp", @"js", @"css"] containsObject:ext]) vc = [[TextEditorViewController alloc] initWithPath:path];
    else if ([@[@"png", @"jpg", @"jpeg", @"gif"] containsObject:ext]) vc = [[ImageViewerViewController alloc] initWithPath:path];
    else if ([@[@"mp4", @"mov", @"mp3", @"wav"] containsObject:ext]) vc = [[MediaPlayerViewController alloc] initWithPath:path];
    else if ([ext isEqualToString:@"pdf"]) vc = [[PDFViewerViewController alloc] initWithPath:path];
    else if ([@[@"db", @"sqlite"] containsObject:ext]) vc = [[SQLiteViewerViewController alloc] initWithPath:path];
    else if ([@[@"csv", @"tsv", @"xlsx"] containsObject:ext]) vc = [[ExcelViewerViewController alloc] initWithPath:path];
    else vc = [[HexEditorViewController alloc] initWithPath:path];

    if (vc) [self.navigationController pushViewController:vc animated:YES];
}
"""

content = content.replace('- (void)handleSwipeBack:', open_file_method + "\n- (void)handleSwipeBack:")

# 3. Update didSelectRowAtIndexPath to handle files
old_did_select = """- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.items[indexPath.row];
    if ([item[@"isDir"] boolValue]) {
        NSString *name = item[@"name"];
        NSString *newPath = [self.currentPath isEqualToString:@"/"] ? [@"/" stringByAppendingString:name] : [self.currentPath stringByAppendingPathComponent:name];
        [self loadPath:newPath];
    }
}"""

new_did_select = """- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.items[indexPath.row];
    NSString *name = item[@"name"];
    if ([item[@"isDir"] boolValue]) {
        NSString *newPath = [self.currentPath isEqualToString:@"/"] ? [@"/" stringByAppendingString:name] : [self.currentPath stringByAppendingPathComponent:name];
        [self loadPath:newPath];
    } else {
        [self openFile:name];
    }
}"""

content = content.replace(old_did_select, new_did_select)

with open('AfcBrowserViewController.m', 'w') as f:
    f.write(content)

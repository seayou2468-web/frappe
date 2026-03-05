#import <Foundation/Foundation.h>
#import "FileManagerCore.h"

// Mock NSHomeDirectory for testing if needed, or rely on actual if possible.
// However, NSHomeDirectory is a system function. We can test the logic as is.

void test_relativization() {
    NSString *home = NSHomeDirectory();
    NSString *docs = [home stringByAppendingPathComponent:@"Documents"];
    NSString *testPath = [docs stringByAppendingPathComponent:@"Downloads/file.txt"];

    NSString *rel = [FileManagerCore relativeToHomePath:testPath];
    NSLog(@"Absolute: %@", testPath);
    NSLog(@"Relative: %@", rel);

    NSString *abs = [FileManagerCore absoluteFromHomeRelativePath:rel];
    NSLog(@"Reconstructed: %@", abs);

    if ([testPath isEqualToString:abs]) {
        NSLog(@"SUCCESS: Path roundtrip matches.");
    } else {
        NSLog(@"FAILURE: Path roundtrip mismatch.");
    }
}

int main() {
    @autoreleasepool {
        test_relativization();
    }
    return 0;
}

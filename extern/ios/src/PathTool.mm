#import <Foundation/Foundation.h>

const char *getCacheDirectory() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *cacheDirectory = [paths.firstObject stringByAppendingPathComponent:@"Caches"];

    const char *cacheDir = [cacheDirectory UTF8String];

    return cacheDir;
}

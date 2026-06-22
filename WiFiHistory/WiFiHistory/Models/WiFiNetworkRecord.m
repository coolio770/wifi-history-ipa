#import "WiFiNetworkRecord.h"

@implementation WiFiNetworkRecord

- (instancetype)initWithSSID:(NSString *)ssid {
    self = [super init];
    if (self) {
        _ssid = [ssid copy];
        _isHidden = NO;
    }
    return self;
}

@end

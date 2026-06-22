#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WiFiNetworkRecord : NSObject

@property (nonatomic, copy) NSString *ssid;
@property (nonatomic, copy, nullable) NSString *password;
@property (nonatomic, copy, nullable) NSString *securityType;
@property (nonatomic, strong, nullable) NSDate *lastConnected;
@property (nonatomic, assign) BOOL isHidden;

- (instancetype)initWithSSID:(NSString *)ssid;

@end

NS_ASSUME_NONNULL_END

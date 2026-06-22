#import <Foundation/Foundation.h>
#import "WiFiNetworkRecord.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^WiFiHistoryLoadCompletion)(NSArray<WiFiNetworkRecord *> *networks, NSError * _Nullable error);

@interface WiFiHistoryManager : NSObject

+ (instancetype)sharedManager;

/// Loads merged Wi-Fi history (known-networks metadata + keychain passwords).
- (void)loadNetworkHistoryWithCompletion:(WiFiHistoryLoadCompletion)completion;

/// Synchronous load for simple table refresh.
- (NSArray<WiFiNetworkRecord *> *)loadNetworkHistory;

@end

NS_ASSUME_NONNULL_END

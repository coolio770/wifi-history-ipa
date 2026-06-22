#import "WiFiHistoryManager.h"
#import <Security/Security.h>

static NSArray<NSString *> *WiFiKnownNetworksPaths(void) {
    return @[
        @"/private/var/preferences/SystemConfiguration/com.apple.wifi.known-networks.plist",
        @"/var/preferences/SystemConfiguration/com.apple.wifi.known-networks.plist",
        @"/Library/Preferences/SystemConfiguration/com.apple.wifi.known-networks.plist"
    ];
}

@implementation WiFiHistoryManager

+ (instancetype)sharedManager {
    static WiFiHistoryManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[WiFiHistoryManager alloc] init];
    });
    return manager;
}

- (void)loadNetworkHistoryWithCompletion:(WiFiHistoryLoadCompletion)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<WiFiNetworkRecord *> *networks = [self loadNetworkHistory];
        NSError *error = nil;
        if (networks.count == 0) {
            error = [NSError errorWithDomain:@"WiFiHistory"
                                        code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"No Wi-Fi networks found. Ensure the device is jailbroken and entitlements are applied."}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(networks, error);
        });
    });
}

- (NSArray<WiFiNetworkRecord *> *)loadNetworkHistory {
    NSMutableDictionary<NSString *, WiFiNetworkRecord *> *bySSID = [NSMutableDictionary dictionary];

    [self mergeKnownNetworksPlistIntoMap:bySSID];
    [self mergeKeychainPasswordsIntoMap:bySSID];

    NSArray<WiFiNetworkRecord *> *sorted = [bySSID.allValues sortedArrayUsingComparator:^NSComparisonResult(WiFiNetworkRecord *a, WiFiNetworkRecord *b) {
        if (a.lastConnected && b.lastConnected) {
            return [b.lastConnected compare:a.lastConnected];
        }
        if (a.lastConnected) return NSOrderedAscending;
        if (b.lastConnected) return NSOrderedDescending;
        return [a.ssid compare:b.ssid];
    }];

    return sorted;
}

#pragma mark - Known networks plist

- (void)mergeKnownNetworksPlistIntoMap:(NSMutableDictionary<NSString *, WiFiNetworkRecord *> *)map {
    for (NSString *path in WiFiKnownNetworksPaths()) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            continue;
        }
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
        if (![plist isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        [self parseKnownNetworksPlist:plist intoMap:map];
        break;
    }
}

- (void)parseKnownNetworksPlist:(NSDictionary *)plist intoMap:(NSMutableDictionary<NSString *, WiFiNetworkRecord *> *)map {
    for (id key in plist) {
        id value = plist[key];
        if (![value isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *entry = (NSDictionary *)value;
        NSString *ssid = [self ssidFromKnownNetworkEntry:entry fallbackKey:key];
        if (ssid.length == 0) {
            continue;
        }

        WiFiNetworkRecord *record = map[ssid] ?: [[WiFiNetworkRecord alloc] initWithSSID:ssid];
        record.lastConnected = [self dateFromKnownNetworkEntry:entry];
        record.securityType = [self stringFromEntry:entry keys:@[@"SecurityType", @"securityType"]];
        record.isHidden = [[self stringFromEntry:entry keys:@[@"SSID", @"ssid"]] hasPrefix:@"\0"] || [entry[@"Hidden"] boolValue];

        map[ssid] = record;
    }
}

- (NSString *)ssidFromKnownNetworkEntry:(NSDictionary *)entry fallbackKey:(id)key {
    NSString *ssid = [self stringFromEntry:entry keys:@[@"SSID", @"ssid", @"SSID_STR"]];
    if (ssid.length > 0) {
        return ssid;
    }
    if ([key isKindOfClass:[NSString class]]) {
        return (NSString *)key;
    }
    if ([key isKindOfClass:[NSData class]]) {
        return [[NSString alloc] initWithData:(NSData *)key encoding:NSUTF8StringEncoding];
    }
    return nil;
}

- (NSDate *)dateFromKnownNetworkEntry:(NSDictionary *)entry {
    NSNumber *timestamp = entry[@"LastConnected"] ?: entry[@"lastConnected"] ?: entry[@"AddedAt"];
    if (![timestamp isKindOfClass:[NSNumber class]]) {
        return nil;
    }
    // iOS stores Wi-Fi timestamps as seconds since 2001-01-01 (CFAbsoluteTime).
    NSTimeInterval secondsSince2001 = timestamp.doubleValue;
    if (secondsSince2001 <= 0) {
        return nil;
    }
    return [NSDate dateWithTimeIntervalSinceReferenceDate:secondsSince2001];
}

- (NSString *)stringFromEntry:(NSDictionary *)entry keys:(NSArray<NSString *> *)keys {
    for (NSString *key in keys) {
        id value = entry[key];
        if ([value isKindOfClass:[NSString class]]) {
            return value;
        }
        if ([value isKindOfClass:[NSData class]]) {
            NSString *decoded = [[NSString alloc] initWithData:(NSData *)value encoding:NSUTF8StringEncoding];
            if (decoded.length > 0) {
                return decoded;
            }
        }
    }
    return nil;
}

#pragma mark - Keychain (AirPort service)

- (void)mergeKeychainPasswordsIntoMap:(NSMutableDictionary<NSString *, WiFiNetworkRecord *> *)map {
    NSArray<NSDictionary *> *items = [self keychainAirPortItems];
    for (NSDictionary *item in items) {
        NSString *ssid = item[(__bridge id)kSecAttrAccount];
        if (![ssid isKindOfClass:[NSString class]] || ssid.length == 0) {
            continue;
        }

        NSData *passwordData = item[(__bridge id)kSecValueData];
        NSString *password = passwordData ? [[NSString alloc] initWithData:passwordData encoding:NSUTF8StringEncoding] : nil;

        WiFiNetworkRecord *record = map[ssid] ?: [[WiFiNetworkRecord alloc] initWithSSID:ssid];
        if (password.length > 0) {
            record.password = password;
        }
        NSString *label = item[(__bridge id)kSecAttrLabel];
        if (!record.securityType.length && [label isKindOfClass:[NSString class]]) {
            record.securityType = label;
        }
        map[ssid] = record;
    }
}

- (NSArray<NSDictionary *> *)keychainAirPortItems {
    NSMutableArray<NSDictionary *> *results = [NSMutableArray array];

    NSArray<NSString *> *accessGroups = @[@"apple", @"com.apple.identities", @"lockdown-identities"];
    for (NSString *group in accessGroups) {
        NSArray *groupItems = [self keychainAirPortItemsForAccessGroup:group];
        [results addObjectsFromArray:groupItems];
    }

    // Fallback query without access group (works on some jailbreak setups).
    NSArray *ungrouped = [self keychainAirPortItemsForAccessGroup:nil];
    [results addObjectsFromArray:ungrouped];

    return results;
}

- (NSArray<NSDictionary *> *)keychainAirPortItemsForAccessGroup:(NSString * _Nullable)accessGroup {
    NSMutableDictionary *query = [@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"AirPort",
        (__bridge id)kSecReturnAttributes: @YES,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll
    } mutableCopy];

    if (accessGroup.length > 0) {
        query[(__bridge id)kSecAttrAccessGroup] = accessGroup;
    }

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || result == NULL) {
        return @[];
    }

    id items = (__bridge_transfer id)result;
    if ([items isKindOfClass:[NSDictionary class]]) {
        return @[items];
    }
    if ([items isKindOfClass:[NSArray class]]) {
        return items;
    }
    return @[];
}

@end

//
//  MPCompileDiagnostics.h
//  MetaGlyphs
//
//  Created by Georg Seifert on 21.10.26.
//
//

#import <Foundation/Foundation.h>
@class GSLayer;

NS_ASSUME_NONNULL_BEGIN
extern NSNotificationName const MPCompileDiagnosticsDidChangeNotification;

// Session-only results. Errors never become part of the saved font.
@interface MPCompileDiagnostics : NSObject
@property (class, nonatomic, readonly) MPCompileDiagnostics *sharedDiagnostics;
+ (NSArray *)sourceStateForLayer:(GSLayer *)layer;
- (void)recordError:(nullable NSError *)error forLayer:(GSLayer *)layer sourceState:(NSArray *)sourceState;
// nil means no result for the current source; NSNull in "error" means success.
- (nullable NSDictionary *)resultForLayer:(GSLayer *)layer;
- (void)clear;
@end
NS_ASSUME_NONNULL_END

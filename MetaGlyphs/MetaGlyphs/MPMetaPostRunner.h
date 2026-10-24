//
//  MPMetaPostRunner.h
//  MetaGlyphs
//
//  Created by Georg Seifert on 21.10.26.
//
//


#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
extern NSErrorDomain const MPMetaPostErrorDomain;

/// Replaceable engine boundary: glyph-body source in, MetaPost SVG out.
@interface MPMetaPostRunner : NSObject
@property (nonatomic, copy, readonly, nullable) NSString *executablePath;
@property (nonatomic, copy, readonly, nullable) NSString *supportDirectory;
/// Loads the runtime bundled in the plugin.
- (instancetype)init;
/// Explicit engine path for standalone tests and tools; nil uses the bundle.
- (instancetype)initWithExecutablePath:(nullable NSString *)path;
- (nullable NSData *)SVGForBody:(NSString *)body parameters:(NSDictionary<NSString *, NSNumber *> *)parameters error:(NSError **)error;
- (nullable NSData *)SVGForBody:(NSString *)body globalCode:(NSString *)globalCode
                    parameters:(NSDictionary<NSString *, NSNumber *> *)parameters
                     sourceURL:(nullable NSURL *)sourceURL
                  dependencies:(NSDictionary<NSString *, NSData *> * _Nullable * _Nullable)dependencies
                         error:(NSError **)error;
+ (NSString *)programForBody:(NSString *)body parameters:(NSDictionary<NSString *, NSNumber *> *)parameters;
+ (NSString *)programForBody:(NSString *)body globalCode:(NSString *)globalCode parameters:(NSDictionary<NSString *, NSNumber *> *)parameters;
@end
NS_ASSUME_NONNULL_END

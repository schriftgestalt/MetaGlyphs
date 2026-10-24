//
//  MPOutlineImporter.h
//  MetaGlyphs
//
//  Created by Georg Seifert on 21.10.26.
//
//


#import <Cocoa/Cocoa.h>
@class GSLayer;

NS_ASSUME_NONNULL_BEGIN
@interface MPOutlineImporter : NSObject
/// Detached, flattened outlines in the original font coordinate system.
+ (nullable GSLayer *)layerFromSVG:(NSData *)svg error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END

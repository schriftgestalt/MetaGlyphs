//
//  MetaGlyphs.h
//  MetaGlyphs
//
//  Created by Georg Seifert on 21.10.26.
//  
//

#import <Cocoa/Cocoa.h>

#import <GlyphsApp/GlyphsPluginProtocol.h>
#import <GlyphsCore/GlyphsFilterCoreProtocol.h>

@interface MetaGlyphs : NSObject <GlyphsPlugin>

- (BOOL)processLayer:(nonnull GSLayer *)layer supporting:(GSDrawStackFeature)supportedFeatures extraHandles:(nullable NSMutableArray *)extraHandles error:(NSError * _Nullable * _Nullable)error;

@end

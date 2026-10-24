//
//  MPCompileDiagnostics.m
//  MetaGlyphs
//
//  Created by Georg Seifert on 21.10.26.
//
//

#import "MPCompileDiagnostics.h"
#import <GlyphsCore/GSLayer.h>
#import <GlyphsCore/GSGlyph.h>
#import <GlyphsCore/GSFont.h>

NSNotificationName const MPCompileDiagnosticsDidChangeNotification = @"com.GeorgSeifert.metapost.diagnosticsChanged";

@interface MPCompileDiagnostics ()
@property (nonatomic, strong) NSMapTable<GSGlyph *, NSMutableDictionary<NSString *, NSDictionary *> *> *results;
@property (nonatomic, strong) NSMapTable<GSLayer *, NSDictionary *> *unidentifiedResults;
@end

@implementation MPCompileDiagnostics
+ (MPCompileDiagnostics *)sharedDiagnostics {
	static MPCompileDiagnostics *diagnostics;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ diagnostics = [self new]; });
	return diagnostics;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_results = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory];
		_unidentifiedResults = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory];
	}
	return self;
}

+ (NSArray *)sourceStateForLayer:(GSLayer *)layer {
	id glyphSource = [layer.glyph userDataForKey:@"metaFont"] ?: @"";
	id globalSource = [layer.font userDataForKey:@"metaFont"] ?: @"";
	// Copy text: NSTextView can otherwise expose mutable backing storage.
	return @[@([glyphSource isKindOfClass:NSString.class]), [[glyphSource description] copy],
		@([globalSource isKindOfClass:NSString.class]), [[globalSource description] copy],
		layer.font.fileURL.path ?: @"", @(layer.width)];
}

- (void)notifyChange {
	// Preparation can run off the main thread. Defer UI updates, and never
	// trigger another preparation from the notification handler.
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSNotificationCenter.defaultCenter postNotificationName:MPCompileDiagnosticsDidChangeNotification object:self];
	});
}

- (void)recordError:(NSError *)error forLayer:(GSLayer *)layer sourceState:(NSArray *)sourceState {
	GSGlyph *glyph = layer.glyph;
	if (!glyph) return;
	NSDictionary *result = @{@"source": sourceState, @"error": error ?: NSNull.null};
	@synchronized (self) {
		if (!layer.layerId.length) {
			// Detached layers need their own identity rather than a shared nil key.
			if ([[self.unidentifiedResults objectForKey:layer] isEqual:result]) return;
			[self.unidentifiedResults setObject:result forKey:layer];
		} else {
			NSMutableDictionary *layers = [self.results objectForKey:glyph];
			if ([layers[layer.layerId] isEqual:result]) return;
			if (!layers) {
				layers = [NSMutableDictionary new];
				[self.results setObject:layers forKey:glyph];
			}
			layers[layer.layerId] = result;
		}
	}
	[self notifyChange];
}

- (NSDictionary *)resultForLayer:(GSLayer *)layer {
	if (!layer.glyph) return nil;
	NSArray *sourceState = [MPCompileDiagnostics sourceStateForLayer:layer];
	@synchronized (self) {
		NSDictionary *result = layer.layerId.length ? [self.results objectForKey:layer.glyph][layer.layerId] : [self.unidentifiedResults objectForKey:layer];
		return [result[@"source"] isEqual:sourceState] ? result : nil;
	}
}

- (void)clear {
	@synchronized (self) { [self.results removeAllObjects]; [self.unidentifiedResults removeAllObjects]; }
	[self notifyChange];
}
@end

//
//  MetaGlyphs.m
//  MetaGlyphs
//
//  Created by Georg Seifert on 21.10.26.
//  
//

#import "MetaGlyphs.h"
#import <GlyphsApp/GSCallbackHandler.h>
#import <GlyphsCore/GSFilterHandler.h>
#import <GlyphsCore/GSLayer.h>
#import <GlyphsCore/GSGlyph.h>
#import <GlyphsCore/GSFont.h>
#import <GlyphsCore/GSFontMaster.h>
#import <GlyphsCore/GSMetric.h>
#import "MPMetaPostRunner.h"
#import "MPOutlineImporter.h"
#import "MPCodeSidebarController.h"
#import "MPCompileDiagnostics.h"

@interface MetaGlyphs ()
@property (nonatomic, strong) MPMetaPostRunner *runner;
@property (nonatomic, strong) NSCache<NSArray *, NSDictionary *> *outlineCache;
@end

static double MPMetric(GSLayer *layer, GSMetricsType type, double fallback) {
	if (!layer.font) return fallback;
	double value = [layer metricForType:type];
	return isfinite(value) && value != NSNotFound ? value : fallback;
}

@implementation MetaGlyphs

- (instancetype)init {
	self = [super init];
	if (self) {
		_runner = [MPMetaPostRunner new];
		_outlineCache = [NSCache new];
		_outlineCache.countLimit = 64;
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadImports:) name:MPReloadImportsNotification object:nil];
	}
	return self;
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)reloadImports:(NSNotification *)notification {
	[self.outlineCache removeAllObjects];
	[MPCompileDiagnostics.sharedDiagnostics clear];
}

- (NSUInteger)interfaceVersion {
	// Distinguishes the API version the plugin was built for. Return 1.
	return 1;
}

- (void)loadPlugin {
	[GSCallbackHandler addEditViewLeftSidebarController:MPCodeSidebarController.class];
	[GSFilterHandler addLayerCallback:self forOperation:GSPrepareLayerCallbackName];
	[GSCallbackHandler addCallback:self forOperation:GSDrawBackgroundCallbackName];
}

- (NSString *)codeForLayer:(GSLayer *)layer {
	return [layer.glyph userDataForKey:@"metaFont"];
}

- (BOOL)needsProcessingLayer:(GSLayer *)layer {
	id code = [self codeForLayer:layer];
	return code != nil;
}

- (BOOL)processLayer:(nonnull GSLayer *)layer supporting:(GSDrawStackFeature)supportedFeatures extraHandles:(nullable NSMutableArray *)extraHandles error:(out NSError **)error {
	NSArray *sourceState = [MPCompileDiagnostics sourceStateForLayer:layer];
	NSError *generationError = nil;
	BOOL success = [self generateLayer:layer error:&generationError];
	[MPCompileDiagnostics.sharedDiagnostics recordError:success ? nil : generationError forLayer:layer sourceState:sourceState];
	if (error) *error = generationError;
	return success;
}

- (BOOL)generateLayer:(GSLayer *)layer error:(NSError **)error {
	id code = [self codeForLayer:layer];
	if (!code) {
		return YES;
	}
	if (![code isKindOfClass:NSString.class]) {
		if (error) *error = [NSError errorWithDomain:MPMetaPostErrorDomain
												code:7
											userInfo:@{
			NSLocalizedDescriptionKey: @"The glyph’s metaFont user data must be a source-code string."
		}];
		return NO;
	}
	if (![[code stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length]) {
		return YES;
	}
	id global = [layer.font userDataForKey:@"metaFont"] ?: @"";
	if (![global isKindOfClass:NSString.class]) {
		if (error) *error = [NSError errorWithDomain:MPMetaPostErrorDomain code:7 userInfo:
			@{NSLocalizedDescriptionKey: @"The font’s metaFont user data must be a source-code string."}];
		return NO;
	}
	NSMutableDictionary *parameters = [NSMutableDictionary new];
	GSFontMaster *master = layer.associatedFontMasterFast;
	for (GSAxis *axis in layer.font.axes) {
		CGFloat axisValue = [master axisInternalValueValueForId:axis.axisId];
		parameters[axis.axisTag] = @(axisValue);
	}

	if (layer.isBraceLayer) {
		for (GSAxis *axis in layer.font.axes) {
			NSNumber *axisValue = [layer axisInternalValueForId:axis.axisId];
			if (axisValue) {
				parameters[axis.axisTag] = axisValue;
			}
		}
		for (GSAxis *axis in layer.glyph.axes) {
			CGFloat axisValue = [layer axisInternalValueValueForId:axis.axisId];
			if (axisValue < NSNotFound) {
				parameters[axis.name] = @(axisValue);
			}
		}
	}
	double upm = layer.font ? layer.font.unitsPerEm : 1000;

	parameters[@"w"] = @(layer.width);
	parameters[@"upm"] = @(upm);
	parameters[@"u"] = @(upm / 1000.0);
	parameters[@"h"] = @(MPMetric(layer, GSMetricsTypeCapHeight, 700));
	parameters[@"d"] = @(-MPMetric(layer, GSMetricsTypeDescender, -200));
	parameters[@"ascender"] = @(MPMetric(layer, GSMetricsTypeAscender, 800));
	parameters[@"descender"] = @(MPMetric(layer, GSMetricsTypeDescender, -200));
	parameters[@"capheight"] = @(MPMetric(layer, GSMetricsTypeCapHeight, 700));
	parameters[@"xheight"] = @(MPMetric(layer, GSMetricsTypexHeight, 500));

	NSURL *sourceURL = layer.font.fileURL;
	NSArray *key = @[[MPMetaPostRunner programForBody:code globalCode:global parameters:parameters], sourceURL.path ?: @""];
	NSDictionary *cached = [self.outlineCache objectForKey:key];
	for (NSString *path in cached[@"dependencies"]) {
		if (![cached[@"dependencies"][path] isEqual:[NSData dataWithContentsOfFile:path]]) {
			cached = nil;
			break;
		}
	}
	// An absent import can be created without editing either code buffer.
	if (cached[@"error"] && [cached[@"expires"] timeIntervalSinceNow] <= 0) cached = nil;
	if (cached[@"error"]) {
		if (error) {
			*error = cached[@"error"];
		}
		return NO;
	}
	GSLayer *generated = cached[@"layer"];
	if (!generated) {
		NSError *generationError = nil;
		NSDictionary *dependencies = nil;
		NSData *svg = [self.runner SVGForBody:code globalCode:global parameters:parameters sourceURL:sourceURL dependencies:&dependencies error:&generationError];
		if (svg) {
			generated = [MPOutlineImporter layerFromSVG:svg error:&generationError];
		}
		if (!generated) {
			if (!generationError) {
				generationError = [NSError errorWithDomain:MPMetaPostErrorDomain
													  code:8
												  userInfo:@{
					NSLocalizedDescriptionKey: @"MetaPost did not generate an outline."
				}];
			}
			// A broken or looping snippet must not recompile on every redraw.
			[self.outlineCache setObject:@{@"error": generationError, @"dependencies": dependencies ?: @{}, @"expires": [NSDate dateWithTimeIntervalSinceNow:1]} forKey:key];
			if (error) {
				*error = generationError;
			}
			return NO;
		}
		[self.outlineCache setObject:@{@"layer": generated, @"dependencies": dependencies ?: @{}} forKey:key];
	}
	// This callback processes the layer prepared for output. Reuse no mutable
	// paths from the cache; keep the glyph's stored code and source layer intact.
	GSLayer *copy = [generated copy];
	[layer setShapes:copy.shapes hints:@[]];
	return YES;
}

@end

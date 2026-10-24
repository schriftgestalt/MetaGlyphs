//
//  MPOutlineImporter.m
//  MetaGlyphs
//
//  Created by Georg Seifert on 21.10.26.
//
//


#import "MPOutlineImporter.h"
#import "MPMetaPostRunner.h"
#import <GlyphsCore/GSLayer.h>
#import <GlyphsCore/GSPath.h>
#import <GlyphsCore/GSPathPen.h>
#import <GlyphsCore/GSPathOperator.h>

static BOOL MPImportError(NSError **error, NSString *message) {
	if (error) {
		*error = [NSError errorWithDomain:MPMetaPostErrorDomain code:5 userInfo:@{NSLocalizedDescriptionKey: message}];
	}
	return NO;
}

static NSDictionary *MPStyles(NSXMLElement *node, NSDictionary *inherited) {
	NSMutableDictionary *styles = [inherited mutableCopy];
	for (NSXMLNode *attribute in node.attributes) {
		styles[attribute.name] = attribute.stringValue;
	}
	for (NSString *entry in [[node attributeForName:@"style"].stringValue componentsSeparatedByString:@";"]) {
		NSRange colon = [entry rangeOfString:@":"];
		if (colon.location == NSNotFound) {
			continue;
		}
		NSCharacterSet *spaces = NSCharacterSet.whitespaceAndNewlineCharacterSet;
		styles[[[entry substringToIndex:colon.location] stringByTrimmingCharactersInSet:spaces]] =
		[[entry substringFromIndex:NSMaxRange(colon)] stringByTrimmingCharactersInSet:spaces];
	}
	return styles;
}

static NSArray<NSNumber *> *MPNumbers(NSString *string) {
	NSScanner *scanner = [NSScanner scannerWithString:string ?: @""];
	scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	scanner.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@" ,\t\r\n"];
	NSMutableArray *numbers = [NSMutableArray new];
	double value;
	while ([scanner scanDouble:&value]) {
		if (!isfinite(value)) {
			return nil;
		}
		[numbers addObject:@(value)];
	}
	return scanner.isAtEnd ? numbers : nil;
}

// Keep the centre line in Core Graphics until after stroke expansion. A native
// glyph-path / Bezier conversion must not implicitly close an open SVG stroke.
// MetaPost emits move, line, cubic and close commands; also accept the SVG
// shorthand/relative forms without routing them through font outlines.
static CGPathRef MPCreateSVGPath(NSString *source, NSError **error) CF_RETURNS_RETAINED {
	NSScanner *scanner = [NSScanner scannerWithString:source ?: @""];
	scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	scanner.charactersToBeSkipped = nil;
	NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@" ,\t\r\n"];
	CGMutablePathRef path = CGPathCreateMutable();
	unichar command = 0, previous = 0;
	CGPoint control = CGPointZero;
	BOOL hasMove = NO;
	while (YES) {
		[scanner scanCharactersFromSet:separators intoString:NULL];
		if (scanner.isAtEnd) {
			break;
		}
		unichar next = [source characterAtIndex:scanner.scanLocation];
		if ((next >= 'A' && next <= 'Z') || (next >= 'a' && next <= 'z')) {
			command = next;
			scanner.scanLocation++;
		}
		BOOL relative = command >= 'a' && command <= 'z';
		unichar upper = relative ? command - ('a' - 'A') : command;
		if ((!hasMove && upper != 'M') || !command) {
			goto invalid;
		}
		if (upper == 'Z') {
			CGPathCloseSubpath(path);
			previous = upper;
			command = 0;
			continue;
		}
		NSUInteger count;
		switch (upper) {
			case 'M':
			case 'L':
			case 'T':
				count = 2;
				break;
			case 'H':
			case 'V':
				count = 1;
				break;
			case 'C':
				count = 6;
				break;
			case 'S':
			case 'Q':
				count = 4;
				break;
			default:
				goto invalid;
		}
		double values[6];
		for (NSUInteger idx = 0; idx < count; idx++) {
			[scanner scanCharactersFromSet:separators intoString:NULL];
			if (![scanner scanDouble:&values[idx]] || !isfinite(values[idx])) {
				goto invalid;
			}
		}
		CGPoint current = CGPathGetCurrentPoint(path);
		CGPoint points[3];
		if (upper == 'H' || upper == 'V') {
			points[0] = current;
			if (upper == 'H') {
				points[0].x = values[0] + (relative ? current.x : 0);
			}
			else {
				points[0].y = values[0] + (relative ? current.y : 0);
			}
		}
		else {
			for (NSUInteger i = 0; i < count / 2; i++) {
				points[i] = CGPointMake(values[i * 2] + (relative ? current.x : 0), values[i * 2 + 1] + (relative ? current.y : 0));
			}
		}
		for (NSUInteger i = 0; i < MAX((NSUInteger)1, count / 2); i++) {
			if (!isfinite(points[i].x) || !isfinite(points[i].y)) {
				goto invalid;
			}
		}
		CGPoint reflected = CGPointMake(2 * current.x - control.x, 2 * current.y - control.y);
		switch (upper) {
			case 'M':
				CGPathMoveToPoint(path, NULL, points[0].x, points[0].y);
				hasMove = YES;
				command = relative ? 'l' : 'L';
				break;
			case 'L': case 'H': case 'V':
				CGPathAddLineToPoint(path, NULL, points[0].x, points[0].y); break;
			case 'C':
				CGPathAddCurveToPoint(path, NULL, points[0].x, points[0].y, points[1].x, points[1].y, points[2].x, points[2].y);
				control = points[1];
				break;
			case 'S': {
				CGPoint first = previous == 'C' || previous == 'S' ? reflected : current;
				CGPathAddCurveToPoint(path, NULL, first.x, first.y, points[0].x, points[0].y, points[1].x, points[1].y);
				control = points[0];
				break;
			}
			case 'Q':
				CGPathAddQuadCurveToPoint(path, NULL, points[0].x, points[0].y, points[1].x, points[1].y);
				control = points[0];
				break;
			case 'T': {
				CGPoint first = previous == 'Q' || previous == 'T' ? reflected : current;
				CGPathAddQuadCurveToPoint(path, NULL, first.x, first.y, points[0].x, points[0].y);
				control = first;
				break;
			}
		}
		previous = upper;
	}
	if (hasMove) {
		return path;
	}
invalid:
	CGPathRelease(path);
	MPImportError(error, @"MetaPost generated an invalid or unsupported SVG path.");
	return NULL;
}

// -1 = no paint, 0 = black, 1 = white knockout, 2 = unsupported color.
static NSInteger MPPaint(NSString *paint) {
	if ([paint isEqualToString:@"none"]) return -1;
	if ([paint isEqualToString:@"black"] || [paint isEqualToString:@"#000000"] || [paint isEqualToString:@"#000"]) {
		return 0;
	}
	if ([paint isEqualToString:@"white"] || [paint isEqualToString:@"#ffffff"] || [paint isEqualToString:@"#fff"]) {
		return 1;
	}
	if ([paint hasPrefix:@"rgb("] && [paint hasSuffix:@")"]) {
		BOOL percent = [paint containsString:@"%"];
		NSString *values = [[paint substringWithRange:NSMakeRange(4, paint.length - 5)] stringByReplacingOccurrencesOfString:@"%" withString:@""];
		NSArray *numbers = MPNumbers(values);
		if (numbers.count == 3) {
			BOOL black = YES;
			BOOL white = YES;
			for (NSNumber *number in numbers) {
				black &= fabs(number.doubleValue) < .00001;
				white &= fabs(number.doubleValue - (percent ? 100 : 255)) < .00001;
			}
			if (black) {
				return 0;
			}
			if (white) {
				return 1;
			}
		}
	}
	return 2;
}

static BOOL MPAppend(CGPathRef path, NSInteger paint, CGAffineTransform transform, GSLayer *output, NSError **error) {
	if (paint < 0) {
		return YES;
	}
	if (paint > 1) {
		return MPImportError(error, @"Use black drawing and white unfill operations for monochrome glyphs.");
	}
	CGPathRef transformed = CGPathCreateCopyByTransformingPath(path, &transform);
	GSLayer *part = [GSLayer new];
	GSPathPen *pen = [[GSPathPen alloc] initWithLayer:part];
	__block BOOL finite = YES;
	CGPathApplyWithBlock(transformed, ^(const CGPathElement *element) {
		const CGPoint *p = element->points;
		NSInteger count = element->type == kCGPathElementAddCurveToPoint ? 3 :
		element->type == kCGPathElementAddQuadCurveToPoint ? 2 :
		element->type == kCGPathElementCloseSubpath ? 0 : 1;
		for (NSInteger i = 0; i < count; i++) {
			finite &= isfinite(p[i].x) && isfinite(p[i].y);
		}
		if (!finite) {
			return;
		}
		switch (element->type) {
			case kCGPathElementMoveToPoint:
				if (pen.currentPath) {
					[pen closePath];
				}
				[pen moveTo:p[0]];
				break;
			case kCGPathElementAddLineToPoint:
				[pen lineTo:p[0]];
				break;
			case kCGPathElementAddQuadCurveToPoint:
				[pen qCurveWithPoints:p count:2];
				break;
			case kCGPathElementAddCurveToPoint:
				[pen curveTo:p[2] off1:p[0] off2:p[1]];
				break;
			case kCGPathElementCloseSubpath:
				[pen closePath];
				break;
		}
	});
	if (pen.currentPath) {
		[pen closePath];
	}
	CGPathRelease(transformed);
	if (!finite) {
		return MPImportError(error, @"MetaPost generated a non-finite coordinate.");
	}
	// Resolve each paint operation before combining it with earlier operations.
	// Otherwise two independently filled, opposite-winding paths cancel where
	// they overlap, although MetaPost paints that region solid.
	if (part.countOfShapes) {
		NSMutableArray *paths = [part.shapes mutableCopy];
		if (![GSPathOperator removeOverlapPaths:paths error:error]) return NO;
		[part setShapesFast:paths];
		[part correctPathDirection];
	}
	if (paint == 0) {
		[output setShapesFast:[output.shapes arrayByAddingObjectsFromArray:part.shapes]];
	}
	else {
		NSMutableArray *paths = [output.shapes mutableCopy];
		if (![GSPathOperator subtractPaths:(NSArray<GSPath *> *)part.shapes from:paths error:error]) {
			return NO;
		}
		[output setShapesFast:paths];
	}
	return YES;
}

static BOOL MPReadNode(NSXMLElement *node, NSDictionary *inherited, CGAffineTransform parent, GSLayer *output, NSError **error) {
	NSDictionary *styles = MPStyles(node, inherited);
	if (styles[@"clip-path"]) {
		return MPImportError(error, @"MetaPost clipping is not supported yet.");
	}
	NSString *tag = node.localName;
	if (![@[@"svg", @"g", @"path"] containsObject:tag]) {
		return MPImportError(error, @"Use paths in glyph code; text, labels, and other SVG objects are not supported yet.");
	}
	CGAffineTransform transform = parent;
	NSString *matrix = [node attributeForName:@"transform"].stringValue;
	if (matrix.length) {
		if (![matrix hasPrefix:@"matrix("] || ![matrix hasSuffix:@")"]) return MPImportError(error, @"Unsupported SVG transformation from MetaPost.");
		NSArray *v = MPNumbers([matrix substringWithRange:NSMakeRange(7, matrix.length - 8)]);
		if (v.count != 6) {
			return MPImportError(error, @"Invalid SVG transformation from MetaPost.");
		}
		CGAffineTransform local = CGAffineTransformMake([v[0] doubleValue], [v[1] doubleValue], [v[2] doubleValue], [v[3] doubleValue], [v[4] doubleValue], [v[5] doubleValue]);
		transform = CGAffineTransformConcat(local, parent);
	}
	if (![tag isEqualToString:@"path"]) {
		for (NSXMLNode *child in node.children) if (child.kind == NSXMLElementKind && !MPReadNode((NSXMLElement *)child, styles, transform, output, error)) {
			return NO;
		}
		return YES;
	}
	NSString *d = [node attributeForName:@"d"].stringValue;
	CGPathRef path = MPCreateSVGPath(d, error);
	if (!path) {
		return NO;
	}
	BOOL ok = MPAppend(path, MPPaint(styles[@"fill"] ?: @"black"), transform, output, error);
	NSInteger paint = MPPaint(styles[@"stroke"] ?: @"none");
	if (ok && paint >= 0) {
		double width = styles[@"stroke-width"] ? [styles[@"stroke-width"] doubleValue] : 1;
		if (!isfinite(width) || width < 0) {
			ok = MPImportError(error, @"Invalid pen width from MetaPost.");
		}
		else if (width > 0) {
			CGLineCap cap = [styles[@"stroke-linecap"] isEqual:@"round"] ? kCGLineCapRound : [styles[@"stroke-linecap"] isEqual:@"square"] ? kCGLineCapSquare : kCGLineCapButt;
			CGLineJoin join = [styles[@"stroke-linejoin"] isEqual:@"round"] ? kCGLineJoinRound : [styles[@"stroke-linejoin"] isEqual:@"bevel"] ? kCGLineJoinBevel : kCGLineJoinMiter;
			double miter = styles[@"stroke-miterlimit"] ? [styles[@"stroke-miterlimit"] doubleValue] : 4;
			if (styles[@"stroke-dasharray"]) {
				ok = MPImportError(error, @"Dashed pen strokes are not supported yet.");
			}
			else if (!isfinite(miter) || miter <= 0) {
				ok = MPImportError(error, @"Invalid pen join from MetaPost.");
			}
			else {
				// Expand before the matrix to preserve elliptical/rotated pens.
				CGPathRef stroke = CGPathCreateCopyByStrokingPath(path, NULL, width, cap, join, miter);
				ok = MPAppend(stroke, paint, transform, output, error);
				CGPathRelease(stroke);
			}
		}
	}
	CGPathRelease(path);
	return ok;
}

@implementation MPOutlineImporter
+ (GSLayer *)layerFromSVG:(NSData *)svg error:(NSError **)error {

	NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:svg options:NSXMLNodeLoadExternalEntitiesNever error:error];
	if (!document) {
		return nil;
	}
	NSString *source = [[NSString alloc] initWithData:svg encoding:NSUTF8StringEncoding];
	NSRange marker = [source rangeOfString:@"<!-- Original BoundingBox:"];
	double minX = 0, minY = 0, maxX = 0, maxY = 0;
	BOOL valid = source && marker.location != NSNotFound && [document.rootElement.localName isEqualToString:@"svg"];
	if (valid) {
		NSScanner *scanner = [NSScanner scannerWithString:[source substringFromIndex:NSMaxRange(marker)]];
		scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
		valid = [scanner scanDouble:&minX] && [scanner scanDouble:&minY] && [scanner scanDouble:&maxX] && [scanner scanDouble:&maxY] &&
		isfinite(minX) && isfinite(minY) && isfinite(maxX) && isfinite(maxY);
	}
	if (!valid) {
		MPImportError(error, @"MetaPost did not produce an SVG with original font coordinates.");
		return nil;
	}
	// Inverse of the translation/Y reflection in upstream svgout.w; no scaling.
	CGAffineTransform transform = CGAffineTransformMake(1, 0, 0, -1, MIN(minX, 0), maxY);
	GSLayer *layer = [GSLayer new];
	if (!MPReadNode(document.rootElement, @{}, transform, layer, error)) return nil;
	if (layer.countOfShapes) {
		NSMutableArray *paths = [layer.shapes mutableCopy];
		if (![GSPathOperator removeOverlapPaths:paths error:error]) {
			return nil;
		}
		[layer setShapesFast:paths];
	}
	return layer;
}

@end

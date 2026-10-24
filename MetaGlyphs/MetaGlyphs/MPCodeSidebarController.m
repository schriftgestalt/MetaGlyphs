//
//  MPCodeSidebarController.m
//  MetaGlyphs
//
//  Created by Georg Seifert on 21.10.26.
//
//


#import "MPCodeSidebarController.h"
#import "MPCompileDiagnostics.h"
#import <GlyphsApp/GSEditViewController.h>
#import <GlyphsApp/GSGlyphEditView.h>
#import <GlyphsCore/GSLayer.h>
#import <GlyphsCore/GSGlyph.h>
#import <GlyphsCore/GSFont.h>
#import <GlyphsCore/GSUndoManager.h>

static void *MPActiveLayerContext = &MPActiveLayerContext;
static void *MPSourceContext = &MPSourceContext;
NSNotificationName const MPReloadImportsNotification = @"com.GeorgSeifert.metapost.reloadImports";

// Let the glyph own undo. NSTextView's independent text undo registrations
// would otherwise duplicate model edits and survive switching glyphs.
@interface MPCodeTextView : NSTextView
@property (nonatomic, weak, nullable) NSUndoManager *codeUndoManager;
@end
@implementation MPCodeTextView
- (void)highlightSyntax {
	// Display-only colors leave plain source, selection and model undo untouched.
	NSLayoutManager *layout = self.layoutManager;
	NSString *source = self.string;
	[layout removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:NSMakeRange(0, source.length)];
	static NSRegularExpression *tokens;
	static NSSet<NSString *> *structureKeywords;
	static NSSet<NSString *> *drawingKeywords;
	static NSSet<NSString *> *geometryKeywords;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		// Strings and comments come first so their contents are never tokenized.
		// Metafont strings have no backslash escapes and end at the line boundary.
		tokens = [NSRegularExpression regularExpressionWithPattern:@"%[^\\r\\n]*|\"[^\"\\r\\n]*\"?|[0-9]+(?:\\.[0-9]+)?|(?<!\\.)\\.[0-9]+|[A-Za-z_]+" options:0 error:NULL];
		structureKeywords = [NSSet setWithArray:[@"def vardef primarydef secondarydef tertiarydef enddef expr suffix text primary secondary tertiary "
			"if elseif else fi for forsuffixes forever endfor exitif step until upto downto "
			"begingroup endgroup save interim let newinternal input end dump "
			"numeric pair path pen picture transform string boolean true false known unknown "
			"beginchar endchar beginfig endfig mode_setup font_size font_identifier and or not "
			"show showvariable message errmessage btex etex verbatimtex"
			componentsSeparatedByString:@" "]];
		drawingKeywords = [NSSet setWithArray:[@"draw undraw fill unfill filldraw unfilldraw pickup currentpen pencircle nullpen "
			"withpen withcolor withrgbcolor withcmykcolor withgreyscale dashed clipped to special shipout"
			componentsSeparatedByString:@" "]];
		geometryKeywords = [NSSet setWithArray:[@"fullcircle halfcircle quartercircle unitsquare cycle controls tension atleast "
			"shifted scaled xscaled yscaled zscaled rotated slanted transformed reflectedabout rotatedaround "
			"dir point of precontrol postcontrol subpath reverse length unitvector direction directiontime "
			"intersectiontimes intersectionpoint makepath makepen buildcycle cutbefore cutafter "
			"abs sqrt sind cosd angle floor ceiling round min max mod div decimal"
			componentsSeparatedByString:@" "]];
	});
	[tokens enumerateMatchesInString:source options:0 range:NSMakeRange(0, source.length) usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
		NSString *token = [source substringWithRange:match.range];
		unichar first = [token characterAtIndex:0];
		NSColor *color = nil;
		if (first == '%') color = NSColor.secondaryLabelColor;
		else if (first == '"') color = NSColor.systemRedColor;
		else if ((first >= '0' && first <= '9') || first == '.') color = NSColor.systemBlueColor;
		else if ([structureKeywords containsObject:token]) color = NSColor.systemPurpleColor;
		else if ([drawingKeywords containsObject:token]) color = NSColor.systemBrownColor;
		else if ([geometryKeywords containsObject:token]) color = NSColor.systemTealColor;
		if (color) [layout addTemporaryAttribute:NSForegroundColorAttributeName value:color forCharacterRange:match.range];
	}];
}

- (void)setString:(NSString *)string {
	[super setString:string];
	[self highlightSyntax];
}

- (void)didChangeText {
	[self highlightSyntax];
	[super didChangeText];
}

- (NSUndoManager *)undoManager { return self.codeUndoManager; }
- (void)undo:(id)sender { if (self.codeUndoManager.canUndo) [self.codeUndoManager undo]; }
- (void)redo:(id)sender { if (self.codeUndoManager.canRedo) [self.codeUndoManager redo]; }
- (BOOL)validateMenuItem:(NSMenuItem *)item {
	if (item.action == @selector(undo:)) return self.codeUndoManager.canUndo;
	if (item.action == @selector(redo:)) return self.codeUndoManager.canRedo;
	return [super validateMenuItem:item];
}
@end

@interface MPCodeSidebarController ()
@property (nonatomic, strong) MPCodeTextView *textView;
@property (nonatomic, strong) MPCodeTextView *globalTextView;
@property (nonatomic, strong) NSTextField *glyphLabel;
@property (nonatomic, strong) NSButton *reloadButton;
@property (nonatomic, strong) NSTextField *messagesLabel;
@property (nonatomic, strong) NSTextView *messagesTextView;
@property (nonatomic, weak) GSGlyph *displayedGlyph;
@property (nonatomic, weak) GSFont *displayedFont;
@property (nonatomic, copy, nullable) NSString *activeLayerKeyPath;
@property (nonatomic) BOOL writingSource;
@property (nonatomic) BOOL loadingSource;
@property (nonatomic, strong, nullable) NSTimer *redrawTimer;
@end

@implementation MPCodeSidebarController
@synthesize controller = _controller;

+ (NSString *)title {
	return @"MetaFont";
}

+ (NSImage *)tabBarImage {
	return [NSImage imageWithSystemSymbolName:@"chevron.left.forwardslash.chevron.right" accessibilityDescription:self.title]
	?: [NSImage imageNamed:NSImageNameActionTemplate];
}

- (instancetype)init {
	return [self initWithNibName:nil bundle:nil];
}

- (instancetype)initWithNibName:(NSNibName)nibName bundle:(NSBundle *)bundle {
	self = [super initWithNibName:nibName bundle:bundle];
	if (self) {
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interfaceUpdated:) name:GSUpdateInterface object:nil];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interfaceUpdated:) name:GSUndoNotification object:nil];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interfaceUpdated:) name:NSUndoManagerDidUndoChangeNotification object:nil];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interfaceUpdated:) name:NSUndoManagerDidRedoChangeNotification object:nil];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(diagnosticsUpdated:) name:MPCompileDiagnosticsDidChangeNotification object:nil];
	}
	return self;
}

- (void)dealloc {
	[_redrawTimer invalidate];
	[NSNotificationCenter.defaultCenter removeObserver:self];
	if (_activeLayerKeyPath) [_controller removeObserver:self forKeyPath:_activeLayerKeyPath context:MPActiveLayerContext];
	[_displayedGlyph removeObserver:self forKeyPath:@"userData" context:MPSourceContext];
	[_displayedFont removeObserver:self forKeyPath:@"userData" context:MPSourceContext];
}

- (void)loadView {
	NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 400)];
	self.view = view;

	self.glyphLabel = [NSTextField labelWithString:@"Select a glyph"];
	self.glyphLabel.font = [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize];
	self.glyphLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
	self.glyphLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[view addSubview:self.glyphLabel];
	self.reloadButton = [NSButton buttonWithTitle:@"" target:self action:@selector(reloadImports:)];
	self.reloadButton.image = [NSImage imageWithSystemSymbolName:@"arrow.counterclockwise" accessibilityDescription:@"Reload"];
	self.reloadButton.toolTip = @"Reload imported files and regenerate outlines.";
	self.reloadButton.translatesAutoresizingMaskIntoConstraints = NO;
	[view addSubview:self.reloadButton];

	NSTextField *hint = [NSTextField wrappingLabelWithString:@"Global runs before each glyph. Imports use the saved font’s folder."];
	hint.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
	hint.textColor = NSColor.secondaryLabelColor;
	hint.translatesAutoresizingMaskIntoConstraints = NO;
	[view addSubview:hint];

	NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSZeroRect];
	tabs.translatesAutoresizingMaskIntoConstraints = NO;
	[view addSubview:tabs];
	MPCodeTextView *glyphEditor;
	MPCodeTextView *globalEditor;
	NSTabViewItem *glyphTab = [[NSTabViewItem alloc] initWithIdentifier:@"glyph"];
	glyphTab.label = @"Glyph";
	glyphTab.view = [self scrollViewWithEditor:&glyphEditor];
	[tabs addTabViewItem:glyphTab];
	NSTabViewItem *globalTab = [[NSTabViewItem alloc] initWithIdentifier:@"global"];
	globalTab.label = @"Global";
	globalTab.view = [self scrollViewWithEditor:&globalEditor];
	[tabs addTabViewItem:globalTab];
	self.textView = glyphEditor;
	self.globalTextView = globalEditor;

	self.messagesLabel = [NSTextField labelWithString:@"Messages"];
	self.messagesLabel.font = [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize];
	self.messagesLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[view addSubview:self.messagesLabel];
	NSScrollView *messages = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 280, 100)];
	messages.translatesAutoresizingMaskIntoConstraints = NO;
	messages.hasVerticalScroller = YES;
	messages.hasHorizontalScroller = YES;
	messages.autohidesScrollers = YES;
	messages.borderType = NSBezelBorder;
	NSTextView *output = [[NSTextView alloc] initWithFrame:messages.contentView.bounds];
	output.editable = NO;
	output.selectable = YES;
	output.richText = NO;
	output.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
	output.textContainerInset = NSMakeSize(6, 6);
	output.verticallyResizable = YES;
	output.horizontallyResizable = YES;
	output.autoresizingMask = NSViewWidthSizable;
	output.minSize = NSZeroSize;
	output.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
	output.textContainer.containerSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
	output.textContainer.widthTracksTextView = NO;
	messages.documentView = output;
	self.messagesTextView = output;
	[view addSubview:messages];
	NSLayoutConstraint *messageHeight = [messages.heightAnchor constraintEqualToConstant:110];
	messageHeight.priority = NSLayoutPriorityDefaultHigh;
	messageHeight.active = YES;

	[NSLayoutConstraint activateConstraints:@[
		[self.glyphLabel.topAnchor constraintEqualToAnchor:view.topAnchor constant:10],
		[self.glyphLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:10],
		[self.glyphLabel.trailingAnchor constraintGreaterThanOrEqualToAnchor:self.reloadButton.leadingAnchor constant:-8],
		[self.reloadButton.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-6],
		[self.reloadButton.centerYAnchor constraintEqualToAnchor:self.glyphLabel.centerYAnchor],
		[self.reloadButton.widthAnchor constraintEqualToConstant:24],
		[hint.topAnchor constraintEqualToAnchor:self.glyphLabel.bottomAnchor constant:5],
		[hint.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:10],
		[hint.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-10],
		[tabs.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:8],
		[tabs.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:6],
		[tabs.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-6],
		[tabs.bottomAnchor constraintEqualToAnchor:self.messagesLabel.topAnchor constant:-8],
		[self.messagesLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:10],
		[self.messagesLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-10],
		[messages.topAnchor constraintEqualToAnchor:self.messagesLabel.bottomAnchor constant:4],
		[messages.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:6],
		[messages.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-6],
		[messages.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-6],
		[messages.heightAnchor constraintGreaterThanOrEqualToConstant:40]
	]];
	[self reloadCode];
}

- (NSScrollView *)scrollViewWithEditor:(MPCodeTextView **)outEditor {
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 280, 320)];
	scroll.hasVerticalScroller = YES;
	scroll.hasHorizontalScroller = YES;
	scroll.autohidesScrollers = YES;
	scroll.borderType = NSBezelBorder;
	MPCodeTextView *editor = [[MPCodeTextView alloc] initWithFrame:scroll.contentView.bounds];
	editor.richText = NO;
	editor.importsGraphics = NO;
	editor.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
	editor.textContainerInset = NSMakeSize(8, 8);
	editor.verticallyResizable = YES;
	editor.horizontallyResizable = YES;
	editor.autoresizingMask = NSViewWidthSizable;
	editor.minSize = NSZeroSize;
	editor.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
	editor.textContainer.containerSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
	editor.textContainer.widthTracksTextView = NO;
	editor.automaticQuoteSubstitutionEnabled = NO;
	editor.automaticDashSubstitutionEnabled = NO;
	editor.automaticTextReplacementEnabled = NO;
	editor.automaticSpellingCorrectionEnabled = NO;
	editor.continuousSpellCheckingEnabled = NO;
	editor.grammarCheckingEnabled = NO;
	editor.allowsUndo = NO;
	editor.delegate = self;
	scroll.documentView = editor;
	*outEditor = editor;
	return scroll;
}

- (NSObject<GSGlyphViewControllerProtocol> *)controller {
	return _controller;
}

- (void)setController:(NSObject<GSGlyphViewControllerProtocol> *)controller {
	if (_controller == controller) {
		[self reloadCode];
		return;
	}
	[self.redrawTimer invalidate];
	self.redrawTimer = nil;
	if (self.activeLayerKeyPath) [_controller removeObserver:self forKeyPath:self.activeLayerKeyPath context:MPActiveLayerContext];
	_controller = controller;
	self.activeLayerKeyPath = nil;
	if (controller) {
		// Observe the edit view itself, including replacement of graphicView.
		self.activeLayerKeyPath = [controller respondsToSelector:@selector(graphicView)] ? @"graphicView.activeLayer" : @"activeLayer";
		[controller addObserver:self forKeyPath:self.activeLayerKeyPath options:0 context:MPActiveLayerContext];
	}
	[self reloadCode];
}

- (GSLayer *)activeLayer {
	if ([self.controller respondsToSelector:@selector(graphicView)]) {
		return ((GSEditViewController *)self.controller).graphicView.activeLayer;
	}
	return self.controller.activeLayer;
}

- (GSFont *)activeFont {
	GSFont *font = self.activeLayer.font;
	id represented = self.controller.representedObject;
	return font ?: ([represented isKindOfClass:GSFont.class] ? represented : nil);
}

- (void)invalidateGlyph:(GSGlyph *)glyph {
	GSLayer *active = self.activeLayer;
	if (active.glyph == glyph) [active setNeedUpdateShapes];
	for (GSLayer *layer in glyph.layers.allValues) if (layer != active) [layer setNeedUpdateShapes];
}

- (void)invalidateFont:(GSFont *)font {
	for (GSGlyph *glyph in font.glyphs) [self invalidateGlyph:glyph];
	// Detached test layers or a transient preview need not be in font.glyphs.
	if (self.activeLayer.font == font) [self.activeLayer setNeedUpdateShapes];
}

- (void)schedulePreview {
	[self.redrawTimer invalidate];
	__weak MPCodeSidebarController *weakSelf = self;
	self.redrawTimer = [NSTimer scheduledTimerWithTimeInterval:0.35 repeats:NO block:^(NSTimer *timer) {
		MPCodeSidebarController *sidebar = weakSelf;
		NSObject<GSGlyphViewControllerProtocol> *controller = sidebar.controller;
		if ([controller respondsToSelector:@selector(reflow)]) [controller reflow];
		if ([controller respondsToSelector:@selector(redraw)]) [controller redraw];
		sidebar.redrawTimer = nil;
	}];
}

- (IBAction)reloadImports:(id)sender {
	[MPCompileDiagnostics.sharedDiagnostics clear];
	[NSNotificationCenter.defaultCenter postNotificationName:MPReloadImportsNotification object:self.activeFont];
	if (self.activeFont) [self invalidateFont:self.activeFont];
	else if (self.activeLayer.glyph) [self invalidateGlyph:self.activeLayer.glyph];
	[self refreshMessages];
	[self schedulePreview];
}

- (void)refreshMessages {
	if (!self.isViewLoaded) return;
	GSLayer *layer = self.activeLayer;
	NSDictionary *result = layer ? [MPCompileDiagnostics.sharedDiagnostics resultForLayer:layer] : nil;
	NSError *error = [result[@"error"] isKindOfClass:NSError.class] ? result[@"error"] : nil;
	NSString *message;
	id source = [layer.glyph userDataForKey:@"metaFont"];
	if (!layer.glyph) message = @"Select a glyph to see generation messages.";
	else if (!source || ([source isKindOfClass:NSString.class] && ![source stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)) message = @"Enter glyph code to generate outlines.";
	else if (error) message = error.localizedDescription;
	else message = result ? @"No errors." : @"Waiting for preview…";
	self.messagesLabel.stringValue = error ? @"Messages · Error" : @"Messages";
	self.messagesLabel.textColor = error ? NSColor.systemRedColor : NSColor.labelColor;
	self.messagesTextView.textColor = error ? NSColor.textColor : NSColor.secondaryLabelColor;
	if (![self.messagesTextView.string isEqualToString:message]) {
		self.messagesTextView.string = message;
		[self.messagesTextView scrollRangeToVisible:NSMakeRange(0, 0)];
	}
}

- (void)diagnosticsUpdated:(NSNotification *)notification {
	// The diagnostics store delivers on the main thread. Refresh only the
	// output so a compilation result never resets the caret or redraws shapes.
	[self refreshMessages];
}

- (void)reloadCode {
	if (!NSThread.isMainThread) {
		__weak MPCodeSidebarController *weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reloadCode]; });
		return;
	}
	if (self.writingSource) return;
	GSLayer *layer = self.activeLayer;
	GSGlyph *glyph = layer.glyph;
	GSFont *font = self.activeFont;
	BOOL sameGlyph = glyph == self.displayedGlyph;
	BOOL sameFont = font == self.displayedFont;
	if (glyph != self.displayedGlyph) {
		[self.displayedGlyph removeObserver:self forKeyPath:@"userData" context:MPSourceContext];
		self.displayedGlyph = glyph;
		[glyph addObserver:self forKeyPath:@"userData" options:0 context:MPSourceContext];
	}
	if (!sameFont) {
		[self.displayedFont removeObserver:self forKeyPath:@"userData" context:MPSourceContext];
		self.displayedFont = font;
		[font addObserver:self forKeyPath:@"userData" options:0 context:MPSourceContext];
	}
	if (!self.isViewLoaded) return;
	id stored = [glyph userDataForKey:@"metaFont"];
	NSString *code = [stored isKindOfClass:NSString.class] ? stored : @"";
	// Do not reset the insertion point on ordinary interface updates.
	if (![self.textView.string isEqualToString:code]) {
		self.loadingSource = YES;
		self.textView.string = code;
		self.loadingSource = NO;
		// External source edits, including Undo/Redo, also invalidate the
		// prepared shapes. Merely switching glyphs does not edit their state.
		if (sameGlyph && glyph) { [self invalidateGlyph:glyph]; [self schedulePreview]; }
	}
	id globalStored = [font userDataForKey:@"metaFont"];
	NSString *global = [globalStored isKindOfClass:NSString.class] ? globalStored : @"";
	if (![self.globalTextView.string isEqualToString:global]) {
		self.loadingSource = YES;
		self.globalTextView.string = global;
		self.loadingSource = NO;
		if (sameFont && font) { [self invalidateFont:font]; [self schedulePreview]; }
	}
	self.textView.editable = glyph != nil;
	self.textView.selectable = glyph != nil;
	self.textView.codeUndoManager = glyph.undoManager;
	self.globalTextView.editable = font != nil;
	self.globalTextView.selectable = font != nil;
	self.globalTextView.codeUndoManager = font.undoManager;
	self.reloadButton.enabled = font != nil || glyph != nil;
	self.glyphLabel.stringValue = glyph ? [NSString stringWithFormat:@"MetaFont · %@", glyph.name] : @"Select a glyph";
	[self refreshMessages];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context == MPActiveLayerContext || context == MPSourceContext) {
		[self reloadCode];
		return;
	}
	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)interfaceUpdated:(NSNotification *)notification {
	[self reloadCode];
}

- (void)viewWillAppear {
	[super viewWillAppear];
	[self reloadCode];
}

- (void)textDidChange:(NSNotification *)notification {
	BOOL isGlobal = notification.object == self.globalTextView;
	if ((!isGlobal && notification.object != self.textView) || self.writingSource || self.loadingSource) return;
	GSLayer *layer = self.activeLayer;
	GSGlyph *glyph = layer.glyph;
	GSFont *font = self.activeFont;
	// An event arriving after a selection change must not write an old buffer
	// into the newly selected glyph.
	if ((isGlobal && (!font || font != self.displayedFont)) ||
		(!isGlobal && (!glyph || glyph != self.displayedGlyph))) {
		[self reloadCode];
		return;
	}
	// NSTextView.string can expose its mutable backing storage. Persist a
	// snapshot so loading another glyph cannot mutate this glyph's source.
	NSString *code = [(isGlobal ? self.globalTextView : self.textView).string copy];
	id old = isGlobal ? [font userDataForKey:@"metaFont"] : [glyph userDataForKey:@"metaFont"];
	if ([old isEqual:code] || (!old && !code.length)) return;
	self.writingSource = YES;
	@try {
		if (isGlobal) {
			[font setUserData:code.length ? code : nil forKey:@"metaFont"];
			[self invalidateFont:font];
		} else {
			[glyph setUserData:code.length ? code : nil forKey:@"metaFont"];
			[self invalidateGlyph:glyph];
		}
	} @finally {
		self.writingSource = NO;
	}
	// Persist immediately; only preview refresh is delayed. No delayed write
	// can land on another glyph when the active layer changes.
	[self refreshMessages];
	[self schedulePreview];
}

@end

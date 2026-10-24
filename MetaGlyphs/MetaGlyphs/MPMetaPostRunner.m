//
//  MPMetaPostRunner.m
//  MetaGlyphs
//
//  Created by Georg Seifert on 21.10.26.
//
//


#import "MPMetaPostRunner.h"
#import <signal.h>

NSErrorDomain const MPMetaPostErrorDomain = @"com.GeorgSeifert.metapost";

static NSError *MPError(NSInteger code, NSString *message) {
	return [NSError errorWithDomain:MPMetaPostErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation MPMetaPostRunner
- (instancetype)init {
	return [self initWithExecutablePath:nil];
}

- (instancetype)initWithExecutablePath:(NSString *)path {
	self = [super init];
	if (self) {
		// Explicit paths are used by standalone engine tests. The plugin uses
		// only its own runtime and never searches an installed TeX tree.
		if (path.length) {
			_executablePath = [path copy];
		}
		else {
			_executablePath = [[NSBundle bundleForClass:self.class] URLForResource:@"mpost" withExtension:nil].path;
		}
		NSString *directory = [_executablePath stringByDeletingLastPathComponent];
		if (directory.length && [[NSFileManager defaultManager] fileExistsAtPath:[directory stringByAppendingPathComponent:@"plain.mp"]] &&
			[[NSFileManager defaultManager] fileExistsAtPath:[directory stringByAppendingPathComponent:@"mpost.mp"]]) {
			_supportDirectory = directory;
		}
		if (!path.length && (!_supportDirectory || ![NSFileManager.defaultManager isExecutableFileAtPath:_executablePath])) {
			_executablePath = nil;
		}
	}
	return self;
}

+ (NSString *)programForBody:(NSString *)body parameters:(NSDictionary<NSString *,NSNumber *> *)parameters {
	return [self programForBody:body globalCode:@"" parameters:parameters];
}

+ (NSString *)programForBody:(NSString *)body globalCode:(NSString *)globalCode parameters:(NSDictionary<NSString *,NSNumber *> *)parameters {
	NSMutableString *program = [NSMutableString stringWithString:
								@"outputformat := \"svg\";\noutputtemplate := \"glyph.svg\";\nrandomseed := 0;\n"];
	for (NSString *name in [[parameters allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		[program appendFormat:@"numeric %@; %@ := %@;\n", name, name,
		 [parameters[name] descriptionWithLocale:@{NSLocaleIdentifier: @"en_US_POSIX"}]];
	}
	[program appendFormat:@"%% Global source starts here.\n%@\nbeginfig(1);\n%% Glyph source starts here.\n%@\nendfig;\nend\n", globalCode, body];
	return program;
}

- (NSData *)SVGForBody:(NSString *)body parameters:(NSDictionary<NSString *,NSNumber *> *)parameters error:(NSError **)error {
	return [self SVGForBody:body globalCode:@"" parameters:parameters sourceURL:nil dependencies:NULL error:error];
}

- (NSData *)SVGForBody:(NSString *)body globalCode:(NSString *)globalCode parameters:(NSDictionary<NSString *,NSNumber *> *)parameters sourceURL:(NSURL *)sourceURL dependencies:(NSDictionary<NSString *,NSData *> **)dependencies error:(NSError **)error {
	if (dependencies) *dependencies = @{};
	if (!self.executablePath.length) {
		if (error) *error = MPError(1, @"The plugin’s bundled MetaPost runtime is missing or incomplete. Reinstall the plugin.");
		return nil;
	}
	NSFileManager *manager = [NSFileManager defaultManager];
	NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
						URLByAppendingPathComponent:[@"Glyphs-MetaPost-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
	if (![manager createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:error]) return nil;
	@try {
		if (self.supportDirectory) {
			// Supply an isolated Kpathsea configuration. Its file recorder
			// tracks nested/computed inputs; no installed TeX tree is needed.
			if (![@"TEXMF = .\n" writeToURL:[directory URLByAppendingPathComponent:@"texmf.cnf"] atomically:YES encoding:NSUTF8StringEncoding error:error]) return nil;
		}
		NSString *program = [self.class programForBody:body globalCode:globalCode parameters:parameters];
		if (self.supportDirectory) {
			NSString *plain = [self.supportDirectory stringByAppendingPathComponent:@"plain.mp"];
			if ([plain containsString:@"\""] || [plain containsString:@"\n"]) {
				if (error) *error = MPError(9, @"The MetaPost support-file path contains an unsupported quote or newline.");
				return nil;
			}
			program = [NSString stringWithFormat:@"input \"%@\";\n%@", plain, program];
		}
		if (![program writeToURL:[directory URLByAppendingPathComponent:@"glyph.mp"] atomically:YES encoding:NSUTF8StringEncoding error:error]) return nil;
		NSURL *log = [directory URLByAppendingPathComponent:@"process.log"];
		if (![manager createFileAtPath:log.path contents:nil attributes:nil]) {
			if (error) *error = MPError(2, @"Could not create the MetaPost diagnostic log.");
			return nil;
		}
		NSFileHandle *output = [NSFileHandle fileHandleForWritingToURL:log error:error];
		if (!output) return nil;
		NSTask *task = [NSTask new];
		task.executableURL = [NSURL fileURLWithPath:self.executablePath];
		task.currentDirectoryURL = directory;
		NSMutableArray *arguments = [@[@"-interaction=nonstopmode", @"-halt-on-error", @"-restricted"] mutableCopy];
		if (self.supportDirectory) [arguments addObject:@"-ini"];
		[arguments addObject:@"-recorder"];
		[arguments addObject:[directory URLByAppendingPathComponent:@"glyph.mp"].path];
		task.arguments = arguments;
		task.standardInput = [NSFileHandle fileHandleWithNullDevice];
		task.standardOutput = output;
		task.standardError = output;
		NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
		environment[@"PATH"] = [[self.executablePath stringByDeletingLastPathComponent] stringByAppendingString:@":/usr/bin:/bin"];
		environment[@"openout_any"] = @"p";
		environment[@"openin_any"] = @"p";
		environment[@"shell_escape"] = @"f";
		if (self.supportDirectory) environment[@"TEXMFCNF"] = directory.path;
		// Resolve inputs relative to the .glyphs/.glyphspackage file while all
		// generated files and logs remain in the private working directory.
		NSString *base = sourceURL.isFileURL ? sourceURL.URLByDeletingLastPathComponent.path : nil;
		NSString *inputs = base ? [base stringByAppendingString:@":."] : @".";
		environment[@"MPINPUTS"] = self.supportDirectory ? inputs : [inputs stringByAppendingString:@":"];
		task.environment = environment;
		dispatch_semaphore_t completed = dispatch_semaphore_create(0);
		task.terminationHandler = ^(NSTask *finished) { dispatch_semaphore_signal(completed); };
		if (![task launchAndReturnError:error]) {
			[output closeFile];
			return nil;
		}
		BOOL timedOut = dispatch_semaphore_wait(completed, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) != 0;
		if (timedOut) {
			kill(task.processIdentifier, SIGKILL);
			[task waitUntilExit];
		}
		[output closeFile];
		if (timedOut || task.terminationStatus != 0) {
			NSFileHandle *reader = [NSFileHandle fileHandleForReadingFromURL:log error:NULL];
			NSData *diagnosticData = [reader readDataOfLength:16384];
			[reader closeFile];
			NSString *diagnostic = diagnosticData ? [[NSString alloc] initWithData:diagnosticData encoding:NSUTF8StringEncoding] : nil;
			if (error) *error = MPError(3, [NSString stringWithFormat:@"%@\n%@",
											timedOut ? @"MetaPost exceeded the three-second time limit." : @"MetaPost could not compile this glyph.", diagnostic ?: @""]);
			return nil;
		}
		NSURL *svg = [directory URLByAppendingPathComponent:@"glyph.svg"];
		NSNumber *size;
		if (![svg getResourceValue:&size forKey:NSURLFileSizeKey error:error]) return nil;
		if (size.unsignedLongLongValue > 8 * 1024 * 1024) {
			if (error) *error = MPError(4, @"The generated outline exceeds the eight-megabyte limit.");
			return nil;
		}
		return [NSData dataWithContentsOfURL:svg options:0 error:error];
	}
	@finally {
		if (dependencies) {
			NSMutableDictionary *snapshots = [NSMutableDictionary new];
			NSString *record = [NSString stringWithContentsOfURL:[directory URLByAppendingPathComponent:@"glyph.fls"] encoding:NSUTF8StringEncoding error:NULL];
			for (NSString *line in [record componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
				if (![line hasPrefix:@"INPUT "]) continue;
				NSString *path = [line substringFromIndex:6];
				if (![path isAbsolutePath]) path = [directory.path stringByAppendingPathComponent:path];
				path = path.stringByStandardizingPath;
				if ([path hasPrefix:[directory.path stringByAppendingString:@"/"]]) continue;
				NSData *contents = [NSData dataWithContentsOfFile:path];
				if (contents) snapshots[path] = contents;
			}
			*dependencies = snapshots;
		}
		[manager removeItemAtURL:directory error:NULL];
	}
}

@end

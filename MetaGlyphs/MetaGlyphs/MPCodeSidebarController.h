//
//  MPCodeSidebarController.h
//  MetaGlyphs
//
//  Created by Georg Seifert on 21.10.26.
//
//


#import <Cocoa/Cocoa.h>
#import <GlyphsApp/GSEditViewSidebarControllerProtocol.h>
#import <GlyphsApp/GSGlyphViewControllerProtocol.h>

NS_ASSUME_NONNULL_BEGIN
extern NSNotificationName const MPReloadImportsNotification;

@interface MPCodeSidebarController : NSViewController <GSEditViewSidebarControllerProtocol, NSTextViewDelegate>
@property (weak, nullable) NSObject<GSGlyphViewControllerProtocol> *controller;
- (void)reloadCode;
- (IBAction)reloadImports:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END

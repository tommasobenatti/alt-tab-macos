#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include <SDL3/SDL.h>
#include <stdio.h>
#include <unistd.h>

extern void postProductionFocus(int32_t pid, uint32_t wid, int32_t complete);
extern void postFocusRelease(int32_t pid, uint32_t wid);

@interface NSObject (SDLFocusProbe)
- (BOOL)isMovingOrFocusClickPending;
@end

@interface ClickCounter : NSObject
@property unsigned count;
- (void)clicked:(id)sender;
@end
@implementation ClickCounter
- (void)clicked:(id)sender { self.count++; }
@end

@interface ProbeWindow : NSWindow
@property unsigned mouseDowns;
@property unsigned mouseUps;
@property NSPoint lastLocal;
@property CGPoint lastGlobal;
@end
@implementation ProbeWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (void)sendEvent:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown) self.mouseDowns++;
    if (event.type == NSEventTypeLeftMouseUp) self.mouseUps++;
    if (event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeLeftMouseUp) {
        self.lastLocal = event.locationInWindow;
        if (event.CGEvent) self.lastGlobal = CGEventGetLocation(event.CGEvent);
    }
    [super sendEvent:event];
}
@end

@interface WebReady : NSObject <WKNavigationDelegate>
@property BOOL ready;
@end
@implementation WebReady
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation { self.ready = YES; }
@end

static unsigned gameDowns = 0;
static unsigned gameUps = 0;
static void pump(Uint64 milliseconds) {
    Uint64 deadline = SDL_GetTicks() + milliseconds;
    SDL_Event event;
    while (SDL_GetTicks() < deadline) {
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_MOUSE_BUTTON_DOWN) gameDowns++;
            if (event.type == SDL_EVENT_MOUSE_BUTTON_UP) gameUps++;
        }
        SDL_Delay(2);
    }
}

int main(void) {
    @autoreleasepool {
        NSRunningApplication *previous = NSWorkspace.sharedWorkspace.frontmostApplication;
        if (!SDL_Init(SDL_INIT_VIDEO)) return 2;
        SDL_Window *sdl = SDL_CreateWindow("Generic SDL input probe", 480, 240, SDL_WINDOW_RESIZABLE);
        if (!sdl) { SDL_Quit(); return 2; }
        NSWindow *sdlNative = (__bridge NSWindow *)SDL_GetPointerProperty(SDL_GetWindowProperties(sdl), SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
        id listener = sdlNative.delegate;
        ProbeWindow *cocoa = [[ProbeWindow alloc] initWithContentRect:NSMakeRect(450, 220, 480, 240) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        cocoa.releasedWhenClosed = NO;
        cocoa.title = @"Generic AppKit input probe";
        ClickCounter *counter = [ClickCounter new];
        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 480, 240)];
        button.title = @"Any accidental click reaches this button";
        button.target = counter;
        button.action = @selector(clicked:);
        button.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        cocoa.contentView = button;
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp activateIgnoringOtherApps:YES];
        [cocoa makeKeyAndOrderFront:nil];
        pump(120);
        NSRect initialFrame = cocoa.frame;
        unsigned errors = 0;
        unsigned sdlKeyErrors = 0, pendingErrors = 0, cocoaKeyErrors = 0;
        for (unsigned i = 0; i < 12; i++) {
            [sdlNative makeKeyAndOrderFront:nil];
            postProductionFocus(getpid(), (uint32_t)sdlNative.windowNumber, 1);
            pump(25);
            SDL_SetWindowRelativeMouseMode(sdl, true);
            pump(10);
            if (!sdlNative.isKeyWindow) { errors++; sdlKeyErrors++; }
            if ([listener isMovingOrFocusClickPending]) { errors++; pendingErrors++; }
            postFocusRelease(getpid(), (uint32_t)sdlNative.windowNumber);
            pump(10);
            SDL_SetWindowRelativeMouseMode(sdl, false);
            [cocoa makeKeyAndOrderFront:nil];
            postProductionFocus(getpid(), (uint32_t)cocoa.windowNumber, 1);
            pump(25);
            if (!cocoa.isKeyWindow) { errors++; cocoaKeyErrors++; }
        }
        if (counter.count != 0 || gameDowns != 0 || gameUps != 0 || !NSEqualRects(initialFrame, cocoa.frame)) errors++;
        printf("SDL=%d cycles=12 errors=%u actions=%u gameButtons=%u/%u cocoaEdges=%u/%u local=(%.0f,%.0f) global=(%.0f,%.0f) frameUnchanged=%d\n", SDL_GetVersion(), errors, counter.count, gameDowns, gameUps, cocoa.mouseDowns, cocoa.mouseUps, cocoa.lastLocal.x, cocoa.lastLocal.y, cocoa.lastGlobal.x, cocoa.lastGlobal.y, NSEqualRects(initialFrame,cocoa.frame));
        printf("keyFailures SDL=%u Cocoa=%u pending=%u active=%d\n", sdlKeyErrors, cocoaKeyErrors, pendingErrors, NSApp.active);
        ProbeWindow *webWindow = [[ProbeWindow alloc] initWithContentRect:NSScreen.mainScreen.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        webWindow.releasedWhenClosed = NO;
        WKWebView *web = [[WKWebView alloc] initWithFrame:webWindow.contentView.bounds];
        web.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        webWindow.contentView = web;
        WebReady *ready = [WebReady new];
        web.navigationDelegate = ready;
        [web loadHTMLString:@"<!doctype html><html><body style='margin:0'><button style='position:fixed;inset:0;width:100%;height:100%'>Local WebKit input test</button><script>window.edges={mousedown:0,mouseup:0,click:0};for(const key of Object.keys(edges))document.addEventListener(key,()=>edges[key]++,true);</script></body></html>" baseURL:nil];
        Uint64 webDeadline = SDL_GetTicks() + 5000;
        while (!ready.ready && SDL_GetTicks() < webDeadline) pump(20);
        if (!ready.ready) { fprintf(stderr, "WebKit did not load the local test page\n"); errors++; }
        for (unsigned i = 0; i < 8 && ready.ready; i++) {
            [webWindow makeKeyAndOrderFront:nil];
            postProductionFocus(getpid(), (uint32_t)webWindow.windowNumber, 1);
            pump(35);
            [cocoa makeKeyAndOrderFront:nil];
            pump(15);
        }
        __block BOOL receivedWebResult = NO;
        __block unsigned webErrors = 0;
        [web evaluateJavaScript:@"JSON.stringify(window.edges)" completionHandler:^(id result, NSError *error) {
            printf("WebKit edges: %s; error=%s\n", [result UTF8String] ?: "null", error ? error.localizedDescription.UTF8String : "none");
            if (error || ![result isKindOfClass:NSString.class]) {
                webErrors++;
            } else {
                NSData *data = [result dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *counts = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (![counts isKindOfClass:NSDictionary.class] || counts.count != 3) webErrors++;
                for (NSNumber *value in counts.allValues) if (value.unsignedIntegerValue != 0) webErrors++;
            }
            receivedWebResult = YES;
        }];
        webDeadline = SDL_GetTicks() + 3000;
        while (!receivedWebResult && SDL_GetTicks() < webDeadline) pump(20);
        if (!receivedWebResult) errors++;
        errors += webErrors;
        [webWindow close];
        [cocoa close];
        SDL_DestroyWindow(sdl);
        SDL_Quit();
        [previous activateWithOptions:0];
        return errors ? 1 : 0;
    }
}

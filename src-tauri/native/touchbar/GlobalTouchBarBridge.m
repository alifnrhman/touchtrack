#import <AppKit/AppKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdbool.h>
#include <string.h>

// Experimental private selectors; no private-framework linking or symbol patching.
static SEL presentSelector(void) {
    for (NSString *name in @[@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:", @"presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:"]) {
        SEL selector = NSSelectorFromString(name);
        Method method = class_getClassMethod(NSTouchBar.class, selector);
        if (!method || method_getNumberOfArguments(method) != 5) continue;
        char result[16] = {0}, argument[16] = {0};
        method_getReturnType(method, result, sizeof(result));
        method_getArgumentType(method, 3, argument, sizeof(argument));
        if (result[0] == 'v' && (argument[0] == 'q' || argument[0] == 'Q')) return selector;
    }
    return NULL;
}
static SEL dismissSelector(void) {
    for (NSString *name in @[@"dismissSystemModalTouchBar:", @"dismissSystemModalFunctionBar:"]) {
        SEL selector = NSSelectorFromString(name);
        Method method = class_getClassMethod(NSTouchBar.class, selector);
        if (!method || method_getNumberOfArguments(method) != 3) continue;
        char result[16] = {0}; method_getReturnType(method, result, sizeof(result));
        if (result[0] == 'v') return selector;
    }
    return NULL;
}
bool ytm_global_supported(void) { return presentSelector() && dismissSelector(); }
bool ytm_global_present(void *pointer) {
    if (![NSThread isMainThread] || !pointer) return false;
    SEL selector = presentSelector(); if (!selector || !dismissSelector()) return false;
    @try {
        ((void (*)(id, SEL, NSTouchBar *, long long, NSString *))objc_msgSend)(NSTouchBar.class, selector, (__bridge NSTouchBar *)pointer, 0, nil);
        return true;
    } @catch (NSException *exception) { return false; }
}
bool ytm_global_dismiss(void *pointer) {
    if (![NSThread isMainThread] || !pointer) return false;
    SEL selector = dismissSelector(); if (!selector) return false;
    @try {
        ((void (*)(id, SEL, NSTouchBar *))objc_msgSend)(NSTouchBar.class, selector, (__bridge NSTouchBar *)pointer);
        return true;
    } @catch (NSException *exception) { return false; }
}

#import <Cocoa/Cocoa.h>
#include <node_api.h>
#include <unistd.h>

extern "C" void postProductionFocus(int32_t pid, uint32_t wid, int32_t complete);

static napi_value post(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    void *bytes = NULL;
    size_t length = 0;
    if (argc != 1 || napi_get_buffer_info(env, argv[0], &bytes, &length) != napi_ok || length < sizeof(void *)) {
        napi_throw_type_error(env, NULL, "Expected the native window handle");
        return NULL;
    }
    NSView *view = (__bridge NSView *)*(void **)bytes;
    if (!view.window) {
        napi_throw_error(env, NULL, "The window handle has no NSWindow");
        return NULL;
    }
    postProductionFocus(getpid(), (uint32_t)view.window.windowNumber, 1);
    if ([view.window respondsToSelector:@selector(accessibilityPerformRaise)]) {
        [view.window accessibilityPerformRaise];
    }
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value init(napi_env env, napi_value exports) {
    napi_value function;
    napi_create_function(env, "post", NAPI_AUTO_LENGTH, post, NULL, &function);
    napi_set_named_property(env, exports, "post", function);
    return exports;
}

NAPI_MODULE(focus, init)

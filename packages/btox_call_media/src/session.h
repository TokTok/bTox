/* The system's part of a call's audio: on iOS, the audio session and its
 * routes. */
#ifndef BTOX_SESSION_H
#define BTOX_SESSION_H

#include "btox_call_media.h"

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if defined(__APPLE__) && TARGET_OS_IPHONE
#define BTOX_IOS 1
#else
#define BTOX_IOS 0
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Before the call's audio starts. [on_routes] hears where it goes. */
bool btox_session_start(bool speaker, btox_routes_cb *on_routes);

void btox_session_set_route(Btox_Route route);

void btox_session_stop(void);

#ifdef __cplusplus
}
#endif

#endif /* BTOX_SESSION_H */

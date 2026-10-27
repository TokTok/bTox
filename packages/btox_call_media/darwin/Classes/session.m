#include "session.h"

#if BTOX_IOS

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

static btox_routes_cb *routes_cb;
static id route_changes;

static bool is_wired(AVAudioSessionPort port) {
  return [port isEqualToString:AVAudioSessionPortHeadphones] ||
         [port isEqualToString:AVAudioSessionPortHeadsetMic] ||
         [port isEqualToString:AVAudioSessionPortUSBAudio];
}

static bool is_bluetooth(AVAudioSessionPort port) {
  return [port isEqualToString:AVAudioSessionPortBluetoothHFP] ||
         [port isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
         [port isEqualToString:AVAudioSessionPortBluetoothLE];
}

static AVAudioSessionPortDescription *input_for(Btox_Route route) {
  for (AVAudioSessionPortDescription *input in AVAudioSession.sharedInstance
           .availableInputs) {
    const bool matches =
        route == BTOX_ROUTE_WIRED ? is_wired(input.portType)
        : route == BTOX_ROUTE_BLUETOOTH
            ? is_bluetooth(input.portType)
            : [input.portType isEqualToString:AVAudioSessionPortBuiltInMic];
    if (matches) {
      return input;
    }
  }
  return nil;
}

static void report(void) {
  /* Once, as the call may stop meanwhile. */
  btox_routes_cb *const on_routes = routes_cb;
  if (on_routes == NULL) {
    return;
  }
  AVAudioSession *session = AVAudioSession.sharedInstance;
  AVAudioSessionPort output = session.currentRoute.outputs.firstObject.portType;
  const Btox_Route route =
      [output isEqualToString:AVAudioSessionPortBuiltInSpeaker]
          ? BTOX_ROUTE_SPEAKER
      : is_wired(output)     ? BTOX_ROUTE_WIRED
      : is_bluetooth(output) ? BTOX_ROUTE_BLUETOOTH
                             : BTOX_ROUTE_EARPIECE;
  int32_t available = 1 << BTOX_ROUTE_SPEAKER;
  /* iPads have no earpiece. */
  if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
    available |= 1 << BTOX_ROUTE_EARPIECE;
  }
  for (Btox_Route headset = BTOX_ROUTE_WIRED; headset <= BTOX_ROUTE_BLUETOOTH;
       ++headset) {
    if (input_for(headset) != nil) {
      available |= 1 << headset;
    }
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    UIDevice.currentDevice.proximityMonitoringEnabled =
        route == BTOX_ROUTE_EARPIECE;
  });
  on_routes(route, available);
}

static void route_to(Btox_Route route) {
  AVAudioSession *session = AVAudioSession.sharedInstance;
  [session overrideOutputAudioPort:route == BTOX_ROUTE_SPEAKER
                                       ? AVAudioSessionPortOverrideSpeaker
                                       : AVAudioSessionPortOverrideNone
                             error:nil];
  if (route != BTOX_ROUTE_SPEAKER) {
    [session setPreferredInput:input_for(route) error:nil];
  }
}

bool btox_session_start(bool speaker, btox_routes_cb *on_routes) {
  AVAudioSession *session = AVAudioSession.sharedInstance;
  if (![session setCategory:AVAudioSessionCategoryPlayAndRecord
                       mode:AVAudioSessionModeVoiceChat
                    options:AVAudioSessionCategoryOptionAllowBluetooth
                      error:nil] ||
      ![session setActive:YES error:nil]) {
    return false;
  }
  routes_cb = on_routes;
  /* A headset takes the call, as phones do. */
  if (speaker && input_for(BTOX_ROUTE_WIRED) == nil &&
      input_for(BTOX_ROUTE_BLUETOOTH) == nil) {
    route_to(BTOX_ROUTE_SPEAKER);
  }
  route_changes = [NSNotificationCenter.defaultCenter
      addObserverForName:AVAudioSessionRouteChangeNotification
                  object:session
                   queue:nil
              usingBlock:^(NSNotification *note) {
                report();
              }];
  report();
  return true;
}

void btox_session_set_route(Btox_Route route) {
  route_to(route);
  report();
}

void btox_session_stop(void) {
  [NSNotificationCenter.defaultCenter removeObserver:route_changes];
  route_changes = nil;
  routes_cb = NULL;
  dispatch_async(dispatch_get_main_queue(), ^{
    UIDevice.currentDevice.proximityMonitoringEnabled = NO;
  });
  AVAudioSession *session = AVAudioSession.sharedInstance;
  [session overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
  [session setActive:NO
         withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
               error:nil];
}

#endif

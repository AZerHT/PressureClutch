#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

#include <CoreFoundation/CoreFoundation.h>

// MultitouchSupport.framework is private: these declarations follow what OpenMultitouchSupport and TrackWeight use.

typedef struct {
    float x, y;
} MTPoint;

typedef struct {
    MTPoint position, velocity;
} MTVector;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerID;
    int handID;
    MTVector normalized;
    /// Size of the contact.
    float zTotal;
    /// Force pressed by this finger: about 20 resting, 60–130 at the click, up to ~300 pressing hard.
    float zPressure;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;
    int field14;
    int field15;
    float zDensity;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallback)(MTDeviceRef device, const MTTouch *touches, int count, double timestamp, int frame);

CFArrayRef MTDeviceCreateList(void);
void MTRegisterContactFrameCallback(MTDeviceRef device, MTContactCallback callback);
void MTDeviceStart(MTDeviceRef device, int mode);

#endif

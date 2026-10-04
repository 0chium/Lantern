#include <dlfcn.h>
#include <substrate.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdatomic.h>
#include <notify.h>

typedef int (*LanternSetIndividualTorchLEDLevelsFunction)(
    void *device,
    unsigned int arg1,
    unsigned int levels
);

typedef uint32_t (*LanternNotifyRegisterDispatchFunction)(
    const char *name,
    int *outToken,
    dispatch_queue_t queue,
    void (^handler)(int token)
);

typedef uint32_t (*LanternNotifyGetStateFunction)(
    int token,
    uint64_t *state
);

static LanternSetIndividualTorchLEDLevelsFunction
    originalSetIndividualTorchLEDLevels = NULL;

static LanternNotifyGetStateFunction
    LanternNotifyGetState = NULL;

static atomic_bool gLanternEnabled = false;
static int gLanternNotificationToken = -1;

static const char *kLanternStateNotification =
    "com.ochium.lantern.state";


static uint32_t LanternWarmLevels(uint32_t levels)
{
    const uint32_t byte3 = (levels >> 24) & 0xFF;
    const uint32_t byte1 = (levels >> 8) & 0xFF;

    return (byte3 << 16) | byte1;
}


static bool LanternCanTransform(uint32_t levels)
{
    const uint32_t byte2 = (levels >> 16) & 0xFF;
    const uint32_t byte0 = levels & 0xFF;

    return levels != 0 &&
           byte2 == 0 &&
           byte0 == 0;
}


static void LanternRefreshState(void)
{
    if (LanternNotifyGetState == NULL ||
        gLanternNotificationToken < 0)
        return;

    uint64_t state = 0;

    if (LanternNotifyGetState(
            gLanternNotificationToken,
            &state
        ) == 0) {
        atomic_store(&gLanternEnabled, state != 0);
    }
}


static int LanternSetIndividualTorchLEDLevels(
    void *device,
    unsigned int arg1,
    unsigned int levels
)
{
    uint32_t finalLevels = levels;

    if (atomic_load(&gLanternEnabled) &&
        LanternCanTransform(levels)) {
        finalLevels = LanternWarmLevels(levels);
    }

    return originalSetIndividualTorchLEDLevels(
        device,
        arg1,
        finalLevels
    );
}


__attribute__((constructor))
static void LanternLoaded(void)
{
    /*
     * Resolve libnotify dynamically. This avoids introducing
     * direct notify_* imports into Lantern.
     */
    LanternNotifyRegisterDispatchFunction notifyRegisterDispatch =
        (LanternNotifyRegisterDispatchFunction)dlsym(
            RTLD_DEFAULT,
            "notify_register_dispatch"
        );

    LanternNotifyGetState =
        (LanternNotifyGetStateFunction)dlsym(
            RTLD_DEFAULT,
            "notify_get_state"
        );

    if (notifyRegisterDispatch != NULL &&
        LanternNotifyGetState != NULL) {

        notifyRegisterDispatch(
            kLanternStateNotification,
            &gLanternNotificationToken,
            dispatch_get_main_queue(),
            ^(int token) {
                LanternRefreshState();
            }
        );

        LanternRefreshState();
    }

    const char *h10Path =
        "/System/Library/MediaCapture/H10ISP.mediacapture";

    const char *symbolName =
        "__ZN6H10ISP12H10ISPDevice27SetIndividualTorchLEDLevelsEjj";

    void *h10Handle = dlopen(h10Path, RTLD_NOW);

    if (h10Handle == NULL)
        return;

    MSImageRef image = MSGetImageByName(h10Path);

    if (image == NULL)
        return;

    void *symbol = MSFindSymbol(image, symbolName);

    if (symbol == NULL)
        return;

    MSHookFunction(
        symbol,
        (void *)&LanternSetIndividualTorchLEDLevels,
        (void **)&originalSetIndividualTorchLEDLevels
    );
}

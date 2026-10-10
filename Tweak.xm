#include <dlfcn.h>
#include <substrate.h>
#include <stdint.h>
#include <stdbool.h>
#include <notify.h>
#include <dispatch/dispatch.h>
#include <atomic>
#define LD_ROLE "cameracaptured"
#include "LanternDiagnostic.h"

// Preserve observed x0 status bits; semantic C++ return typedef is unpublished.
typedef uint64_t (*LanternSetIndividualTorchLEDLevelsFunction)(void *, unsigned int, unsigned int);
typedef uint32_t (*LanternNotifyDispatchFunction)(const char *, int *, dispatch_queue_t, void (^)(int));
typedef uint32_t (*LanternNotifyGetStateFunction)(int, uint64_t *);
static LanternSetIndividualTorchLEDLevelsFunction originalSetIndividualTorchLEDLevels;
static std::atomic<bool> gLanternWarm(false);
static_assert(ATOMIC_BOOL_LOCK_FREE == 2, "H10 mode must be lock-free");
static const char *kLanternStateNotification = "com.ochium.lantern.state";

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

static uint64_t LanternSetIndividualTorchLEDLevels(void *device, unsigned int arg1, unsigned int levels)
{
    LDCall diagnostic(arg1, levels);
    // A guard avoids a NULL call; it cannot undo a patched/no-original failure.
    if (!originalSetIndividualTorchLEDLevels) return UINT64_MAX;
    if (levels == 0) {
        diagnostic.attempt(~0ULL, levels, LD_ZERO); // baseline skips the warm-state read
        uint64_t result = originalSetIndividualTorchLEDLevels(device, arg1, levels);
        diagnostic.returned(result);
        return result;
    }
    uint32_t finalLevels = levels;
    const bool warm = gLanternWarm.load(std::memory_order_acquire);
    LDReason reason = warm ? LD_PATTERN : LD_WHITE;
    if (warm && LanternCanTransform(levels)) {
        finalLevels = LanternWarmLevels(levels);
        reason = LD_TRANSFORM;
    }
    diagnostic.attempt(warm, finalLevels, reason);
    uint64_t result = originalSetIndividualTorchLEDLevels(device, arg1, finalLevels);
    diagnostic.returned(result); // raw x0 bits; unpublished semantic return type
    return result;
}

__attribute__((constructor))
static void LanternLoaded(void)
{
    LDComponentEntry();
    LDInitRecord(LD_INIT_STAGE, 1);
    LanternNotifyDispatchFunction reg = (LanternNotifyDispatchFunction)dlsym(RTLD_DEFAULT, "notify_register_dispatch");
    LanternNotifyGetStateFunction get = (LanternNotifyGetStateFunction)dlsym(RTLD_DEFAULT, "notify_get_state");
    if (!reg || !get) { LDInitRecord(LD_INIT_FAILURE, 1, !!reg, !!get); return; }
    int token = -1;
    dispatch_queue_t queue = dispatch_queue_create("com.ochium.lantern.mode", DISPATCH_QUEUE_SERIAL);
    uint32_t registration = reg(kLanternStateNotification, &token, queue, ^(int deliveredToken) {
        uint64_t state = 0;
        uint32_t status = get(deliveredToken, &state);
        bool warm = status == 0 && state == 1;
        gLanternWarm.store(warm, std::memory_order_release);
        LDLog(LD_MODE_RECEIVED, status, state, warm);
    });
    if (registration != 0) { LDInitRecord(LD_INIT_FAILURE, 2, registration); return; }
    // Do not import stale notify state at startup: new process starts WHITE.
    const char *h10Path = "/System/Library/MediaCapture/H10ISP.mediacapture";
    const char *symbolName = "__ZN6H10ISP12H10ISPDevice27SetIndividualTorchLEDLevelsEjj";
    LDInitRecord(LD_INIT_STAGE, 3);
    if (!dlopen(h10Path, RTLD_NOW)) { LDInitRecord(LD_INIT_FAILURE, 3); return; }
    MSImageRef image = MSGetImageByName(h10Path);
    if (!image) { LDInitRecord(LD_INIT_FAILURE, 4); return; }
    void *symbol = MSFindSymbol(image, symbolName);
    if (!symbol) { LDInitRecord(LD_INIT_FAILURE, 5); return; }
    LDInitRecord(LD_SYMBOL_FOUND);
    LDInitRecord(LD_HOOK_REQUEST, 1);
    MSHookFunction(symbol, (void *)&LanternSetIndividualTorchLEDLevels,
        (void **)&originalSetIndividualTorchLEDLevels);
    LDInitRecord(LD_HOOK_ORIGINAL, !!originalSetIndividualTorchLEDLevels);
    if (!originalSetIndividualTorchLEDLevels) LDInitRecord(LD_INIT_FAILURE, 6);
    LDInitRecord(LD_INIT_READY); // constructor completed, not an installation ACK
}

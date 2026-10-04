#include <dlfcn.h>
#include <substrate.h>
#include <stdint.h>
#include <stdbool.h>

typedef int (*LanternSetIndividualTorchLEDLevelsFunction)(
    void *device,
    unsigned int arg1,
    unsigned int levels
);

static LanternSetIndividualTorchLEDLevelsFunction
    originalSetIndividualTorchLEDLevels = NULL;


/*
 * Apple's normal flashlight request on this device uses:
 *
 *     A 00 C 00
 *
 * Lantern moves those two existing channel values to:
 *
 *     00 A 00 C
 *
 * We preserve A and C independently rather than shifting
 * the complete 32-bit word.
 */
static uint32_t LanternWarmLevels(uint32_t levels)
{
    const uint32_t byte3 = (levels >> 24) & 0xFF;
    const uint32_t byte1 = (levels >> 8)  & 0xFF;

    return (byte3 << 16) | byte1;
}


/*
 * Only transform the normal alternating-channel form.
 *
 * Requests that already contain data in byte2 or byte0
 * are passed through untouched.
 */
static bool LanternCanTransform(uint32_t levels)
{
    const uint32_t byte2 = (levels >> 16) & 0xFF;
    const uint32_t byte0 = levels & 0xFF;

    return levels != 0 &&
           byte2 == 0 &&
           byte0 == 0;
}


static int LanternSetIndividualTorchLEDLevels(
    void *device,
    unsigned int arg1,
    unsigned int levels
)
{
    uint32_t finalLevels = levels;

    if (LanternCanTransform(levels))
        finalLevels = LanternWarmLevels(levels);

    return originalSetIndividualTorchLEDLevels(
        device,
        arg1,
        finalLevels
    );
}


__attribute__((constructor))
static void LanternLoaded(void)
{
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

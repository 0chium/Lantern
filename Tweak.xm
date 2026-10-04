#include <dlfcn.h>
#include <substrate.h>
#include <stdint.h>

typedef int (*LanternSetIndividualTorchLEDLevelsFunction)(
    void *device,
    unsigned int arg1,
    unsigned int levels
);

static LanternSetIndividualTorchLEDLevelsFunction
    originalSetIndividualTorchLEDLevels = NULL;

static int LanternSetIndividualTorchLEDLevels(
    void *device,
    unsigned int arg1,
    unsigned int levels
)
{
    /*
     * Lantern v0.0.1 intentionally does not modify the request.
     *
     * This build only verifies that the clean Lantern hook can
     * coexist with Apple's normal flashlight path.
     */
    return originalSetIndividualTorchLEDLevels(
        device,
        arg1,
        levels
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

// Compile/link probe only. Never injected, installed, or executed by this workflow.
#include <os/log.h>
#include <stdint.h>
#include <stdatomic.h>

_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "32-bit diagnostic counters must be lock-free");
_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "64-bit diagnostic counters must be lock-free");

void LanternNativeLoggingCompileProbe(uint32_t status)
{
    os_log_t channel = os_log_create("com.ochium.lantern.diagnostic", "status");
    os_log_with_type(channel, OS_LOG_TYPE_DEFAULT,
                     "compile_probe status=%{public}u", status);
}


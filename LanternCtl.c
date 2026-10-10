#include <dlfcn.h>
#include <notify.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include "LanternDiagnosticBuild.h"

static int diagnostic(int argc, char **argv)
{
    const char *name = NULL;
    uint64_t capture = 0;
    if (strcmp(argv[1], "diagnostic-arm") == 0) {
        if (argc != 3 || strlen(argv[2]) != 16) return 1;
        for (unsigned i = 0; i < 16; ++i)
            if (!((argv[2][i] >= '0' && argv[2][i] <= '9') ||
                  (argv[2][i] >= 'a' && argv[2][i] <= 'f') ||
                  (argv[2][i] >= 'A' && argv[2][i] <= 'F'))) return 1;
        errno = 0; capture = strtoull(argv[2], NULL, 16);
        if (errno || !capture) return 1;
        name = LD_ARM_NAME;
    } else if (argc == 2 && strcmp(argv[1], "diagnostic-stop") == 0) name = LD_STOP_NAME;
    else if (argc == 2 && strcmp(argv[1], "diagnostic-export") == 0) name = LD_EXPORT_NAME;
    else return 1;
    int token = -1;
    uint32_t status = notify_register_check(name, &token);
    if (!status && capture) status = notify_set_state(token, capture);
    if (!status) status = notify_post(name);
    if (token >= 0) notify_cancel(token);
    if (status) { fprintf(stderr, "Diagnostic request failed: %u\n", status); return 1; }
    printf("%s: request posted; delivery/export NOT acknowledged; LED color unverified\n", LD_BUILD_ID);
    return 0;
}

typedef uint32_t (*NotifyRegisterCheckFunction)(
    const char *name,
    int *outToken
);

typedef uint32_t (*NotifySetStateFunction)(
    int token,
    uint64_t state
);

typedef uint32_t (*NotifyGetStateFunction)(
    int token,
    uint64_t *state
);

typedef uint32_t (*NotifyPostFunction)(
    const char *name
);

typedef uint32_t (*NotifyCancelFunction)(
    int token
);

static const char *kLanternStateNotification =
    "com.ochium.lantern.state";

int main(int argc, char **argv)
{
    // Diagnostic requests never register or change the ordinary warm-state channel.
    if (argc >= 2 && strncmp(argv[1], "diagnostic-", 11) == 0) return diagnostic(argc, argv);
    NotifyRegisterCheckFunction notifyRegisterCheck =
        (NotifyRegisterCheckFunction)dlsym(
            RTLD_DEFAULT,
            "notify_register_check"
        );

    NotifySetStateFunction notifySetState =
        (NotifySetStateFunction)dlsym(
            RTLD_DEFAULT,
            "notify_set_state"
        );

    NotifyGetStateFunction notifyGetState =
        (NotifyGetStateFunction)dlsym(
            RTLD_DEFAULT,
            "notify_get_state"
        );

    NotifyPostFunction notifyPost =
        (NotifyPostFunction)dlsym(
            RTLD_DEFAULT,
            "notify_post"
        );

    NotifyCancelFunction notifyCancel =
        (NotifyCancelFunction)dlsym(
            RTLD_DEFAULT,
            "notify_cancel"
        );

    if (notifyRegisterCheck == NULL ||
        notifySetState == NULL ||
        notifyGetState == NULL ||
        notifyPost == NULL ||
        notifyCancel == NULL) {
        fprintf(stderr, "Lantern: unable to resolve libnotify\n");
        return 1;
    }

    int token = -1;

    if (notifyRegisterCheck(
            kLanternStateNotification,
            &token
        ) != 0) {
        fprintf(stderr, "Lantern: unable to register state\n");
        return 1;
    }

    if (argc == 2 && strcmp(argv[1], "on") == 0) {

        if (notifySetState(token, 1) != 0) {
            fprintf(stderr, "Lantern: unable to set state\n");
            notifyCancel(token);
            return 1;
        }

        notifyPost(kLanternStateNotification);

        printf("Lantern: ON\n");
    }
    else if (argc == 2 && strcmp(argv[1], "off") == 0) {

        if (notifySetState(token, 0) != 0) {
            fprintf(stderr, "Lantern: unable to set state\n");
            notifyCancel(token);
            return 1;
        }

        notifyPost(kLanternStateNotification);

        printf("Lantern: OFF\n");
    }
    else if (argc == 2 && strcmp(argv[1], "status") == 0) {

        uint64_t state = 0;

        if (notifyGetState(token, &state) != 0) {
            fprintf(stderr, "Lantern: unable to read state\n");
            notifyCancel(token);
            return 1;
        }

        printf(
            "Lantern: %s\n",
            state != 0 ? "ON" : "OFF"
        );
    }
    else {
        printf(
            "Usage: lanternctl on | off | status\n"
        );

        notifyCancel(token);
        return 1;
    }

    notifyCancel(token);
    return 0;
}

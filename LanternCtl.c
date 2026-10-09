#include <dlfcn.h>
#include <notify.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

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

    if (argc == 2 && strcmp(argv[1], "diagnostic-export") == 0) {
        uint32_t status=notifyPost("com.ochium.lantern.diagnostic.build51.state.export.v1");
        notifyCancel(token);
        printf("Diagnostic export request status: %u (not completion)\n",status);
        return status==0 ? 0 : 1;
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

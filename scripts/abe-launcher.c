// Dedicated launchd entry point for apple-books-external-mount.
//
// Why this exists: when launchd runs the zsh script directly, TCC attributes
// the job to /bin/zsh, which has no Full Disk Access — so `rm` inside
// ~/Library/Containers and `mount_apfs` reading the sparsebundle on the
// external drive both fail with "Operation not permitted" (2026-08-07
// incident). Running the job through this binary gives it a stable identity
// that can be granted Full Disk Access once in System Settings.
//
// Build: cc -o bin/abe-launcher scripts/abe-launcher.c
// Grant: System Settings > Privacy & Security > Full Disk Access > add
//        bin/abe-launcher (re-grant after every rebuild — ad-hoc signature).

#include <unistd.h>

#define SCRIPT "/Users/davidmorris/GitHub/apple-books-external-mount/scripts/apple-books-external-mount.sh"

int main(int argc, char *argv[]) {
    char *args[] = {"/bin/zsh", SCRIPT, (argc > 1 ? argv[1] : "ensure"), 0};
    execv("/bin/zsh", args);
    return 1; // execv only returns on failure
}

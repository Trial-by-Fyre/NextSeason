// Launcher for the nightly test LaunchAgent.
//
// macOS privacy protection (TCC) blocks launchd jobs from reading ~/Documents,
// where this repository lives. Access is attributed to the process launchd
// started, so this launcher runs run-nightly-tests.sh (next to it) as a child
// instead of exec'ing it. Granting this one binary Full Disk Access then covers
// the run without granting it to /bin/bash for every script.
//
// Built by install-nightly-tests.sh. Rebuilding changes its signature, which
// invalidates the grant, so the installer rebuilds only when this file changes.

#include <errno.h>
#include <libgen.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>

extern char **environ;
static pid_t child = 0;

// Passes launchd's stop request (or Ctrl-C) on to the runner so it can clean up.
static void forward_signal(int signal_number) {
    if (child > 0) {
        kill(child, signal_number);
    }
}

int main(int argc, char *argv[]) {
    char executable[PATH_MAX];
    uint32_t size = sizeof executable;
    char resolved[PATH_MAX];
    if (_NSGetExecutablePath(executable, &size) != 0 || realpath(executable, resolved) == NULL) {
        fprintf(stderr, "nightly-launcher: cannot locate itself\n");
        return 2;
    }
    char script[PATH_MAX];
    snprintf(script, sizeof script, "%s/run-nightly-tests.sh", dirname(resolved));

    char **arguments = calloc((size_t)argc + 2, sizeof(char *));
    if (arguments == NULL) {
        return 2;
    }
    arguments[0] = "/bin/bash";
    arguments[1] = script;
    for (int index = 1; index < argc; index++) {
        arguments[index + 1] = argv[index];
    }

    signal(SIGTERM, forward_signal);
    signal(SIGINT, forward_signal);
    int error = posix_spawn(&child, "/bin/bash", NULL, NULL, arguments, environ);
    if (error != 0) {
        fprintf(stderr, "nightly-launcher: cannot start %s: %s\n", script, strerror(error));
        return 2;
    }
    int status = 0;
    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR) {
            return 2;
        }
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return 128 + WTERMSIG(status);
}

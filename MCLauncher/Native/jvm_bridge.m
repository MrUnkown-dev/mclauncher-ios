#import "jvm_bridge.h"
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

// ---------------------------------------------------------------------------
// The JVM entry point.
//
// PojavLauncher and the various OpenJDK-for-iOS builds export a C entry point
// that boots the JVM, usually named `launchJVM`. It is declared here as a
// WEAK IMPORT so that this project still links and runs when the runtime has
// not been added yet — `launchJVM` simply resolves to NULL and MCL_hasJVM()
// returns 0.
//
// If your JRE build uses a different symbol name, change it in ONE place: the
// `kJVMSymbolCandidates` table below. The bridge tries each in order.
// ---------------------------------------------------------------------------

extern int launchJVM(int argc, char **argv) __attribute__((weak_import));

typedef int (*MCLJVMFn)(int argc, char **argv);

static MCLJVMFn gResolvedEntry = NULL;
static int gResolveAttempted = 0;

// Candidate symbol names, tried in order.
static const char *kJVMSymbolCandidates[] = {
    "launchJVM",
    "Java_org_lwjgl_Launcher_launchJVM",
    "JVM_launch",
    NULL
};

// Candidate dynamic libraries to dlopen when the symbol is not statically
// linked. All are looked up inside the app bundle's Frameworks directory.
static const char *kJVMDylibCandidates[] = {
    "@rpath/libjvm_launcher.dylib",
    "@rpath/libjvm.dylib",
    "@executable_path/Frameworks/libjvm_launcher.dylib",
    "@executable_path/Frameworks/libjvm.dylib",
    NULL
};

static MCLJVMFn resolveEntry(void) {
    if (gResolveAttempted) return gResolvedEntry;
    gResolveAttempted = 1;

    // 1. Statically linked weak symbol.
    if (launchJVM != NULL) {
        gResolvedEntry = (MCLJVMFn)launchJVM;
        fprintf(stderr, "[MCL] JVM entry resolved from linked symbol 'launchJVM'\n");
        return gResolvedEntry;
    }

    // 2. dlopen each candidate dylib and dlsym each candidate symbol.
    for (int i = 0; kJVMDylibCandidates[i] != NULL; i++) {
        void *handle = dlopen(kJVMDylibCandidates[i], RTLD_NOW | RTLD_GLOBAL);
        if (handle == NULL) continue;
        for (int j = 0; kJVMSymbolCandidates[j] != NULL; j++) {
            void *sym = dlsym(handle, kJVMSymbolCandidates[j]);
            if (sym != NULL) {
                gResolvedEntry = (MCLJVMFn)sym;
                fprintf(stderr, "[MCL] JVM entry resolved from %s via '%s'\n",
                        kJVMDylibCandidates[i], kJVMSymbolCandidates[j]);
                return gResolvedEntry;
            }
        }
        dlclose(handle);
    }

    fprintf(stderr, "[MCL] JVM entry point NOT found. Is the runtime installed? "
                    "See BUILD.md -> Adding the JRE.\n");
    return NULL;
}

int MCL_hasJVM(void) {
    return resolveEntry() != NULL ? 1 : 0;
}

const char *MCL_runtimePath(void) {
    // The runtime ships inside the app bundle under Frameworks/jre.
    static char path[PATH_MAX];
    if (path[0] == '\0') {
        NSString *p = [[[NSBundle mainBundle] bundlePath]
                        stringByAppendingPathComponent:@"Frameworks/jre"];
        strncpy(path, p.fileSystemRepresentation, sizeof(path) - 1);
    }
    return path;
}

int MCL_launchJVM(int argc, char **argv) {
    MCLJVMFn entry = resolveEntry();
    if (entry == NULL) {
        fprintf(stderr, "[MCL] cannot launch: no JVM entry point\n");
        return -127;
    }

    // Redirect the JVM's stdout/stderr into a log the UI can tail. The console
    // view reads this file live.
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                         NSUserDomainMask, YES).firstObject;
    NSString *logPath = [docs stringByAppendingPathComponent:@"minecraft/latest.log"];
    freopen(logPath.fileSystemRepresentation, "w", stdout);
    freopen(logPath.fileSystemRepresentation, "a", stderr);
    setvbuf(stdout, NULL, _IOLBF, 0);

    fprintf(stderr, "[MCL] launching JVM with %d args\n", argc);
    return entry(argc, argv);
}

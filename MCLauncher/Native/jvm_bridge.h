#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns 1 when the JVM entry point is linked into the binary, 0 otherwise.
/// The launcher uses this to decide whether to attempt a launch or show the
/// "runtime not installed" message.
int MCL_hasJVM(void);

/// Absolute path to the bundled Java runtime directory, or NULL when absent.
/// Caller does not own the returned string.
const char * _Nullable MCL_runtimePath(void);

/// Launches the JVM with a NULL-terminated-style argv array. Blocks until the
/// game exits. Returns the JVM exit code, or a negative value on setup failure.
int MCL_launchJVM(int argc, char * _Nullable * _Nullable argv);

NS_ASSUME_NONNULL_END

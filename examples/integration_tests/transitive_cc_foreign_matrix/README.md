# Transitive zlib/libarchive native/foreign matrix

This directory tests a real upstream C dependency graph:

```text
app binary -> libarchive -> zlib
```

Both zlib and libarchive are built from source. zlib targets are modeled after
`examples/third_party/zlib/BUILD.zlib.bazel`; libarchive has matching source
targets in `examples/third_party/libarchive/BUILD.libarchive.bazel`.

## Goals

- Confirm source-built zlib and libarchive can be substituted across native
  `cc_*` and foreign_cc producers.
- Confirm final binaries link and run correctly through the transitive
  `app -> libarchive -> zlib` path.
- Confirm shared-library runtime loading works without ambient
  `LD_LIBRARY_PATH` or `DYLD_LIBRARY_PATH` on Unix, and with only the expected
  Bazel output DLL directories on Windows.
- Confirm foreign_cc-produced `CcInfo` has semantic parity with comparable
  native `cc_*` provider targets after normalizing implementation-specific
  filenames and symlink shapes.

## Layout

Shared app source, CMake project files, test macros, aggregate suites, and
provider test rules live in this package. App build targets and their paired
runtime tests live in subpackages grouped by the final app producer and the app
link mode.

Each app package lists explicit scenario-level macro calls. The call site shows
the app producer, app link mode, `deps`, `dynamic_deps` where applicable,
`linkstatic` where applicable, and expected runtime-loaded libraries.

| Subpackage                     | Role                                                                            |
| ------------------------------ | ------------------------------------------------------------------------------- |
| `.`                            | Shared sources, macros, aggregate suites, and docs                              |
| `cc_binary_static_deps`        | `cc_binary` apps consuming static libarchive through `deps`                     |
| `cc_binary_direct_deps`        | `cc_binary` apps consuming foreign shared libarchive directly through `deps`    |
| `cc_binary_wrapped_cc_library` | `cc_binary` apps consuming shared libarchive through a wrapped `cc_library`     |
| `cc_binary_dynamic_deps`       | `cc_binary` apps consuming native shared libarchive through `dynamic_deps`      |
| `cmake_static_deps`            | CMake apps consuming static libarchive through `deps`                           |
| `cmake_direct_deps`            | CMake apps consuming foreign shared libarchive directly through `deps`          |
| `cmake_wrapped_cc_library`     | CMake apps consuming shared libarchive through a wrapped `cc_library`           |
| `cmake_dynamic_deps`           | CMake apps consuming native shared libarchive through `dynamic_deps`            |
| `provider_parity_tests`        | `CcInfo` semantic parity tests                                                  |
| `known_gap`                    | Stricter expected-gap cases kept outside the default `tests` suite              |

| App package                    | App         | App link mode        | libarchive cases        | zlib cases | App/test pairs |
| ------------------------------ | ----------- | -------------------- | ----------------------- | ---------- | -------------: |
| `cc_binary_static_deps`        | `cc_binary` | `static_deps`        | static, foreign static  | all four   |             16 |
| `cc_binary_direct_deps`        | `cc_binary` | `direct_deps`        | foreign shared          | all four   |              4 |
| `cc_binary_wrapped_cc_library` | `cc_binary` | `wrapped_cc_library` | foreign shared, dynamic | all four   |              8 |
| `cc_binary_dynamic_deps`       | `cc_binary` | `dynamic_deps`       | shared                  | all four   |              4 |
| `cmake_static_deps`            | `cmake`     | `static_deps`        | static, foreign static  | all four   |              8 |
| `cmake_direct_deps`            | `cmake`     | `direct_deps`        | foreign shared          | all four   |              4 |
| `cmake_wrapped_cc_library`     | `cmake`     | `wrapped_cc_library` | foreign shared, dynamic | all four   |              8 |
| `cmake_dynamic_deps`           | `cmake`     | `dynamic_deps`       | shared                  | all four   |              4 |

The root package exposes these suites:

| Suite                    | Contents                                            |
| ------------------------ | --------------------------------------------------- |
| `:cc_binary_tests`       | All `cc_binary` app/runtime cases                   |
| `:cmake_tests`           | All foreign_cc CMake app/runtime cases              |
| `:runtime_tests`         | All runtime matrix cases                            |
| `:provider_parity_tests` | `CcInfo` parity cases from `provider_parity_tests`  |
| `:known_gap_tests`       | Opt-in expected-gap cases from `known_gap`          |
| `:tests`                 | Default runtime and provider parity coverage        |

## Runtime assertion

The app uses libarchive's gzip filter to write a tar archive to memory, then
reads it back through libarchive. That forces libarchive to use zlib rather than
only linking it. Successful runs print exactly:

```text
expected libarchive+zlib loaded: payload=rules_foreign_cc_transitive_test
```

For shared-library cases, the app also reports the runtime loader path for
libarchive and zlib. The test compares those paths against the exact Bazel
runfiles for the expected shared-library targets, so a system library fallback
fails without relying on a system-path blacklist.

The runtime test macro writes a tab-separated manifest with the app runfile and
expected shared-library runfiles from `$(rlocationpaths ...)`. The shell test
resolves those entries with Bazel's runfiles library and canonicalizes paths
with the `bazel_lib` coreutils toolchain `realpath`, rather than a host
`realpath`.

On Unix, the test unsets `LD_LIBRARY_PATH` and `DYLD_LIBRARY_PATH` before
running the app. On Windows, it resolves only the expected Bazel DLL runfiles,
prepends their parent directories to the child `PATH`, and then checks the
actual loaded DLL paths printed by the app. Windows path comparison additionally
uses `cygpath -m` and case folding to normalize native path spelling.

## Matrix

The runtime suite implements 56 app build and runtime scenarios. The scenarios
are enumerated from four zlib producer shapes, four libarchive producer shapes,
and the valid app link modes for each libarchive output shape.

| Producer       | Shape            | Target family                          |
| -------------- | ---------------- | -------------------------------------- |
| zlib           | static           | `@examples_zlib//:zlib_static`         |
| zlib           | foreign static   | `@examples_zlib//:zlib_foreign_static` |
| zlib           | dynamic          | `@examples_zlib//:zlib_dynamic`        |
| zlib           | foreign shared   | `@examples_zlib//:zlib_foreign_shared` |
| libarchive     | static           | `libarchive_static_zlib_*`             |
| libarchive     | foreign static   | `libarchive_foreign_static_zlib_*`     |
| libarchive     | dynamic wrapper  | `libarchive_dynamic_zlib_*`            |
| libarchive     | foreign shared   | `libarchive_foreign_shared_zlib_*`     |

The 56 runtime scenarios break down as:

| App producer/link mode                         | libarchive shapes        | zlib shapes | Cases |
| ---------------------------------------------- | ------------------------ | ----------: | ----: |
| `cc_binary` `static_deps`, `linkstatic=True`   | static, foreign static   |           4 |     8 |
| `cc_binary` `static_deps`, `linkstatic=False`  | static, foreign static   |           4 |     8 |
| `cmake` `static_deps`                          | static, foreign static   |           4 |     8 |
| `cc_binary` direct `deps`                      | foreign shared           |           4 |     4 |
| `cmake` direct `deps`                          | foreign shared           |           4 |     4 |
| `cc_binary` via wrapped `cc_library`           | dynamic, foreign shared  |           4 |     8 |
| `cmake` via wrapped `cc_library`               | dynamic, foreign shared  |           4 |     8 |
| `cc_binary` `dynamic_deps`                     | shared                   |           4 |     4 |
| `cmake` `dynamic_deps`                         | shared                   |           4 |     4 |
| Total                                          |                          |             |    56 |

| App package                    | Runtime cases |
| ------------------------------ | ------------: |
| `cc_binary_static_deps`        |            16 |
| `cmake_static_deps`            |             8 |
| `cc_binary_direct_deps`        |             4 |
| `cmake_direct_deps`            |             4 |
| `cc_binary_wrapped_cc_library` |             8 |
| `cmake_wrapped_cc_library`     |             8 |
| `cc_binary_dynamic_deps`       |             4 |
| `cmake_dynamic_deps`           |             4 |

Native libarchive targets use upstream's C source list with platform config
headers for Linux, macOS, and Windows. The Linux matrix is the primary
validation target for this layout. The Darwin and Windows config headers remain
best-effort fixtures for exercising Bazel provider and runtime behavior later;
the foreign_cc libarchive targets still use libarchive's upstream CMake
configure step.

## Provider parity

The provider tests compare `CcInfo` from a foreign_cc target against a native
`cc_*` target that is intended to expose the same contract:

zlib targets are under `@examples_zlib//`:

| Foreign target          | Native comparison target | Platform              |
| ----------------------- | ------------------------ | --------------------- |
| `:zlib_foreign_static`  | `:zlib_static`           | Linux, macOS, Windows |
| `:zlib_foreign_shared`  | `:zlib_dynamic`          | Linux, macOS, Windows |

libarchive targets are under `@examples_libarchive//`:

| Foreign target                                      | Native comparison target                         | Platform              |
| --------------------------------------------------- | ------------------------------------------------ | --------------------- |
| `:libarchive_foreign_static_zlib_static`            | `:libarchive_static_zlib_static`                 | Linux, macOS, Windows |
| `:libarchive_foreign_static_zlib_foreign_static`    | `:libarchive_static_zlib_foreign_static`         | Linux, macOS, Windows |
| `:libarchive_foreign_static_zlib_dynamic`           | `:libarchive_static_zlib_dynamic`                | Linux, macOS, Windows |
| `:libarchive_foreign_static_zlib_foreign_shared`    | `:libarchive_static_zlib_foreign_shared`         | Linux, macOS, Windows |
| `:libarchive_foreign_shared_zlib_dynamic`           | `:libarchive_dynamic_zlib_dynamic`               | Linux, macOS, Windows |
| `:libarchive_foreign_shared_zlib_foreign_shared`    | `:libarchive_dynamic_zlib_foreign_shared`        | Linux, macOS, Windows |

The comparison projects `CcInfo` down to the parts that should be semantically
equivalent:

- compilation context: defines, local defines, whether headers are present, and
  whether include paths are present
- linking context: static, dynamic, and interface library names; user link
  flags; and whether dynamic/interface libraries use Bazel solib symlinks with
  non-solib resolved files

Version suffixes, import-library spelling differences, and solib path prefixes
are normalized because they are representation details rather than provider
contract differences.

## Known gap

`known_gap_tests` keeps stricter cases that are expected to fail today. They are
tagged `manual`, disabled by default, and documented in `known_gap/README.md`.
Pass `--define=transitive_cc_foreign_known_gap=true` to reproduce them.

## Run

From `examples/`:

```bash
bazel test //integration_tests/transitive_cc_foreign_matrix:tests --test_output=errors
bazel test //integration_tests/transitive_cc_foreign_matrix/... --test_output=errors
bazel test //integration_tests/transitive_cc_foreign_matrix:known_gap_tests \
  --define=transitive_cc_foreign_known_gap=true \
  --test_output=errors
```

Linux is the validated platform for the current matrix layout. Darwin and
Windows validation should be run separately when their target support is being
worked on.

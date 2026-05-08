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

| Subpackage                            | Role                                                                              |
| ------------------------------------- | --------------------------------------------------------------------------------- |
| `.`                                   | shared sources, macros, aggregate suites, and docs                                |
| `app`                                 | namespace directory for app build/test packages                                   |
| `app/cc_binary_static_deps`           | `cc_binary` apps consuming static libarchive through `deps`                       |
| `app/cc_binary_direct_deps`           | `cc_binary` apps consuming foreign shared libarchive directly through `deps`      |
| `app/cc_binary_wrapped_cc_library`    | `cc_binary` apps consuming shared libarchive through a wrapped `cc_library`       |
| `app/cc_binary_dynamic_deps`          | `cc_binary` apps consuming native shared libarchive through `dynamic_deps`        |
| `app/cmake_static_deps`               | CMake apps consuming static libarchive through `deps`                             |
| `app/cmake_direct_deps`               | CMake apps consuming foreign shared libarchive directly through `deps`            |
| `app/cmake_wrapped_cc_library`        | CMake apps consuming shared libarchive through a wrapped `cc_library`             |
| `app/cmake_dynamic_deps`              | CMake apps consuming native shared libarchive through `dynamic_deps`              |
| `provider`                            | `CcInfo` semantic parity tests                                                    |
| `known_gap`                           | stricter case kept outside the default `tests` suite                              |

| App package                         | App         | App link mode          | libarchive cases             | zlib cases | App/test pairs |
| ----------------------------------- | ----------- | ---------------------- | ---------------------------- | ---------- | -------------: |
| `app/cc_binary_static_deps`         | `cc_binary` | `static_deps`          | static, foreign static       | all four   |             16 |
| `app/cc_binary_direct_deps`         | `cc_binary` | `direct_deps`          | foreign shared               | all four   |              4 |
| `app/cc_binary_wrapped_cc_library`  | `cc_binary` | `wrapped_cc_library`   | foreign shared, dynamic      | all four   |              8 |
| `app/cc_binary_dynamic_deps`        | `cc_binary` | `dynamic_deps`         | shared                       | all four   |              4 |
| `app/cmake_static_deps`             | `cmake`     | `static_deps`          | static, foreign static       | all four   |              8 |
| `app/cmake_direct_deps`             | `cmake`     | `direct_deps`          | foreign shared               | all four   |              4 |
| `app/cmake_wrapped_cc_library`      | `cmake`     | `wrapped_cc_library`   | foreign shared, dynamic      | all four   |              8 |
| `app/cmake_dynamic_deps`            | `cmake`     | `dynamic_deps`         | shared                       | all four   |              4 |

The root package exposes these suites:

| Suite | Contents |
| --- | --- |
| `:cc_binary_tests` | All `cc_binary` app/runtime cases |
| `:cmake_tests` | All foreign_cc CMake app/runtime cases |
| `:runtime_tests` | All runtime matrix cases |
| `:provider_tests` | `CcInfo` parity cases from `provider` |
| `:known_gap_tests` | Opt-in expected-gap case from `known_gap` |
| `:tests` | Default runtime and provider coverage |

## Runtime assertion

The app uses libarchive's gzip filter to write a tar archive to memory, then
reads it back through libarchive. That forces libarchive to use zlib rather than
only linking it. Successful runs print exactly:

```text
expected libarchive+zlib loaded: payload=rules_foreign_cc_transitive_test
```

For shared-library cases, the app also reports the runtime loader path for
libarchive and zlib. The test compares those paths against the exact Bazel
runfiles for the expected shared-library targets after resolving symlinks, so a
system library fallback fails without relying on a system-path blacklist.

On Windows, the test adds only the expected Bazel DLL directories to the child
`PATH` before running the app. It resolves runfile symlinks to their physical
Bazel output locations because the Windows DLL loader does not consistently use
MSYS runfile symlink directories for DLL discovery. The helper also includes the
Windows `System32/downlevel` CRT forwarding directory when present; that only
satisfies toolchain runtime DLLs, while libarchive and zlib are still checked
against their exact Bazel-built paths.

## Matrix

The runtime suite implements the 56-scenario model described in `MATRIX.md`.
The scenarios are enumerated from four zlib producer shapes, four libarchive
producer shapes, and the valid app link modes for each libarchive output shape.

| App package | Runtime cases |
| --- | ---: |
| `app/cc_binary_static_deps` | 16 |
| `app/cmake_static_deps` | 8 |
| `app/cc_binary_direct_deps` | 4 |
| `app/cmake_direct_deps` | 4 |
| `app/cc_binary_wrapped_cc_library` | 8 |
| `app/cmake_wrapped_cc_library` | 8 |
| `app/cc_binary_dynamic_deps` | 4 |
| `app/cmake_dynamic_deps` | 4 |

Native libarchive targets use upstream's C source list with platform config
headers for Linux, macOS, and Windows. The Linux matrix is the primary
validation target for this layout. The Darwin and Windows config headers remain
best-effort fixtures for exercising Bazel provider and runtime behavior later;
the foreign_cc libarchive targets still use libarchive's upstream CMake
configure step.

## Provider parity

The provider tests compare `CcInfo` from a foreign_cc target against a native
`cc_*` target that is intended to expose the same contract:

| Foreign target | Native comparison target | Platform |
| --- | --- | --- |
| `@examples_zlib//:zlib_foreign_static` | `@examples_zlib//:zlib_static` | Linux, macOS, Windows |
| `@examples_zlib//:zlib_foreign_shared` | `@examples_zlib//:zlib_dynamic` | Linux, macOS, Windows |
| `@examples_libarchive//:libarchive_foreign_static_zlib_static` | `@examples_libarchive//:libarchive_static_zlib_static` | Linux, macOS, Windows |
| `@examples_libarchive//:libarchive_foreign_static_zlib_foreign_static` | `@examples_libarchive//:libarchive_static_zlib_foreign_static` | Linux, macOS, Windows |
| `@examples_libarchive//:libarchive_foreign_static_zlib_dynamic` | `@examples_libarchive//:libarchive_static_zlib_dynamic` | Linux, macOS, Windows |
| `@examples_libarchive//:libarchive_foreign_static_zlib_foreign_shared` | `@examples_libarchive//:libarchive_static_zlib_foreign_shared` | Linux, macOS, Windows |
| `@examples_libarchive//:libarchive_foreign_shared_zlib_dynamic` | `@examples_libarchive//:libarchive_dynamic_zlib_dynamic` | Linux, macOS, Windows |
| `@examples_libarchive//:libarchive_foreign_shared_zlib_foreign_shared` | `@examples_libarchive//:libarchive_dynamic_zlib_foreign_shared` | Linux, macOS, Windows |

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

`known_gap_tests` keeps the stricter case where a downstream foreign_cc app
depends only on foreign_cc static libarchive built against native static zlib.
The `app/cmake_static_deps` matrix explicitly supplies both libarchive
and zlib to the app. This opt-in case instead checks whether the native static
zlib input is propagated through the foreign static libarchive layer in a way a
downstream foreign action can link without redeclaring zlib.

The targets in this package are tagged `manual` because the case is expected to
fail until that propagation works. They are also disabled by default; pass
`--define=transitive_cc_foreign_known_gap=true` to reproduce the gap.

The known-gap package also contains two strict provider parity cases for foreign
shared libarchive built against static zlib. These currently fail because
foreign_cc propagates `libz.a`/`zlib.lib` from the shared libarchive target,
while the matching native dynamic wrappers do not.

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

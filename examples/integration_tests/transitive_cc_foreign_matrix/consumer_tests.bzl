"""Consumer app/runtime test macros for the transitive native/foreign matrix."""

load("@rules_cc//cc:defs.bzl", "cc_binary")
load("@rules_foreign_cc//foreign_cc:defs.bzl", "cmake")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

_ALL_SUPPORTED_PLATFORMS = select({
    "@platforms//os:linux": [],
    "@platforms//os:macos": [],
    "@platforms//os:windows": [],
    "//conditions:default": ["@platforms//:incompatible"],
})

_APP_LINKOPTS = select({
    "@platforms//os:linux": ["-ldl"],
    "//conditions:default": [],
})

_APP_SRC = "//integration_tests/transitive_cc_foreign_matrix:app.c"
_CONSUMER_BINARY = select({
    "@platforms//os:windows": ["app.exe"],
    "//conditions:default": ["app"],
})
_FOREIGN_APP_SRCS = "//integration_tests/transitive_cc_foreign_matrix:foreign_app_srcs"

def expected_loaded_libraries(libarchive = None, zlib = None):
    expected = {}
    if libarchive:
        expected["libarchive"] = libarchive
    if zlib:
        expected["zlib"] = zlib
    return expected

def cmake_cache_entries(
        libarchive,
        libarchive_windows = None,
        zlib = None,
        zlib_windows = None):
    default_entries = {
        "LIBARCHIVE_LIBRARY_NAME": libarchive,
    }
    windows_entries = {
        "LIBARCHIVE_LIBRARY_NAME": libarchive_windows or libarchive,
    }

    if zlib:
        default_entries["ZLIB_LIBRARY_NAME"] = zlib
        windows_entries["ZLIB_LIBRARY_NAME"] = zlib_windows or zlib

    return select({
        "@platforms//os:windows": windows_entries,
        "//conditions:default": default_entries,
    })

def runtime_test(
        name,
        binary,
        binary_name,
        target_compatible_with,
        expected_loaded_libraries = {},
        tags = []):
    args = [
        binary_name,
        "--binary-runfiles",
        "$(rlocationpaths {})".format(binary),
    ]
    data = [
        binary,
        "@bazel_tools//tools/bash/runfiles",
    ]
    for library_name, library in expected_loaded_libraries.items():
        args.extend([
            "--expect-loaded",
            library_name,
            "$(rlocationpaths {})".format(library),
        ])
        data.append(library)

    sh_test(
        name = name,
        size = "small",
        srcs = ["//integration_tests/transitive_cc_foreign_matrix:runtime_test.sh"],
        args = args,
        data = data,
        tags = tags + ["manual"],
        target_compatible_with = target_compatible_with,
    )

def cc_binary_consumer_test(
        name,
        deps,
        expected_loaded_libraries,
        dynamic_deps = [],
        linkstatic = False,
        linkopts = _APP_LINKOPTS,
        target_compatible_with = _ALL_SUPPORTED_PLATFORMS,
        tags = []):
    cc_binary(
        name = name,
        srcs = [_APP_SRC],
        dynamic_deps = dynamic_deps,
        linkopts = linkopts,
        linkstatic = linkstatic,
        target_compatible_with = target_compatible_with,
        deps = deps,
    )

    runtime_test(
        name = name + "_test",
        binary = ":" + name,
        binary_name = name,
        expected_loaded_libraries = expected_loaded_libraries,
        tags = tags,
        target_compatible_with = target_compatible_with,
    )

def cmake_consumer_test(
        name,
        deps,
        cache_entries,
        expected_loaded_libraries,
        dynamic_deps = [],
        target_compatible_with = _ALL_SUPPORTED_PLATFORMS,
        tags = []):
    cmake(
        name = name,
        cache_entries = cache_entries,
        dynamic_deps = dynamic_deps,
        enable_runtime_library_search_directories = True,
        lib_source = _FOREIGN_APP_SRCS,
        out_binaries = _CONSUMER_BINARY,
        runtime_library_search_mode = "executable",
        target_compatible_with = target_compatible_with,
        deps = deps,
    )

    runtime_test(
        name = name + "_test",
        binary = ":" + name,
        binary_name = "app",
        expected_loaded_libraries = expected_loaded_libraries,
        tags = tags,
        target_compatible_with = target_compatible_with,
    )

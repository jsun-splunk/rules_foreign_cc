"""Unit tests for runtime library search directory helpers."""

load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load(
    "//foreign_cc/private:runtime_library_search_directories.bzl",
    "RUNTIME_LIBRARY_SEARCH_DIRECTORY_ATTRIBUTES",
    "export_for_test",
    "runtime_library_search_directories_enabled",
)

_RuntimeSearchEnabledInfo = provider(
    "Runtime library search directory enablement state.",
    fields = ["enabled"],
)
_RUNTIME_SEARCH_SETTING = str(Label("//foreign_cc/settings:runtime_library_search_directories"))

def _runtime_search_enabled_subject_impl(ctx):
    return [_RuntimeSearchEnabledInfo(
        enabled = runtime_library_search_directories_enabled(ctx),
    )]

_runtime_search_enabled_subject = rule(
    implementation = _runtime_search_enabled_subject_impl,
    attrs = RUNTIME_LIBRARY_SEARCH_DIRECTORY_ATTRIBUTES,
)

def _ctx(
        name = "python",
        lib_name = "",
        package = "pkg",
        repo_name = "",
        out_lib_dir = "lib",
        out_bin_dir = "bin",
        out_shared_libs = [],
        out_binaries = [],
        out_data_dirs = [],
        additional_dynamic_origins = [],
        additional_executable_origins = [],
        runtime_library_search_directories = "disabled",
        include_self_runtime_library_search_directories = False,
        runtime_library_search_mode = "all"):
    return struct(
        attr = struct(
            additional_dynamic_runtime_library_search_origins = additional_dynamic_origins,
            additional_executable_runtime_library_search_origins = additional_executable_origins,
            include_self_runtime_library_search_directories = include_self_runtime_library_search_directories,
            lib_name = lib_name,
            name = name,
            out_bin_dir = out_bin_dir,
            out_binaries = out_binaries,
            out_data_dirs = out_data_dirs,
            out_lib_dir = out_lib_dir,
            out_shared_libs = out_shared_libs,
            runtime_library_search_directories = runtime_library_search_directories,
            runtime_library_search_mode = runtime_library_search_mode,
        ),
        label = struct(
            package = package,
            repo_name = repo_name,
        ),
    )

def _file(short_path):
    return struct(short_path = short_path)

def _runtime_search_context(
        install_root_short_path = "pkg/python",
        shared_files = [],
        executable_files = []):
    return struct(
        executable_files = [_file(short_path) for short_path in executable_files],
        install_root_short_path = install_root_short_path,
        shared_files = [_file(short_path) for short_path in shared_files],
    )

def _runtime_library_search_directories(
        ctx,
        install_root_short_path = "pkg/python",
        shared_files = [],
        executable_files = []):
    return export_for_test.runtime_library_search_directories(
        ctx,
        _runtime_search_context(
            install_root_short_path = install_root_short_path,
            shared_files = shared_files,
            executable_files = executable_files,
        ),
    )

def _default_dynamic_origin_only_when_out_shared_libs_exist_test(ctx):
    env = unittest.begin(ctx)

    with_shared_libs = _runtime_library_search_directories(
        _ctx(
            runtime_library_search_directories = "enabled",
            include_self_runtime_library_search_directories = True,
            out_shared_libs = ["libpython3.10.so"],
            runtime_library_search_mode = "shared",
        ),
        shared_files = ["pkg/python/lib/libpython3.10.so"],
    )
    without_shared_libs = _runtime_library_search_directories(
        _ctx(
            runtime_library_search_directories = "enabled",
            include_self_runtime_library_search_directories = True,
            out_data_dirs = ["lib/python3.10/lib-dynload"],
            runtime_library_search_mode = "shared",
        ),
    )

    asserts.equals(env, ["."], with_shared_libs.shared.to_list())
    asserts.equals(env, [], without_shared_libs.shared.to_list())

    return unittest.end(env)

def _default_executable_origin_only_when_out_binaries_exist_test(ctx):
    env = unittest.begin(ctx)

    with_binaries = _runtime_library_search_directories(
        _ctx(
            runtime_library_search_directories = "enabled",
            include_self_runtime_library_search_directories = True,
            out_binaries = ["python3.10"],
            out_shared_libs = ["libpython3.10.so"],
            runtime_library_search_mode = "executable",
        ),
        executable_files = ["pkg/python/bin/python3.10"],
        shared_files = ["pkg/python/lib/libpython3.10.so"],
    )
    without_binaries = _runtime_library_search_directories(
        _ctx(
            runtime_library_search_directories = "enabled",
            include_self_runtime_library_search_directories = True,
            out_data_dirs = ["bin"],
            out_shared_libs = ["libpython3.10.so"],
            runtime_library_search_mode = "executable",
        ),
        shared_files = ["pkg/python/lib/libpython3.10.so"],
    )

    asserts.equals(env, ["../lib"], with_binaries.executable.to_list())
    asserts.equals(env, [], without_binaries.executable.to_list())

    return unittest.end(env)

def _additional_dynamic_origins_do_not_affect_executable_origins_test(ctx):
    env = unittest.begin(ctx)

    result = _runtime_library_search_directories(
        _ctx(
            additional_dynamic_origins = ["lib/python3.10/lib-dynload"],
            runtime_library_search_directories = "enabled",
            include_self_runtime_library_search_directories = True,
            out_binaries = ["python3.10"],
            out_shared_libs = ["libpython3.10.so"],
            runtime_library_search_mode = "executable",
        ),
        executable_files = ["pkg/python/bin/python3.10"],
        shared_files = ["pkg/python/lib/libpython3.10.so"],
    )

    asserts.equals(env, ["../lib"], result.executable.to_list())

    return unittest.end(env)

def _additional_executable_origins_do_not_affect_dynamic_origins_test(ctx):
    env = unittest.begin(ctx)

    result = _runtime_library_search_directories(
        _ctx(
            additional_executable_origins = ["libexec"],
            runtime_library_search_directories = "enabled",
            include_self_runtime_library_search_directories = True,
            out_shared_libs = ["libpython3.10.so"],
            runtime_library_search_mode = "shared",
        ),
        shared_files = ["pkg/python/lib/libpython3.10.so"],
    )

    asserts.equals(env, ["."], result.shared.to_list())

    return unittest.end(env)

def _additional_origins_are_install_tree_relative_test(ctx):
    env = unittest.begin(ctx)

    result = _runtime_library_search_directories(
        _ctx(
            additional_dynamic_origins = ["lib/python3.10/lib-dynload"],
            runtime_library_search_directories = "enabled",
            include_self_runtime_library_search_directories = True,
            out_shared_libs = ["libpython3.10.so"],
            runtime_library_search_mode = "shared",
        ),
        shared_files = ["pkg/python/lib/libpython3.10.so"],
    )

    asserts.equals(
        env,
        [
            ".",
            "../..",
        ],
        result.shared.to_list(),
    )

    return unittest.end(env)

def _additional_executable_origins_are_install_tree_relative_test(ctx):
    env = unittest.begin(ctx)

    result = _runtime_library_search_directories(
        _ctx(
            additional_executable_origins = ["libexec/bin"],
            runtime_library_search_directories = "enabled",
            include_self_runtime_library_search_directories = True,
            out_binaries = ["python3.10"],
            out_shared_libs = ["libpython3.10.so"],
            runtime_library_search_mode = "executable",
        ),
        executable_files = ["pkg/python/bin/python3.10"],
        shared_files = ["pkg/python/lib/libpython3.10.so"],
    )

    asserts.equals(
        env,
        [
            "../lib",
            "../../lib",
        ],
        result.executable.to_list(),
    )

    return unittest.end(env)

def _self_runtime_search_directories_are_disabled_by_default_test(ctx):
    env = unittest.begin(ctx)

    result = _runtime_library_search_directories(
        _ctx(
            out_binaries = ["python3.10"],
            out_shared_libs = ["libpython3.10.so"],
        ),
        executable_files = ["pkg/python/bin/python3.10"],
        shared_files = ["pkg/python/lib/libpython3.10.so"],
    )

    asserts.equals(env, None, result.shared)
    asserts.equals(env, None, result.executable)

    return unittest.end(env)

def _self_runtime_search_directories_use_default_paths_test(ctx):
    env = unittest.begin(ctx)

    result = _runtime_library_search_directories(
        _ctx(
            runtime_library_search_directories = "enabled",
            include_self_runtime_library_search_directories = True,
            out_binaries = ["python3.10"],
            out_shared_libs = ["libpython3.10.so"],
        ),
        executable_files = ["pkg/python/bin/python3.10"],
        shared_files = ["pkg/python/lib/libpython3.10.so"],
    )

    asserts.equals(env, ["."], result.shared.to_list())
    asserts.equals(env, ["../lib"], result.executable.to_list())

    return unittest.end(env)

def _self_runtime_search_directories_use_custom_paths_test(ctx):
    env = unittest.begin(ctx)

    result = _runtime_library_search_directories(
        _ctx(
            runtime_library_search_directories = "enabled",
            include_self_runtime_library_search_directories = True,
            out_bin_dir = "tools/bin",
            out_binaries = ["python3.10"],
            out_lib_dir = "lib64",
            out_shared_libs = ["libpython3.10.so"],
        ),
        executable_files = ["pkg/python/tools/bin/python3.10"],
        shared_files = ["pkg/python/lib64/libpython3.10.so"],
    )

    asserts.equals(env, ["."], result.shared.to_list())
    asserts.equals(env, ["../../lib64"], result.executable.to_list())

    return unittest.end(env)

def _self_runtime_search_directories_include_additional_dynamic_origins_test(ctx):
    env = unittest.begin(ctx)

    result = _runtime_library_search_directories(
        _ctx(
            additional_dynamic_origins = ["lib/python3.10/lib-dynload"],
            runtime_library_search_directories = "enabled",
            include_self_runtime_library_search_directories = True,
            out_shared_libs = ["libpython3.10.so"],
        ),
        shared_files = ["pkg/python/lib/libpython3.10.so"],
    )

    asserts.equals(env, [".", "../.."], result.shared.to_list())

    return unittest.end(env)

def _self_runtime_search_directories_respect_mode_test(ctx):
    env = unittest.begin(ctx)

    shared_only = _runtime_library_search_directories(
        _ctx(
            runtime_library_search_directories = "enabled",
            include_self_runtime_library_search_directories = True,
            out_binaries = ["python3.10"],
            out_shared_libs = ["libpython3.10.so"],
            runtime_library_search_mode = "shared",
        ),
        executable_files = ["pkg/python/bin/python3.10"],
        shared_files = ["pkg/python/lib/libpython3.10.so"],
    )
    executable_only = _runtime_library_search_directories(
        _ctx(
            runtime_library_search_directories = "enabled",
            include_self_runtime_library_search_directories = True,
            out_binaries = ["python3.10"],
            out_shared_libs = ["libpython3.10.so"],
            runtime_library_search_mode = "executable",
        ),
        executable_files = ["pkg/python/bin/python3.10"],
        shared_files = ["pkg/python/lib/libpython3.10.so"],
    )

    asserts.equals(env, ["."], shared_only.shared.to_list())
    asserts.equals(env, None, shared_only.executable)
    asserts.equals(env, None, executable_only.shared)
    asserts.equals(env, ["../lib"], executable_only.executable.to_list())

    return unittest.end(env)

def _auto_mode_uses_global_build_setting_test(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    asserts.equals(env, True, target[_RuntimeSearchEnabledInfo].enabled)

    return analysistest.end(env)

def _disabled_overrides_enabled_global_build_setting_test(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    asserts.equals(env, False, target[_RuntimeSearchEnabledInfo].enabled)

    return analysistest.end(env)

def _runtime_search_directories_dedupe_dynamic_library_dirs_test(ctx):
    env = unittest.begin(ctx)

    result = export_for_test.search_directories_for_dynamic_libraries(
        ["pkg/python/lib"],
        [
            "pkg/python/lib/libpython3.10.so",
            "pkg/python/lib/libother.so",
        ],
    )

    asserts.equals(env, ["."], result)

    return unittest.end(env)

def _solib_dynamic_library_gets_output_and_sibling_rpaths_test(ctx):
    env = unittest.begin(ctx)

    result = export_for_test.search_directories_for_dynamic_libraries(
        ["thirdparty/python39/python39/lib/python3.9/lib-dynload"],
        ["_solib_local/_Uthirdparty_Sbzip2/libbz2.so"],
    )

    asserts.equals(
        env,
        [
            "../../../../../../_solib_local/_Uthirdparty_Sbzip2",
            "../_Uthirdparty_Sbzip2",
        ],
        result,
    )

    return unittest.end(env)

def _non_solib_dynamic_library_gets_only_output_rpath_test(ctx):
    env = unittest.begin(ctx)

    result = export_for_test.search_directories_for_dynamic_libraries(
        ["pkg/python/bin"],
        ["pkg/python/lib/libpython3.10.so"],
    )

    asserts.equals(env, ["../lib"], result)

    return unittest.end(env)

def _solib_path_without_directory_gets_only_output_rpath_test(ctx):
    env = unittest.begin(ctx)

    result = export_for_test.search_directories_for_dynamic_libraries(
        ["pkg/python/lib"],
        ["_solib_local/libpython3.10.so"],
    )

    asserts.equals(env, ["../../../_solib_local"], result)

    return unittest.end(env)

default_dynamic_origin_only_when_out_shared_libs_exist_test = unittest.make(
    _default_dynamic_origin_only_when_out_shared_libs_exist_test,
)
default_executable_origin_only_when_out_binaries_exist_test = unittest.make(
    _default_executable_origin_only_when_out_binaries_exist_test,
)
additional_dynamic_origins_do_not_affect_executable_origins_test = unittest.make(
    _additional_dynamic_origins_do_not_affect_executable_origins_test,
)
additional_executable_origins_do_not_affect_dynamic_origins_test = unittest.make(
    _additional_executable_origins_do_not_affect_dynamic_origins_test,
)
additional_origins_are_install_tree_relative_test = unittest.make(
    _additional_origins_are_install_tree_relative_test,
)
additional_executable_origins_are_install_tree_relative_test = unittest.make(
    _additional_executable_origins_are_install_tree_relative_test,
)
self_runtime_search_directories_are_disabled_by_default_test = unittest.make(
    _self_runtime_search_directories_are_disabled_by_default_test,
)
self_runtime_search_directories_use_default_paths_test = unittest.make(
    _self_runtime_search_directories_use_default_paths_test,
)
self_runtime_search_directories_use_custom_paths_test = unittest.make(
    _self_runtime_search_directories_use_custom_paths_test,
)
self_runtime_search_directories_include_additional_dynamic_origins_test = unittest.make(
    _self_runtime_search_directories_include_additional_dynamic_origins_test,
)
self_runtime_search_directories_respect_mode_test = unittest.make(
    _self_runtime_search_directories_respect_mode_test,
)
auto_mode_uses_global_build_setting_test = analysistest.make(
    _auto_mode_uses_global_build_setting_test,
    config_settings = {
        _RUNTIME_SEARCH_SETTING: True,
    },
)
disabled_overrides_enabled_global_build_setting_test = analysistest.make(
    _disabled_overrides_enabled_global_build_setting_test,
    config_settings = {
        _RUNTIME_SEARCH_SETTING: True,
    },
)
runtime_search_directories_dedupe_dynamic_library_dirs_test = unittest.make(
    _runtime_search_directories_dedupe_dynamic_library_dirs_test,
)
solib_dynamic_library_gets_output_and_sibling_rpaths_test = unittest.make(
    _solib_dynamic_library_gets_output_and_sibling_rpaths_test,
)
non_solib_dynamic_library_gets_only_output_rpath_test = unittest.make(
    _non_solib_dynamic_library_gets_only_output_rpath_test,
)
solib_path_without_directory_gets_only_output_rpath_test = unittest.make(
    _solib_path_without_directory_gets_only_output_rpath_test,
)

def runtime_library_search_directories_test_suite(name = "runtime_library_search_directories_test_suite"):
    _runtime_search_enabled_subject(
        name = name + "_auto_subject",
        runtime_library_search_directories = "auto",
    )
    _runtime_search_enabled_subject(
        name = name + "_disabled_subject",
        runtime_library_search_directories = "disabled",
    )

    unittest.suite(
        name,
        partial.make(default_dynamic_origin_only_when_out_shared_libs_exist_test, size = "small"),
        partial.make(default_executable_origin_only_when_out_binaries_exist_test, size = "small"),
        partial.make(additional_dynamic_origins_do_not_affect_executable_origins_test, size = "small"),
        partial.make(additional_executable_origins_do_not_affect_dynamic_origins_test, size = "small"),
        partial.make(additional_origins_are_install_tree_relative_test, size = "small"),
        partial.make(additional_executable_origins_are_install_tree_relative_test, size = "small"),
        partial.make(self_runtime_search_directories_are_disabled_by_default_test, size = "small"),
        partial.make(self_runtime_search_directories_use_default_paths_test, size = "small"),
        partial.make(self_runtime_search_directories_use_custom_paths_test, size = "small"),
        partial.make(self_runtime_search_directories_include_additional_dynamic_origins_test, size = "small"),
        partial.make(self_runtime_search_directories_respect_mode_test, size = "small"),
        partial.make(
            auto_mode_uses_global_build_setting_test,
            size = "small",
            target_under_test = ":" + name + "_auto_subject",
        ),
        partial.make(
            disabled_overrides_enabled_global_build_setting_test,
            size = "small",
            target_under_test = ":" + name + "_disabled_subject",
        ),
        partial.make(runtime_search_directories_dedupe_dynamic_library_dirs_test, size = "small"),
        partial.make(solib_dynamic_library_gets_output_and_sibling_rpaths_test, size = "small"),
        partial.make(non_solib_dynamic_library_gets_only_output_rpath_test, size = "small"),
        partial.make(solib_path_without_directory_gets_only_output_rpath_test, size = "small"),
    )

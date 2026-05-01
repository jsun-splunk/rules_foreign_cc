"""Runtime library search directory helpers."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_cc//cc:defs.bzl", "CcInfo")
load("@rules_cc//cc/common:cc_shared_library_info.bzl", "CcSharedLibraryInfo")

RUNTIME_LIBRARY_SEARCH_DIRECTORY_ATTRIBUTES = {
    "additional_dynamic_runtime_library_search_origins": attr.string_list(
        doc = (
            "Additional install-tree-relative origins for shared-library " +
            "link actions. Values are relative to this rule's install root " +
            "and should not include lib_name or the rule name. For each " +
            "origin, runtime library search directories are derived so " +
            "shared libraries loaded from that origin can find shared " +
            "libraries from deps and dynamic_deps. When " +
            "include_self_runtime_library_search_directories is true, these " +
            "origins can also find this rule's own shared libraries."
        ),
        mandatory = False,
        default = [],
    ),
    "additional_executable_runtime_library_search_origins": attr.string_list(
        doc = (
            "Additional install-tree-relative origins for executable link " +
            "actions. Values are relative to this rule's install root and " +
            "should not include lib_name or the rule name. For each origin, " +
            "runtime library search directories are derived so executables " +
            "loaded from that origin can find shared libraries from deps " +
            "and dynamic_deps. When " +
            "include_self_runtime_library_search_directories is true, these " +
            "origins can also find this rule's own shared libraries."
        ),
        mandatory = False,
        default = [],
    ),
    "include_self_runtime_library_search_directories": attr.bool(
        doc = (
            "When true, add runtime library search directories that let " +
            "this rule's binaries, shared libraries, and additional origins " +
            "find this rule's own declared shared-library outputs. Ignored " +
            "unless runtime_library_search_directories is enabled."
        ),
        mandatory = False,
        default = False,
    ),
    "runtime_library_search_directories": attr.string(
        doc = (
            "Controls whether this target derives runtime library search " +
            "directories. Use 'auto' to follow the global " +
            "@rules_foreign_cc//foreign_cc/settings:runtime_library_search_directories " +
            "build setting, 'enabled' to force it on for this target, or " +
            "'disabled' to force it off. This is not supported for Windows " +
            "C++ toolchains."
        ),
        mandatory = False,
        values = ["auto", "enabled", "disabled"],
        default = "auto",
    ),
    "runtime_library_search_mode": attr.string(
        doc = (
            "Controls which link action kinds receive derived runtime " +
            "library search directories. Use 'shared' for shared-library " +
            "link actions, 'executable' for executable link actions, or " +
            "'all' for both."
        ),
        mandatory = False,
        values = ["shared", "executable", "all"],
        default = "all",
    ),
    "_runtime_library_search_directories": attr.label(
        default = Label("//foreign_cc/settings:runtime_library_search_directories"),
        providers = [BuildSettingInfo],
    ),
}

def _dynamic_libraries(linker_input):
    dynamic_libraries = []
    for library in linker_input.libraries:
        if library.dynamic_library:
            dynamic_libraries.append(library.dynamic_library)
    return dynamic_libraries

def _dynamic_libraries_from_dep(dep):
    dynamic_libraries = []
    if CcInfo in dep:
        for linker_input in dep[CcInfo].linking_context.linker_inputs.to_list():
            dynamic_libraries.extend(_dynamic_libraries(linker_input))

    if CcSharedLibraryInfo in dep:
        cc_shared_library_info = dep[CcSharedLibraryInfo]
        dynamic_libraries.extend(_dynamic_libraries(cc_shared_library_info.linker_input))
        for dynamic_dep in cc_shared_library_info.dynamic_deps.to_list():
            dynamic_libraries.extend(_dynamic_libraries(dynamic_dep.linker_input))

    return dynamic_libraries

def _path_segments(path):
    normalized = paths.normalize(path)
    if normalized == ".":
        return []
    return [segment for segment in normalized.split("/") if segment]

def _common_prefix_length(left, right):
    max_common_segment_count = len(left)
    if len(right) < max_common_segment_count:
        max_common_segment_count = len(right)

    for index in range(max_common_segment_count):
        if left[index] != right[index]:
            return index

    return max_common_segment_count

# Runtime search entries are relative to the directory of the object being
# loaded, i.e. `$ORIGIN` on ELF or `@loader_path` on Darwin. Calculate those
# entries in Bazel File.short_path-compatible space, not from absolute execroot
# paths. For example:
#
#   from "pkg/python/bin" to "pkg/python/lib" -> "../lib"
#   from "pkg/python/lib" to "pkg/python/lib" -> "."
#   from "pkg/python/lib/python3.10/lib-dynload" to "pkg/python/lib" -> "../.."
#
# The returned value is the part appended after the loader token.
def _relative_path(from_path, to_path):
    from_segments = _path_segments(from_path)
    to_segments = _path_segments(to_path)
    common_segment_count = _common_prefix_length(from_segments, to_segments)

    # Drop the shared prefix, then walk up from the origin and down to the target.
    relative_segments = (
        [".."] * (len(from_segments) - common_segment_count) +
        to_segments[common_segment_count:]
    )
    return "/".join(relative_segments) if relative_segments else "."

def _dedupe_strings(strings):
    # Preserve first-seen order because runtime search directory order affects
    # which matching soname the dynamic loader resolves first.
    seen = {}
    deduped = []
    for string in strings:
        if string not in seen:
            seen[string] = True
            deduped.append(string)
    return deduped

# LibraryToLink.dynamic_library often points at Bazel's solib symlink instead of
# the real generated library:
#
#   dynamic_library.short_path:
#     "_solib_k8/_Uthirdparty_Szlib/libz.so"
#
#   resolved_symlink_dynamic_library.short_path:
#     "thirdparty/zlib/zlib/lib/libz.so"
#
# Runtime search entries are interpreted relative to the object being loaded.
# If that object is loaded through Bazel's solib tree, `$ORIGIN` / `@loader_path`
# is its solib artifact directory, not its original install-tree directory.
#
# For a dependency in another solib artifact directory, add a sibling-solib
# search entry:
#
#   current origin:
#     "_solib_k8/_Uthirdparty_Sarchive"
#
#   dependency dynamic_library.short_path:
#     "_solib_k8/_Uthirdparty_Szlib/libz.so"
#
#   sibling search entry:
#     "../_Uthirdparty_Szlib"
#
# This is added in addition to the normal origin-to-dependency path because
# either the install-tree path or the solib symlink path may be the path used by
# the loader.
def _solib_sibling_search_directory(dynamic_library_short_path):
    segments = _path_segments(dynamic_library_short_path)
    if len(segments) < 3 or not segments[0].startswith("_solib_"):
        return None

    artifact_dir_under_solib = "/".join(segments[1:-1])
    if not artifact_dir_under_solib:
        return None

    return "../" + artifact_dir_under_solib

# Calculate runtime search entries from each output origin to each dependency
# dynamic library directory. Both inputs are already in Bazel
# File.short_path-compatible space:
#
#   origin_short_paths:
#     directories where this rule's binaries or shared libraries may be loaded
#
#   dynamic_library_short_paths:
#     LibraryToLink.dynamic_library.short_path values from deps/dynamic_deps
#
# Example: a foreign_cc shared library installed under this target's "lib/"
# directory depends on a Bazel shared library exposed through the solib tree:
#
#   origin:
#     "thirdparty/python/python/lib"
#
#   dependency dynamic_library.short_path:
#     "_solib_k8/_Uthirdparty_Szlib/libz.so"
#
#   dependency directory:
#     "_solib_k8/_Uthirdparty_Szlib"
#
#   rpath entry:
#     "../../../../_solib_k8/_Uthirdparty_Szlib"
#
# That entry is later interpreted relative to `$ORIGIN` / `@loader_path`, so a
# library loaded from the install-tree "lib/" directory can find the dependency
# in Bazel's solib tree.
#
# For solib dependencies, also add a sibling-solib entry. This covers the case
# where the current library is loaded through Bazel's solib symlink rather than
# through its install-tree path.
def _search_directories_for_dynamic_libraries(
        origin_short_paths,
        dynamic_library_short_paths):
    directories = []
    for dynamic_library_short_path in dynamic_library_short_paths:
        library_dir = paths.dirname(dynamic_library_short_path)
        for origin_short_path in origin_short_paths:
            directories.append(_relative_path(origin_short_path, library_dir))

        solib_sibling_directory = _solib_sibling_search_directory(dynamic_library_short_path)
        if solib_sibling_directory:
            directories.append(solib_sibling_directory)

    return _dedupe_strings(directories)

def _dynamic_library_short_paths_from_deps(ctx):
    dynamic_library_short_paths = []
    for dep in getattr(ctx.attr, "deps", []) + getattr(ctx.attr, "dynamic_deps", []):
        for dynamic_library in _dynamic_libraries_from_dep(dep):
            dynamic_library_short_paths.append(dynamic_library.short_path)
    return dynamic_library_short_paths

# Declared output files are already in Bazel File.short_path-compatible space.
# Use their parent directories as default runtime origins:
#
#   "pkg/python/bin/python3.10"   -> "pkg/python/bin"
#   "pkg/python/lib/libpython.so" -> "pkg/python/lib"
#
# These defaults come from actual declared outputs, not from out_bin_dir or
# out_lib_dir strings.
def _origin_short_paths_from_files(files):
    return _dedupe_strings([
        paths.dirname(file.short_path)
        for file in files
    ])

# Additional origins are user-facing install-tree paths, so they are relative to
# the foreign build's install root, not to the Bazel execroot or package. The
# framework gives us that install root in File.short_path-compatible space:
#
#   install root: "third_party/python/python"
#   user origin:  "lib/python3.10/lib-dynload"
#   short path:   "third_party/python/python/lib/python3.10/lib-dynload"
#
# This keeps additional origins comparable with dependency LibraryToLink
# short_path values.
def _origin_short_paths_from_install_tree(runtime_search_context, install_tree_origins):
    origin_short_paths = []
    for install_tree_origin in install_tree_origins:
        origin = install_tree_origin.lstrip("/")
        origin_short_paths.append(paths.join(
            runtime_search_context.install_root_short_path,
            origin,
        ) if origin else runtime_search_context.install_root_short_path)
    return _dedupe_strings(origin_short_paths)

def _mode_context(ctx, runtime_search_context, mode):
    if mode == "shared":
        return struct(
            additional_origins = getattr(ctx.attr, "additional_dynamic_runtime_library_search_origins", []),
            output_files = runtime_search_context.shared_files,
        )
    if mode == "executable":
        return struct(
            additional_origins = getattr(ctx.attr, "additional_executable_runtime_library_search_origins", []),
            output_files = runtime_search_context.executable_files,
        )
    fail("Unknown runtime library search mode: {}".format(mode))

def _origin_short_paths_from_mode(runtime_search_context, mode_context):
    return _dedupe_strings(
        _origin_short_paths_from_files(mode_context.output_files) +
        _origin_short_paths_from_install_tree(
            runtime_search_context,
            mode_context.additional_origins,
        ),
    )

def _self_search_directories(origin_short_paths, runtime_search_context):
    # Self output directories let this rule's binaries and shared libraries
    # find this rule's own declared shared libraries.
    directories = []
    self_library_origin_short_paths = _origin_short_paths_from_files(runtime_search_context.shared_files)
    for origin_short_path in origin_short_paths:
        for self_library_origin_short_path in self_library_origin_short_paths:
            directories.append(_relative_path(origin_short_path, self_library_origin_short_path))
    return directories

def _dependency_search_directories(ctx, origin_short_paths):
    # Dependency output directories let this rule's outputs find linked
    # dynamic libraries exposed by deps and dynamic_deps.
    return _search_directories_for_dynamic_libraries(
        origin_short_paths,
        _dynamic_library_short_paths_from_deps(ctx),
    )

def _runtime_library_search_directories_for_mode(ctx, runtime_search_context, mode):
    mode_context = _mode_context(ctx, runtime_search_context, mode)
    origin_short_paths = _origin_short_paths_from_mode(runtime_search_context, mode_context)

    directories = []
    if getattr(ctx.attr, "include_self_runtime_library_search_directories", False):
        directories.extend(_self_search_directories(origin_short_paths, runtime_search_context))

    directories.extend(_dependency_search_directories(ctx, origin_short_paths))
    return _dedupe_strings(directories)

def _mode_includes(ctx, mode):
    runtime_library_search_mode = ctx.attr.runtime_library_search_mode
    return runtime_library_search_mode == "all" or runtime_library_search_mode == mode

def runtime_library_search_directories_enabled(ctx):
    """Returns whether runtime library search directory derivation is enabled.

    Args:
      ctx: Rule context.

    Returns:
      True when runtime library search directory derivation is enabled for this
      target.
    """

    value = getattr(ctx.attr, "runtime_library_search_directories", "disabled")
    if value == "enabled":
        return True
    if value == "disabled":
        return False

    setting = getattr(ctx.attr, "_runtime_library_search_directories", None)
    return setting[BuildSettingInfo].value

def _ignored_attrs(ctx):
    ignored_attrs = []
    if getattr(ctx.attr, "additional_dynamic_runtime_library_search_origins", []):
        ignored_attrs.append("additional_dynamic_runtime_library_search_origins")
    if getattr(ctx.attr, "additional_executable_runtime_library_search_origins", []):
        ignored_attrs.append("additional_executable_runtime_library_search_origins")
    if getattr(ctx.attr, "include_self_runtime_library_search_directories", False):
        ignored_attrs.append("include_self_runtime_library_search_directories")
    return ignored_attrs

# buildifier: disable=print
def _warn_if_attrs_ignored(ctx):
    ignored_attrs = _ignored_attrs(ctx)
    if ignored_attrs:
        print((
            "WARNING: {} sets runtime_library_search attrs ({}) but " +
            "runtime_library_search_directories is disabled; " +
            "ignoring runtime_library_search attrs."
        ).format(ctx.label, ", ".join(ignored_attrs)))

def runtime_library_search_directories(ctx, runtime_search_context):
    """Returns runtime library search directories for link actions.

    Args:
      ctx: Rule context.
      runtime_search_context: Runtime search metadata for declared outputs and
        the install root in File.short_path-compatible space.

    Returns:
      A struct with `shared` and `executable` depset fields. Each field contains
      runtime library search directories for that link action kind, or None when
      the current runtime library search mode excludes that action kind.
    """

    if not runtime_library_search_directories_enabled(ctx):
        _warn_if_attrs_ignored(ctx)
        return struct(shared = None, executable = None)

    if runtime_search_context == None:
        fail("Runtime library search directory derivation requires runtime search context.")

    return struct(
        shared = depset(_runtime_library_search_directories_for_mode(ctx, runtime_search_context, "shared")) if _mode_includes(ctx, "shared") else None,
        executable = depset(_runtime_library_search_directories_for_mode(ctx, runtime_search_context, "executable")) if _mode_includes(ctx, "executable") else None,
    )

export_for_test = struct(
    runtime_library_search_directories = runtime_library_search_directories,
    search_directories_for_dynamic_libraries = _search_directories_for_dynamic_libraries,
)

"""Repository rules for fetching external tools in WORKSPACE mode"""

load("//img/private/prebuilt:prebuilt.bzl", "prebuilt_collection_hub_repo", "prebuilt_pull_hub_repo")

def _img_prebuilt_tool_from_lockfile_impl(rctx):
    """Repository rule that reads lockfile and downloads tool for specific platform."""
    lockfile_content = rctx.read(rctx.attr.lockfile)
    lockfile_data = json.decode(lockfile_content)

    target_tool = None
    for tool in lockfile_data:
        if tool["os"] == rctx.attr.os and tool["cpu"] == rctx.attr.cpu:
            target_tool = tool
            break

    if not target_tool:
        # No prebuilt binary for this platform in the lockfile.
        # Create a stub that gives a clear error at build time instead of
        # crashing during repository fetch.
        rctx.file("img.exe", content = """#!/bin/sh
echo "ERROR: No prebuilt img tool for platform {os}_{cpu}." >&2
echo "Provide a locally-built binary via img_register_prebuilt_toolchains(host_tool=...)" >&2
exit 1
""".format(os = rctx.attr.os, cpu = rctx.attr.cpu), executable = True)
        rctx.file(
            "BUILD.bazel",
            content = """exports_files(["img.exe"])""",
        )
        return

    extension = "exe" if target_tool["os"] == "windows" else ""
    dot = "." if len(extension) > 0 else ""
    url_templates = target_tool.get("url_templates", ["https://github.com/bazel-contrib/rules_img/releases/download/{version}/img_{os}_{cpu}{dot}{extension}"])

    urls = [template.format(
        version = target_tool["version"],
        os = target_tool["os"],
        cpu = target_tool["cpu"],
        dot = dot,
        extension = extension,
    ) for template in url_templates]

    rctx.download(
        urls,
        output = "img.exe",
        executable = True,
        integrity = target_tool["integrity"],
    )

    rctx.file(
        "BUILD.bazel",
        content = """exports_files(["img.exe"])""",
    )

_img_prebuilt_tool_from_lockfile = repository_rule(
    implementation = _img_prebuilt_tool_from_lockfile_impl,
    attrs = {
        "lockfile": attr.label(mandatory = True),
        "os": attr.string(mandatory = True),
        "cpu": attr.string(mandatory = True),
    },
)

def _host_tool_repo_impl(rctx):
    """Repository rule that symlinks a user-provided local binary."""
    rctx.symlink(rctx.attr.binary, rctx.attr.filename)
    rctx.file(
        "BUILD.bazel",
        content = """exports_files(["%s"])""" % rctx.attr.filename,
    )

_host_tool_repo = repository_rule(
    implementation = _host_tool_repo_impl,
    attrs = {
        "binary": attr.label(mandatory = True, allow_single_file = True),
        "filename": attr.string(default = "img.exe"),
    },
)

def img_register_prebuilt_toolchains(
        name = "img_toolchain",
        lockfile = Label("@rules_img//:prebuilt_lockfile.json"),
        host_tool = None,
        host_os = None,
        host_cpu = None,
        platforms = [
            ("linux", "amd64"),
            ("linux", "arm64"),
            ("darwin", "amd64"),
            ("darwin", "arm64"),
            ("windows", "amd64"),
            ("windows", "arm64"),
        ]):
    """Register prebuilt img toolchains for WORKSPACE mode.

    This macro creates repository rules for prebuilt img tools from a lockfile
    and registers them as Bazel toolchains. This is the WORKSPACE equivalent
    of the MODULE.bazel prebuilt_img_tool extension.

    Usage in WORKSPACE:
        load("@rules_img//img:repositories.bzl", "img_register_prebuilt_toolchains")

        # Use defaults
        img_register_prebuilt_toolchains()

        # Or provide a locally-built binary for the host platform
        img_register_prebuilt_toolchains(
            host_tool = "//:img",
            host_os = "linux",
            host_cpu = "s390x",
        )

        # Then register the toolchains
        register_toolchains("@%s//:all" % name)

    Args:
        name: Name of the toolchain collection hub repository (default: "img_toolchain")
        lockfile: Label pointing to the prebuilt lockfile.json (default: "@rules_img//:prebuilt_lockfile.json")
        host_tool: Optional label to a locally-built img binary for the host platform
        host_os: Go OS name for the host_tool (e.g., "linux"). Required if host_tool is set.
        host_cpu: Go arch name for the host_tool (e.g., "s390x"). Required if host_tool is set.
        platforms: List of (os, cpu) tuples for platforms to support via prebuilt downloads
    """

    tools = {}
    for (os, cpu) in platforms:
        repo_name = "%s_%s_%s" % (name, os, cpu)

        _img_prebuilt_tool_from_lockfile(
            name = repo_name,
            lockfile = lockfile,
            os = os,
            cpu = cpu,
        )

        platform_key = "%s_%s" % (os, cpu)
        tools[platform_key] = "@%s//:img.exe" % repo_name

    if host_tool:
        if not host_os or not host_cpu:
            fail("host_os and host_cpu are required when host_tool is set")
        repo_name = "%s_%s_%s_host" % (name, host_os, host_cpu)
        _host_tool_repo(
            name = repo_name,
            binary = host_tool,
            filename = "img.exe",
        )
        platform_key = "%s_%s" % (host_os, host_cpu)
        tools[platform_key] = "@%s//:img.exe" % repo_name

    prebuilt_collection_hub_repo(
        name = name,
        tools = tools,
    )

def _pull_tool_prebuilt_tool_from_lockfile_impl(rctx):
    """Repository rule that reads lockfile and downloads pull_tool for specific platform."""
    lockfile_content = rctx.read(rctx.attr.lockfile)
    lockfile_data = json.decode(lockfile_content)

    target_tool = None
    for tool in lockfile_data:
        if tool["os"] == rctx.attr.os and tool["cpu"] == rctx.attr.cpu:
            target_tool = tool
            break

    if not target_tool:
        rctx.file("pull_tool.exe", content = """#!/bin/sh
echo "ERROR: No prebuilt pull_tool for platform {os}_{cpu}." >&2
echo "Provide a locally-built binary via pull_tool_register_prebuilt_repositories(host_tool=...)" >&2
exit 1
""".format(os = rctx.attr.os, cpu = rctx.attr.cpu), executable = True)
        rctx.file(
            "BUILD.bazel",
            content = """exports_files(["pull_tool.exe"])""",
        )
        return

    extension = "exe" if target_tool["os"] == "windows" else ""
    dot = "." if len(extension) > 0 else ""
    url_templates = target_tool.get("url_templates", ["https://github.com/bazel-contrib/rules_img/releases/download/{version}/pull_tool_{os}_{cpu}{dot}{extension}"])

    urls = [template.format(
        version = target_tool["version"],
        os = target_tool["os"],
        cpu = target_tool["cpu"],
        dot = dot,
        extension = extension,
    ) for template in url_templates]

    rctx.download(
        urls,
        output = "pull_tool.exe",
        executable = True,
        integrity = target_tool["integrity"],
    )

    rctx.file(
        "BUILD.bazel",
        content = """exports_files(["pull_tool.exe"])""",
    )

_pull_tool_prebuilt_tool_from_lockfile = repository_rule(
    implementation = _pull_tool_prebuilt_tool_from_lockfile_impl,
    attrs = {
        "lockfile": attr.label(mandatory = True),
        "os": attr.string(mandatory = True),
        "cpu": attr.string(mandatory = True),
    },
)

def pull_tool_register_prebuilt_repositories(
        name = "pull_hub_repo",
        lockfile = Label("@rules_img//:pull_tool_lockfile.json"),
        host_tool = None,
        host_os = None,
        host_cpu = None,
        platforms = [
            ("linux", "amd64"),
            ("linux", "arm64"),
            ("darwin", "amd64"),
            ("darwin", "arm64"),
            ("windows", "amd64"),
            ("windows", "arm64"),
        ]):
    """Register prebuilt pull_tool repositories for WORKSPACE mode.

    This macro creates repository rules for prebuilt pull_tool binaries from a lockfile
    but does NOT register them as toolchains (unlike img_register_prebuilt_toolchains).
    This is the WORKSPACE equivalent of the MODULE.bazel pull_tool extension.

    Usage in WORKSPACE:
        load("@rules_img//img:repositories.bzl", "pull_tool_register_prebuilt_repositories")

        # Use defaults
        pull_tool_register_prebuilt_repositories()

        # Or provide a locally-built binary for the host platform
        pull_tool_register_prebuilt_repositories(
            host_tool = "//:pull_tool",
            host_os = "linux",
            host_cpu = "s390x",
        )

    Args:
        name: Name of the pull_tool collection hub repository (default: "pull_hub_repo")
        lockfile: Label pointing to the pull_tool_lockfile.json (default: "@rules_img//:pull_tool_lockfile.json")
        host_tool: Optional label to a locally-built pull_tool binary for the host platform
        host_os: Go OS name for the host_tool (e.g., "linux"). Required if host_tool is set.
        host_cpu: Go arch name for the host_tool (e.g., "s390x"). Required if host_tool is set.
        platforms: List of (os, cpu) tuples for platforms to support via prebuilt downloads
    """

    tools = {}
    for (os, cpu) in platforms:
        repo_name = "%s_%s_%s" % (name, os, cpu)

        _pull_tool_prebuilt_tool_from_lockfile(
            name = repo_name,
            lockfile = lockfile,
            os = os,
            cpu = cpu,
        )

        platform_key = "%s_%s" % (os, cpu)
        tools[platform_key] = "@%s//:pull_tool.exe" % repo_name

    if host_tool:
        if not host_os or not host_cpu:
            fail("host_os and host_cpu are required when host_tool is set")
        repo_name = "%s_%s_%s_host" % (name, host_os, host_cpu)
        _host_tool_repo(
            name = repo_name,
            binary = host_tool,
            filename = "pull_tool.exe",
        )
        platform_key = "%s_%s" % (host_os, host_cpu)
        tools[platform_key] = "@%s//:pull_tool.exe" % repo_name

    prebuilt_pull_hub_repo(
        name = name,
        tools = tools,
    )

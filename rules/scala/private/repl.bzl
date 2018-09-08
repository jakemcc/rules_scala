load(
    "@rules_scala_annex//rules:providers.bzl",
    _ScalaConfiguration = "ScalaConfiguration",
    _ZincConfiguration = "ZincConfiguration",
)
load("//rules/common:private/utils.bzl", "write_launcher")
load(":private/core.bzl", _scala_binary_private_attributes = "scala_binary_private_attributes")

scala_repl_private_attributes = dict({
    "_runner": attr.label(
        cfg = "host",
        executable = True,
        default = "@rules_scala_annex//rules/scala:repl",
    ),
}, **_scala_binary_private_attributes)

def scala_repl_implementation(ctx):
    scala_configuration = ctx.attr.scala[_ScalaConfiguration]
    zinc_configuration = ctx.attr.scala[_ZincConfiguration]

    classpath = depset(transitive = [dep[JavaInfo].transitive_runtime_deps for dep in ctx.attr.deps])
    runner_classpath = ctx.attr._runner[JavaInfo].transitive_runtime_deps

    args = ctx.actions.args()
    args.add("--compiler_bridge", zinc_configuration.compiler_bridge.short_path)
    args.add_all("--compiler_classpath", scala_configuration.compiler_classpath, map_each = _short_path)
    args.add_all("--classpath", classpath, map_each = _short_path)
    args.add_all(ctx.attr.scalacopts, format_each = "--compiler_option=%s")
    args.set_param_file_format("multiline")
    args_file = ctx.actions.declare_file("{}/repl.params".format(ctx.label.name))
    ctx.actions.write(args_file, args)

    launcher_files = write_launcher(
        ctx,
        ctx.outputs.bin,
        runner_classpath,
        "annex.repl.ReplRunner",
        [ctx.expand_location(f, ctx.attr.data) for f in ctx.attr.jvm_flags] + [
            "-Dbazel.runPath=$RUNPATH",
            "-DscalaAnnex.test.args=${{RUNPATH}}{}".format(args_file.short_path),
        ],
        "export TERM=xterm-color",  # https://github.com/sbt/sbt/issues/3240
    )

    files = depset(
        [args_file, zinc_configuration.compiler_bridge] + launcher_files + scala_configuration.compiler_classpath,
        transitive = [classpath, runner_classpath],
    )
    return [
        DefaultInfo(
            executable = ctx.outputs.bin,
            files = depset([ctx.outputs.bin], transitive = [files]),
            runfiles = ctx.runfiles(
                collect_default = True,
                collect_data = True,
                files = [ctx.executable._java],
                transitive_files = files,
            ),
        ),
    ]

def _short_path(file):
    return file.short_path
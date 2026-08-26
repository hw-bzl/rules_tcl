"""Nagelfar lint rules"""

load("//tcl/nagelfar:nagelfar_syntaxdb.bzl", "NagelfarSyntaxdbInfo")
load("//tcl/nagelfar:nagelfar_toolchain.bzl", "NAGELFAR_TOOLCHAIN_TYPE")
load("//tcl/private:providers.bzl", "TclInfo")
load("//tcl/private:toolchain.bzl", "TOOLCHAIN_TYPE")
load("//tcl/private:utils.bzl", "find_source_files")

def _rlocationpath(file, workspace_name):
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]

    return "{}/{}".format(workspace_name, file.short_path)

def _gather_dep_syntaxdbs(ctx):
    """Collect NagelfarSyntaxdbInfo files from direct deps and data.

    Each entry comes from either:
      - a user-declared `nagelfar_syntaxdb` target (returns the provider
        from its rule impl), or
      - a Tcl target's prior aspect run (main aspect's own return value
        on that dep, propagated here via `attr_aspects`).

    `NagelfarSyntaxdbInfo.files` is a depset, so we transitive-merge them
    and let Bazel dedupe.
    """
    parts = []
    for attr_name in ("deps", "data"):
        if hasattr(ctx.rule.attr, attr_name):
            for dep in getattr(ctx.rule.attr, attr_name):
                if NagelfarSyntaxdbInfo in dep:
                    parts.append(dep[NagelfarSyntaxdbInfo].files)
    return depset(transitive = parts)

def _tcl_nagelfar_aspect_impl(target, ctx):
    graph_syntaxdbs = _gather_dep_syntaxdbs(ctx)

    # Every source contributes to the header pass (syntaxdb), including
    # external Tcl packages — otherwise downstream consumers of
    # `@rules_tcl` / `@rules_vivado` Tcl libraries would get "Unknown
    # command" warnings for every call into those packages. The check
    # pass is separately gated on the target being main-repo (see
    # `skip_check` below), so we don't lint external sources.
    header_srcs = [
        src
        for src in find_source_files(target)
        if src.basename != "pkgIndex.tcl"
    ]
    if not header_srcs:
        return [NagelfarSyntaxdbInfo(files = graph_syntaxdbs)]

    # `no_lint`-tagged targets skip the check pass but still emit a
    # syntaxdb, so downstream nagelfar runs can resolve their procs and
    # namespaces. Without that, tagging out one library would make every
    # caller warn "Unknown command". External targets get the same
    # header-only treatment — the check pass would surface findings we
    # can't fix from this repo.
    ignore_tags = [
        "no_tcl_nagelfar",
        "no_nagelfar",
        "no_lint",
        "nolint",
    ]
    skip_check = target.label.workspace_root.startswith("external")
    if not skip_check:
        for tag in ctx.rule.attr.tags:
            sanitized = tag.replace("-", "_").lower()
            if sanitized in ignore_tags:
                skip_check = True
                break

    syntaxdb = ctx.actions.declare_file("{}.syntaxdb.tcl".format(target.label.name))

    args = ctx.actions.args()
    args.add_all(header_srcs, format_each = "--src=%s")
    args.add("--header-output", syntaxdb)
    if skip_check:
        args.add("--skip-check")

    toolchain = ctx.toolchains[TOOLCHAIN_TYPE]
    nagelfar_toolchain = ctx.toolchains[NAGELFAR_TOOLCHAIN_TYPE]

    args.add("--nagelfar", nagelfar_toolchain.nagelfar)
    args.add_all(nagelfar_toolchain.syntaxdb, format_each = "--syntaxdb=%s")
    args.add_all(graph_syntaxdbs, format_each = "--syntaxdb=%s")
    args.add_all(nagelfar_toolchain.extra_args, format_each = "--nagelfar-arg=%s")

    # `TclNagelfarHdr` when we only materialize a syntaxdb for
    # downstream aspect runs (skip-check, e.g. `no_lint` targets or
    # external targets); `TclNagelfarCheck` when we also run the lint
    # check. Distinct mnemonics keep BEP/timeline readers honest about
    # which action actually gated on findings.
    mnemonic = "TclNagelfarHdr" if skip_check else "TclNagelfarCheck"

    ctx.actions.run(
        mnemonic = mnemonic,
        executable = ctx.executable._runner,
        arguments = [args],
        inputs = depset(
            header_srcs + [nagelfar_toolchain.nagelfar] + nagelfar_toolchain.syntaxdb,
            transitive = [toolchain.all_files, graph_syntaxdbs],
        ),
        tools = [ctx.executable._runner],
        progress_message = mnemonic + " %{label}",
        outputs = [syntaxdb],
    )

    return [
        NagelfarSyntaxdbInfo(
            files = depset([syntaxdb], transitive = [graph_syntaxdbs]),
        ),
        OutputGroupInfo(
            tcl_nagelfar_checks = depset() if skip_check else depset([syntaxdb]),
        ),
    ]

tcl_nagelfar_aspect = aspect(
    doc = """\
An aspect for performing Nagelfar static analysis on Tcl targets.

The `tcl_nagelfar_aspect` applies [Nagelfar](https://nagelfar.sourceforge.net/)
checks to all Tcl targets in the dependency graph. It also traverses `deps`
and `data` (via a required collector aspect) to gather any `nagelfar_syntaxdb`
targets attached to the graph, and forwards their files to Nagelfar alongside
the toolchain-shipped databases.

**Usage:**

```bash
bazel build //my:target \\
    --aspects=@rules_tcl//tcl/nagelfar:tcl_nagelfar_aspect.bzl%tcl_nagelfar_aspect \\
    --output_groups=+tcl_nagelfar_checks
```

Or configure it in your `.bazelrc`:

```bazelrc
build:nagelfar --aspects=@rules_tcl//tcl/nagelfar:tcl_nagelfar_aspect.bzl%tcl_nagelfar_aspect
build:nagelfar --output_groups=+tcl_nagelfar_checks
```

**Ignoring targets:**

To skip Nagelfar for specific targets, add one of these tags:
- `no_tcl_nagelfar`
- `no_nagelfar`
- `no_lint`
- `nolint`
""",
    implementation = _tcl_nagelfar_aspect_impl,
    # Propagate along `deps` and `data` so every Tcl target in the graph
    # gets its own header/check action. Each run returns a
    # `NagelfarSyntaxdbInfo` covering this target's syntaxdb plus every
    # transitively inherited one; downstream runs pick that up directly
    # via `dep[NagelfarSyntaxdbInfo]`, giving nagelfar visibility into
    # proc/namespace shapes of deps without linting their sources here.
    # (A separate collector aspect would run at the wrong time — Bazel
    # applies required aspects on a target before propagating to that
    # target's deps, so the collector would fire before the deps had
    # their syntaxdbs generated.)
    attr_aspects = ["deps", "data"],
    attrs = {
        "_runner": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//tcl/nagelfar/private:runner"),
        ),
    },
    toolchains = [
        NAGELFAR_TOOLCHAIN_TYPE,
        TOOLCHAIN_TYPE,
    ],
    required_providers = [TclInfo],
)

def _tcl_nagelfar_test_impl(ctx):
    info = ctx.attr.target[TclInfo]

    # `tcl_nagelfar_aspect` runs on `target` and every Tcl dep (via
    # `attr_aspects`), leaving a `NagelfarSyntaxdbInfo` on each. We only
    # need the target's provider — its depset already includes the full
    # transitive set the aspect gathered.
    graph_syntaxdbs = ctx.attr.target[NagelfarSyntaxdbInfo].files.to_list()

    srcs = [
        src
        for src in info.srcs.to_list()
        if src.basename != "pkgIndex.tcl"
    ]

    toolchain = ctx.toolchains[TOOLCHAIN_TYPE]
    nagelfar_toolchain = ctx.toolchains[NAGELFAR_TOOLCHAIN_TYPE]

    all_syntaxdbs = nagelfar_toolchain.syntaxdb + graph_syntaxdbs

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.add("--nagelfar", _rlocationpath(nagelfar_toolchain.nagelfar, ctx.workspace_name))
    for db in all_syntaxdbs:
        args.add("--syntaxdb", _rlocationpath(db, ctx.workspace_name))
    for extra in nagelfar_toolchain.extra_args:
        args.add("--nagelfar-arg", extra)
    args.add_all([
        "--src={}".format(_rlocationpath(src, ctx.workspace_name))
        for src in srcs
    ])
    # `--header-output` intentionally omitted — the runner routes the
    # syntaxdb into $TEST_UNDECLARED_OUTPUTS_DIR at test time.

    args_file = ctx.actions.declare_file("{}.args.txt".format(ctx.label.name))
    ctx.actions.write(
        output = args_file,
        content = args,
    )

    runner = ctx.executable._runner
    executable = ctx.actions.declare_file("{}.{}".format(ctx.label.name, runner.extension).rstrip("."))
    ctx.actions.symlink(
        output = executable,
        target_file = runner,
        is_executable = True,
    )

    nagelfar_files = [nagelfar_toolchain.nagelfar] + all_syntaxdbs

    return [
        DefaultInfo(
            executable = executable,
            runfiles = ctx.runfiles(
                files = srcs + nagelfar_files + [args_file],
                transitive_files = toolchain.all_files,
            ).merge(
                ctx.attr._runner[DefaultInfo].default_runfiles,
            ),
        ),
        RunEnvironmentInfo(
            environment = {
                "RULES_TCL_NAGELFAR_ARGS_FILE": _rlocationpath(args_file, ctx.workspace_name),
            },
        ),
    ]

tcl_nagelfar_test = rule(
    doc = """\
A test rule for performing Nagelfar static analysis on a Tcl target.

**Usage:**

```python
load("@rules_tcl//tcl/nagelfar:tcl_nagelfar_test.bzl", "tcl_nagelfar_test")

tcl_nagelfar_test(
    name = "mylib_nagelfar",
    target = ":mylib",
)
```
""",
    implementation = _tcl_nagelfar_test_impl,
    test = True,
    toolchains = [
        NAGELFAR_TOOLCHAIN_TYPE,
        TOOLCHAIN_TYPE,
    ],
    attrs = {
        "target": attr.label(
            doc = "The Tcl target to perform Nagelfar analysis on.",
            aspects = [tcl_nagelfar_aspect],
            providers = [TclInfo],
            mandatory = True,
        ),
        "_runner": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//tcl/nagelfar/private:runner"),
        ),
    },
)

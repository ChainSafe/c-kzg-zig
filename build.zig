const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const portable = b.option(bool, "portable", "use portable blst (no platform-specific asm)") orelse false;

    const field_elements_per_blob = b.option(
        u32,
        "field_elements_per_blob",
        "Number of field elements per blob (default: 4096 for mainnet)",
    ) orelse 4096;

    const c_kzg_dep = b.dependency("c_kzg", .{});
    const blst_dep = b.dependency("blst", .{});

    // -------------------------------------------------------------------------
    // Build blst static library
    // -------------------------------------------------------------------------
    const blst_common_flags = &[_][]const u8{
        "-fno-builtin",
        "-Wno-unused-function",
        "-Wno-unused-command-line-argument",
    };
    const blst_avx_flag = &[_][]const u8{"-mno-avx"};

    const blst_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    if (portable) {
        blst_mod.addCMacro("__BLST_PORTABLE__", "");
    } else {
        if (std.Target.x86.featureSetHas(target.result.cpu.features, .adx)) {
            blst_mod.addCMacro("__ADX__", "");
        }
    }

    if (target.result.cpu.arch == .aarch64) {
        blst_mod.addCMacro("__ARM_FEATURE_CRYPTO", "1");
    }

    if (target.result.cpu.arch != .x86_64 and
        target.result.cpu.arch != .aarch64)
    {
        blst_mod.addCMacro("__BLST_NO_ASM__", "");
    }

    const blst_flags = if (target.result.cpu.arch == .x86_64)
        blst_common_flags ++ blst_avx_flag
    else
        blst_common_flags;

    blst_mod.addCSourceFiles(.{
        .root = blst_dep.path(""),
        .files = &.{
            "src/server.c",
            "build/assembly.S",
        },
        .flags = blst_flags,
    });
    blst_mod.addIncludePath(blst_dep.path("bindings"));

    const blst_lib = b.addLibrary(.{
        .name = "blst",
        .root_module = blst_mod,
    });
    b.installArtifact(blst_lib);

    // -------------------------------------------------------------------------
    // Build c-kzg-4844 static library (links against blst)
    // -------------------------------------------------------------------------
    const field_elem_define = b.fmt("-DFIELD_ELEMENTS_PER_BLOB={d}", .{field_elements_per_blob});

    const c_kzg_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    c_kzg_mod.addCSourceFile(.{
        .file = c_kzg_dep.path("src/ckzg.c"),
        .flags = &.{
            field_elem_define,
            "-Wno-unused-function",
            "-Wno-unused-parameter",
            "-Wno-pedantic",
        },
    });

    // c-kzg-4844 includes headers relative to its src/ directory;
    // blst.h must be found via blst/bindings.
    c_kzg_mod.addIncludePath(c_kzg_dep.path("src"));
    c_kzg_mod.addIncludePath(blst_dep.path("bindings"));
    c_kzg_mod.linkLibrary(blst_lib);

    const c_kzg_lib = b.addLibrary(.{
        .name = "c_kzg",
        .root_module = c_kzg_mod,
    });
    b.installArtifact(c_kzg_lib);

    // -------------------------------------------------------------------------
    // Zig bindings module
    // -------------------------------------------------------------------------
    const bindings_mod = b.addModule("c_kzg", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    bindings_mod.addIncludePath(c_kzg_dep.path("src"));
    bindings_mod.addIncludePath(blst_dep.path("bindings"));
    bindings_mod.linkLibrary(c_kzg_lib);

    // -------------------------------------------------------------------------
    // Tests
    // -------------------------------------------------------------------------
    const test_mod = b.createModule(.{
        .root_source_file = b.path("test/c_kzg_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c_kzg", .module = bindings_mod },
        },
    });
    test_mod.linkLibrary(c_kzg_lib);

    const tests = b.addTest(.{
        .root_module = test_mod,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const field_elements_per_blob = b.option(
        u32,
        "field_elements_per_blob",
        "Number of field elements per blob (default: 4096 for mainnet)",
    ) orelse 4096;

    const portable = b.option(bool, "portable", "use portable blst (passed through to blst.zig)") orelse false;

    const c_kzg_dep = b.dependency("c_kzg_upstream", .{});
    const blst_dep = b.dependency("blst_zig", .{
        .target = target,
        .optimize = optimize,
        .portable = portable,
    });
    const blst_lib = blst_dep.artifact("blst");

    // -------------------------------------------------------------------------
    // Build c-kzg-4844 static library
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
    // blst.h is surfaced by blst.zig via its installed header tree.
    c_kzg_mod.addIncludePath(c_kzg_dep.path("src"));
    c_kzg_mod.addIncludePath(blst_lib.getEmittedIncludeTree());

    const c_kzg_lib = b.addLibrary(.{
        .name = "c_kzg",
        .root_module = c_kzg_mod,
    });
    c_kzg_lib.installHeader(c_kzg_dep.path("src/ckzg.h"), "ckzg.h");
    c_kzg_lib.installHeadersDirectory(c_kzg_dep.path("src/common"), "common", .{});
    c_kzg_lib.installHeadersDirectory(c_kzg_dep.path("src/eip4844"), "eip4844", .{});
    c_kzg_lib.installHeadersDirectory(c_kzg_dep.path("src/eip7594"), "eip7594", .{});
    c_kzg_lib.installHeadersDirectory(c_kzg_dep.path("src/setup"), "setup", .{});
    c_kzg_lib.installLibraryHeaders(blst_lib);
    b.installArtifact(c_kzg_lib);

    // -------------------------------------------------------------------------
    // Trusted setup data
    // -------------------------------------------------------------------------
    const trusted_setup = c_kzg_dep.path("src/trusted_setup.txt");
    b.addNamedLazyPath("trusted_setup", trusted_setup);
    b.getInstallStep().dependOn(&b.addInstallFile(trusted_setup, "trusted_setup.txt").step);

    // -------------------------------------------------------------------------
    // Tests
    // -------------------------------------------------------------------------
    const test_mod = b.createModule(.{
        .root_source_file = b.path("test/c_kzg_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.linkLibrary(c_kzg_lib);
    test_mod.linkLibrary(blst_lib);

    const tests = b.addTest(.{
        .root_module = test_mod,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}

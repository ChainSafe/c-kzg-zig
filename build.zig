const std = @import("std");

const bytes_per_g1 = 48;
const bytes_per_g2 = 96;

const ParsedTrustedSetup = struct {
    num_g1_points: usize,
    num_g2_points: usize,
    g1_lagrange_bytes: []const u8,
    g2_monomial_bytes: []const u8,
    g1_monomial_bytes: []const u8,
};

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
    const trusted_setup_mod = addTrustedSetupModule(b, trusted_setup);
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
    test_mod.addImport("trusted_setup", trusted_setup_mod);

    const tests = b.addTest(.{
        .root_module = test_mod,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}

fn addTrustedSetupModule(b: *std.Build, trusted_setup_txt: std.Build.LazyPath) *std.Build.Module {
    const parsed = parseTrustedSetupFile(b, trusted_setup_txt);

    const write_files = b.addWriteFiles();
    _ = write_files.add("g1_lagrange.bin", parsed.g1_lagrange_bytes);
    _ = write_files.add("g2_monomial.bin", parsed.g2_monomial_bytes);
    _ = write_files.add("g1_monomial.bin", parsed.g1_monomial_bytes);

    const source = write_files.add("trusted_setup.zig", b.fmt(
        \\// Generated from upstream src/trusted_setup.txt by build.zig.
        \\pub const bytes_per_g1: usize = {d};
        \\pub const bytes_per_g2: usize = {d};
        \\pub const num_g1_points: usize = {d};
        \\pub const num_g2_points: usize = {d};
        \\
        \\pub const g1_lagrange_bytes = @embedFile("g1_lagrange.bin")[0 .. num_g1_points * bytes_per_g1];
        \\pub const g2_monomial_bytes = @embedFile("g2_monomial.bin")[0 .. num_g2_points * bytes_per_g2];
        \\pub const g1_monomial_bytes = @embedFile("g1_monomial.bin")[0 .. num_g1_points * bytes_per_g1];
        \\
        \\pub const Data = struct {{
        \\    g1_monomial_bytes: []const u8,
        \\    g1_lagrange_bytes: []const u8,
        \\    g2_monomial_bytes: []const u8,
        \\}};
        \\
        \\pub const data: Data = .{{
        \\    .g1_monomial_bytes = g1_monomial_bytes,
        \\    .g1_lagrange_bytes = g1_lagrange_bytes,
        \\    .g2_monomial_bytes = g2_monomial_bytes,
        \\}};
        \\
    , .{ bytes_per_g1, bytes_per_g2, parsed.num_g1_points, parsed.num_g2_points }));

    return b.addModule("trusted_setup", .{
        .root_source_file = source,
    });
}

fn parseTrustedSetupFile(b: *std.Build, trusted_setup_txt: std.Build.LazyPath) ParsedTrustedSetup {
    const path = trusted_setup_txt.getPath(b);
    const contents = std.Io.Dir.cwd().readFileAlloc(
        b.graph.io,
        path,
        b.allocator,
        .limited(std.math.maxInt(usize)),
    ) catch |err| {
        buildPanic(b, "failed to read trusted setup from {s}: {s}", .{ path, @errorName(err) });
    };

    var tokens = std.mem.tokenizeAny(u8, contents, " \t\r\n");
    const num_g1_points = parseCountToken(b, &tokens, path, "g1 point count");
    const num_g2_points = parseCountToken(b, &tokens, path, "g2 point count");

    const g1_lagrange_bytes = parseHexSection(
        b,
        &tokens,
        path,
        "g1_lagrange_bytes",
        num_g1_points,
        bytes_per_g1,
    );
    const g2_monomial_bytes = parseHexSection(
        b,
        &tokens,
        path,
        "g2_monomial_bytes",
        num_g2_points,
        bytes_per_g2,
    );
    const g1_monomial_bytes = parseHexSection(
        b,
        &tokens,
        path,
        "g1_monomial_bytes",
        num_g1_points,
        bytes_per_g1,
    );

    if (tokens.next() != null) {
        buildPanic(b, "trusted setup at {s} has trailing data after the expected sections", .{path});
    }

    return .{
        .num_g1_points = num_g1_points,
        .num_g2_points = num_g2_points,
        .g1_lagrange_bytes = g1_lagrange_bytes,
        .g2_monomial_bytes = g2_monomial_bytes,
        .g1_monomial_bytes = g1_monomial_bytes,
    };
}

fn parseCountToken(b: *std.Build, tokens: anytype, path: []const u8, label: []const u8) usize {
    const token = tokens.next() orelse {
        buildPanic(b, "trusted setup at {s} is missing {s}", .{ path, label });
    };
    return std.fmt.parseUnsigned(usize, token, 10) catch |err| {
        buildPanic(
            b,
            "failed to parse {s} in trusted setup at {s}: {s}",
            .{ label, path, @errorName(err) },
        );
    };
}

fn parseHexSection(
    b: *std.Build,
    tokens: anytype,
    path: []const u8,
    label: []const u8,
    point_count: usize,
    bytes_per_point: usize,
) []const u8 {
    const total_len = point_count * bytes_per_point;
    const out = b.allocator.alloc(u8, total_len) catch @panic("OOM");

    for (0..point_count) |point_index| {
        const token = tokens.next() orelse {
            buildPanic(
                b,
                "trusted setup at {s} is missing point {d} for {s}",
                .{ path, point_index, label },
            );
        };
        if (token.len != bytes_per_point * 2) {
            buildPanic(
                b,
                "trusted setup at {s} has invalid hex length for point {d} in {s}: expected {d}, found {d}",
                .{ path, point_index, label, bytes_per_point * 2, token.len },
            );
        }

        const start = point_index * bytes_per_point;
        _ = std.fmt.hexToBytes(out[start .. start + bytes_per_point], token) catch |err| {
            buildPanic(
                b,
                "failed to decode point {d} in {s} from trusted setup at {s}: {s}",
                .{ point_index, label, path, @errorName(err) },
            );
        };
    }

    return out;
}

fn buildPanic(b: *std.Build, comptime fmt: []const u8, args: anytype) noreturn {
    @panic(b.fmt(fmt, args));
}

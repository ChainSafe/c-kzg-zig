const std = @import("std");
const c = @cImport({
    @cInclude("ckzg.h");
});

fn trustedSetupPath() ?[]const u8 {
    const val = std.c.getenv("C_KZG_TRUSTED_SETUP_PATH") orelse return null;
    return std.mem.span(val);
}

fn expectOk(ret: c.C_KZG_RET) !void {
    try std.testing.expectEqual(@as(c.C_KZG_RET, c.C_KZG_OK), ret);
}

fn loadSetup(allocator: std.mem.Allocator) !?c.KZGSettings {
    const path = trustedSetupPath() orelse return null;
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const file = c.fopen(path_z.ptr, "r") orelse return error.FileOpenFailed;
    defer _ = c.fclose(file);

    var settings: c.KZGSettings = undefined;
    try expectOk(c.load_trusted_setup_file(&settings, file, 0));
    return settings;
}

test "constants" {
    try std.testing.expectEqual(@as(usize, 4096), @as(usize, @intCast(c.FIELD_ELEMENTS_PER_BLOB)));
    try std.testing.expectEqual(@as(usize, 32), @as(usize, @intCast(c.BYTES_PER_FIELD_ELEMENT)));
    try std.testing.expectEqual(@as(usize, 131072), @as(usize, @intCast(c.BYTES_PER_BLOB)));
    try std.testing.expectEqual(@as(usize, 48), @as(usize, @intCast(c.BYTES_PER_COMMITMENT)));
    try std.testing.expectEqual(@as(usize, 48), @as(usize, @intCast(c.BYTES_PER_PROOF)));
    try std.testing.expectEqual(@as(usize, 64), @as(usize, @intCast(c.FIELD_ELEMENTS_PER_CELL)));
    try std.testing.expectEqual(@as(usize, 2048), @as(usize, @intCast(c.BYTES_PER_CELL)));
    try std.testing.expectEqual(@as(usize, 64), @as(usize, @intCast(c.CELLS_PER_BLOB)));
    try std.testing.expectEqual(@as(usize, 128), @as(usize, @intCast(c.CELLS_PER_EXT_BLOB)));
}

test "load trusted setup" {
    const allocator = std.testing.allocator;
    var settings = try loadSetup(allocator) orelse return;
    defer c.free_trusted_setup(&settings);
}

test "blob to commitment" {
    const allocator = std.testing.allocator;
    var settings = try loadSetup(allocator) orelse return;
    defer c.free_trusted_setup(&settings);

    var blob = std.mem.zeroes(c.Blob);
    var commitment: c.KZGCommitment = undefined;
    try expectOk(c.blob_to_kzg_commitment(&commitment, &blob, &settings));
    try std.testing.expectEqual(@as(usize, 48), commitment.bytes.len);
}

test "compute and verify blob kzg proof" {
    const allocator = std.testing.allocator;
    var settings = try loadSetup(allocator) orelse return;
    defer c.free_trusted_setup(&settings);

    var blob = std.mem.zeroes(c.Blob);
    var commitment: c.KZGCommitment = undefined;
    var proof: c.KZGProof = undefined;
    var ok = false;

    try expectOk(c.blob_to_kzg_commitment(&commitment, &blob, &settings));
    try expectOk(c.compute_blob_kzg_proof(&proof, &blob, &commitment, &settings));
    try expectOk(c.verify_blob_kzg_proof(&ok, &blob, &commitment, &proof, &settings));
    try std.testing.expect(ok);
}

test "batch verify blob kzg proofs" {
    const allocator = std.testing.allocator;
    var settings = try loadSetup(allocator) orelse return;
    defer c.free_trusted_setup(&settings);

    var blob = std.mem.zeroes(c.Blob);
    var commitment: c.KZGCommitment = undefined;
    var proof: c.KZGProof = undefined;
    var ok = false;

    try expectOk(c.blob_to_kzg_commitment(&commitment, &blob, &settings));
    try expectOk(c.compute_blob_kzg_proof(&proof, &blob, &commitment, &settings));

    const blobs = [_]c.Blob{ blob, blob };
    const commitments = [_]c.KZGCommitment{ commitment, commitment };
    const proofs = [_]c.KZGProof{ proof, proof };

    try expectOk(c.verify_blob_kzg_proof_batch(
        &ok,
        &blobs,
        &commitments,
        &proofs,
        blobs.len,
        &settings,
    ));
    try std.testing.expect(ok);
}

test "compute cells and kzg proofs" {
    const allocator = std.testing.allocator;
    var settings = try loadSetup(allocator) orelse return;
    defer c.free_trusted_setup(&settings);

    const cell_count: usize = @intCast(c.CELLS_PER_EXT_BLOB);
    var blob = std.mem.zeroes(c.Blob);
    var cells: [cell_count]c.Cell = undefined;
    var proofs: [cell_count]c.KZGProof = undefined;

    try expectOk(c.compute_cells_and_kzg_proofs(&cells, &proofs, &blob, &settings));
}

test "recover cells and kzg proofs" {
    const allocator = std.testing.allocator;
    var settings = try loadSetup(allocator) orelse return;
    defer c.free_trusted_setup(&settings);

    const cell_count: usize = @intCast(c.CELLS_PER_EXT_BLOB);
    const num_provided = cell_count / 2;

    var blob = std.mem.zeroes(c.Blob);
    var computed_cells: [cell_count]c.Cell = undefined;
    var computed_proofs: [cell_count]c.KZGProof = undefined;
    var recovered_cells: [cell_count]c.Cell = undefined;
    var recovered_proofs: [cell_count]c.KZGProof = undefined;
    var indices: [num_provided]u64 = undefined;
    var cells: [num_provided]c.Cell = undefined;

    try expectOk(c.compute_cells_and_kzg_proofs(&computed_cells, &computed_proofs, &blob, &settings));

    for (0..num_provided) |i| {
        indices[i] = @intCast(i);
        cells[i] = computed_cells[i];
    }

    try expectOk(c.recover_cells_and_kzg_proofs(
        &recovered_cells,
        &recovered_proofs,
        &indices,
        &cells,
        num_provided,
        &settings,
    ));

    for (0..cell_count) |i| {
        try std.testing.expectEqualSlices(u8, &computed_cells[i].bytes, &recovered_cells[i].bytes);
        try std.testing.expectEqualSlices(u8, &computed_proofs[i].bytes, &recovered_proofs[i].bytes);
    }
}

test "verify cell kzg proof batch" {
    const allocator = std.testing.allocator;
    var settings = try loadSetup(allocator) orelse return;
    defer c.free_trusted_setup(&settings);

    const n = 4;
    const cell_count: usize = @intCast(c.CELLS_PER_EXT_BLOB);

    var blob = std.mem.zeroes(c.Blob);
    var commitment: c.KZGCommitment = undefined;
    var computed_cells: [cell_count]c.Cell = undefined;
    var computed_proofs: [cell_count]c.KZGProof = undefined;
    var commitments_per_cell: [n]c.KZGCommitment = undefined;
    var cell_indices: [n]u64 = undefined;
    var cells: [n]c.Cell = undefined;
    var proofs: [n]c.KZGProof = undefined;
    var ok = false;

    try expectOk(c.blob_to_kzg_commitment(&commitment, &blob, &settings));
    try expectOk(c.compute_cells_and_kzg_proofs(&computed_cells, &computed_proofs, &blob, &settings));

    for (0..n) |i| {
        commitments_per_cell[i] = commitment;
        cell_indices[i] = @intCast(i);
        cells[i] = computed_cells[i];
        proofs[i] = computed_proofs[i];
    }

    try expectOk(c.verify_cell_kzg_proof_batch(
        &ok,
        &commitments_per_cell,
        &cell_indices,
        &cells,
        &proofs,
        n,
        &settings,
    ));
    try std.testing.expect(ok);
}

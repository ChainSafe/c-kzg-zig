const std = @import("std");
const kzg = @import("c_kzg");

/// Path to the trusted setup file from c-kzg-4844.
/// Set via environment variable C_KZG_TRUSTED_SETUP_PATH, or falls back to
/// a path relative to the project root (works when running from repo directory).
fn trustedSetupPath() ?[]const u8 {
    const val = std.c.getenv("C_KZG_TRUSTED_SETUP_PATH") orelse return null;
    return std.mem.span(val);
}

// ---------------------------------------------------------------------------
// Compile-time smoke test: verify constants match spec
// ---------------------------------------------------------------------------

test "constants" {
    try std.testing.expectEqual(@as(usize, 4096), kzg.FIELD_ELEMENTS_PER_BLOB);
    try std.testing.expectEqual(@as(usize, 32), kzg.BYTES_PER_FIELD_ELEMENT);
    try std.testing.expectEqual(@as(usize, 131072), kzg.BYTES_PER_BLOB);
    try std.testing.expectEqual(@as(usize, 48), kzg.BYTES_PER_COMMITMENT);
    try std.testing.expectEqual(@as(usize, 48), kzg.BYTES_PER_PROOF);
    try std.testing.expectEqual(@as(usize, 64), kzg.FIELD_ELEMENTS_PER_CELL);
    try std.testing.expectEqual(@as(usize, 2048), kzg.BYTES_PER_CELL);
    try std.testing.expectEqual(@as(usize, 64), kzg.CELLS_PER_BLOB);
    try std.testing.expectEqual(@as(usize, 128), kzg.CELLS_PER_EXT_BLOB);
}

// ---------------------------------------------------------------------------
// Integration tests (require trusted setup file)
// ---------------------------------------------------------------------------

/// Load the trusted setup from the environment-specified path.
/// Returns null if C_KZG_TRUSTED_SETUP_PATH is not set (skip integration tests).
fn loadSetup(allocator: std.mem.Allocator) !?*kzg.KzgSettings {
    const path = trustedSetupPath() orelse return null;
    return try kzg.loadTrustedSetupFile(allocator, path);
}

test "load trusted setup" {
    const allocator = std.testing.allocator;
    const settings = try loadSetup(allocator) orelse {
        std.debug.print("SKIP: set C_KZG_TRUSTED_SETUP_PATH to enable integration tests\n", .{});
        return;
    };
    defer kzg.freeTrustedSetup(allocator, settings);
    // If we got here without error, the setup loaded fine.
    try std.testing.expect(true);
}

test "blob to commitment" {
    const allocator = std.testing.allocator;
    const settings = try loadSetup(allocator) orelse return;
    defer kzg.freeTrustedSetup(allocator, settings);

    // All-zero blob is a valid input.
    var blob: kzg.Blob = [_]u8{0} ** kzg.BYTES_PER_BLOB;
    const commitment = try kzg.blobToKzgCommitment(&blob, settings);
    // Commitment is 48 bytes; just verify it's non-null (a real value was computed).
    try std.testing.expectEqual(@as(usize, 48), commitment.len);
}

test "compute and verify blob kzg proof" {
    const allocator = std.testing.allocator;
    const settings = try loadSetup(allocator) orelse return;
    defer kzg.freeTrustedSetup(allocator, settings);

    var blob: kzg.Blob = [_]u8{0} ** kzg.BYTES_PER_BLOB;
    const commitment = try kzg.blobToKzgCommitment(&blob, settings);
    const proof = try kzg.computeBlobKzgProof(&blob, &commitment, settings);
    const ok = try kzg.verifyBlobKzgProof(&blob, &commitment, &proof, settings);
    try std.testing.expect(ok);
}

test "batch verify blob kzg proofs" {
    const allocator = std.testing.allocator;
    const settings = try loadSetup(allocator) orelse return;
    defer kzg.freeTrustedSetup(allocator, settings);

    // Use two identical all-zero blobs.
    const blob: kzg.Blob = [_]u8{0} ** kzg.BYTES_PER_BLOB;
    const commitment = try kzg.blobToKzgCommitment(&blob, settings);
    const proof = try kzg.computeBlobKzgProof(&blob, &commitment, settings);

    const blobs = [_]kzg.Blob{ blob, blob };
    const commitments = [_]kzg.KzgCommitment{ commitment, commitment };
    const proofs = [_]kzg.KzgProof{ proof, proof };

    const ok = try kzg.verifyBlobKzgProofBatch(&blobs, &commitments, &proofs, settings);
    try std.testing.expect(ok);
}

test "compute cells and kzg proofs" {
    const allocator = std.testing.allocator;
    const settings = try loadSetup(allocator) orelse return;
    defer kzg.freeTrustedSetup(allocator, settings);

    const blob: kzg.Blob = [_]u8{0} ** kzg.BYTES_PER_BLOB;
    const result = try kzg.computeCellsAndKzgProofs(&blob, settings);
    try std.testing.expectEqual(kzg.CELLS_PER_EXT_BLOB, result.cells.len);
    try std.testing.expectEqual(kzg.CELLS_PER_EXT_BLOB, result.proofs.len);
}

test "recover cells and kzg proofs" {
    const allocator = std.testing.allocator;
    const settings = try loadSetup(allocator) orelse return;
    defer kzg.freeTrustedSetup(allocator, settings);

    const blob: kzg.Blob = [_]u8{0} ** kzg.BYTES_PER_BLOB;
    const computed = try kzg.computeCellsAndKzgProofs(&blob, settings);

    // Provide only the first half of the cells for recovery.
    const num_provided = kzg.CELLS_PER_EXT_BLOB / 2;
    var indices: [num_provided]u64 = undefined;
    var cells: [num_provided]kzg.Cell = undefined;
    for (0..num_provided) |i| {
        indices[i] = @intCast(i);
        cells[i] = computed.cells[i];
    }

    const recovered = try kzg.recoverCellsAndKzgProofs(&indices, &cells, settings);
    // The recovered cells should match the originally computed cells.
    for (0..kzg.CELLS_PER_EXT_BLOB) |i| {
        try std.testing.expectEqualSlices(u8, &computed.cells[i], &recovered.cells[i]);
    }
}

test "verify cell kzg proof batch" {
    const allocator = std.testing.allocator;
    const settings = try loadSetup(allocator) orelse return;
    defer kzg.freeTrustedSetup(allocator, settings);

    const blob: kzg.Blob = [_]u8{0} ** kzg.BYTES_PER_BLOB;
    const commitment = try kzg.blobToKzgCommitment(&blob, settings);
    const computed = try kzg.computeCellsAndKzgProofs(&blob, settings);

    // Verify a subset of cells.
    // commitments_per_cell: one commitment per cell entry (repeat for same blob).
    const n = 4;
    var commitments_per_cell: [n]kzg.KzgCommitment = undefined;
    var cell_indices: [n]u64 = undefined;
    var cells: [n]kzg.Cell = undefined;
    var proofs: [n]kzg.KzgProof = undefined;

    for (0..n) |i| {
        commitments_per_cell[i] = commitment;
        cell_indices[i] = @intCast(i);
        cells[i] = computed.cells[i];
        proofs[i] = computed.proofs[i];
    }

    const ok = try kzg.verifyCellKzgProofBatch(
        allocator,
        &commitments_per_cell,
        &cell_indices,
        &cells,
        &proofs,
        settings,
    );
    try std.testing.expect(ok);
}

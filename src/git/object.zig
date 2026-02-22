const std = @import("std");

/// Git object types
pub const ObjectType = enum {
    blob,
    tree,
    commit,
    tag,
};

/// A parsed git object
pub const Object = struct {
    obj_type: ObjectType,
    data: []const u8,
};

/// Read and decompress a loose git object by its hex SHA.
/// Returns the decompressed content (header + data). Caller must free with allocator.
pub fn readLoose(allocator: std.mem.Allocator, git_dir: []const u8, hex_sha: []const u8) ![]u8 {
    if (hex_sha.len < 4) return error.InvalidSha;

    // Build path: <git_dir>/objects/XX/YYYY...
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const obj_path = try std.fmt.bufPrint(&path_buf, "{s}/objects/{s}/{s}", .{
        git_dir,
        hex_sha[0..2],
        hex_sha[2..],
    });

    const compressed = std.fs.cwd().readFileAlloc(allocator, obj_path, 50 * 1024 * 1024) catch {
        return error.ObjectNotFound;
    };
    defer allocator.free(compressed);

    return zlibDecompress(allocator, compressed);
}

/// Parse the header of a decompressed git object.
/// Returns the type and data portion (after the NUL byte).
pub fn parseObject(raw: []const u8) !Object {
    // Format: "<type> <size>\0<content>"
    const nul_pos = std.mem.indexOfScalar(u8, raw, 0) orelse return error.InvalidObject;
    const header = raw[0..nul_pos];
    const space_pos = std.mem.indexOfScalar(u8, header, ' ') orelse return error.InvalidObject;
    const type_str = header[0..space_pos];

    const obj_type: ObjectType = if (std.mem.eql(u8, type_str, "commit"))
        .commit
    else if (std.mem.eql(u8, type_str, "tree"))
        .tree
    else if (std.mem.eql(u8, type_str, "blob"))
        .blob
    else if (std.mem.eql(u8, type_str, "tag"))
        .tag
    else
        return error.UnknownObjectType;

    return Object{
        .obj_type = obj_type,
        .data = raw[nul_pos + 1 ..],
    };
}

/// Read a loose object and parse it. Caller must free returned raw with allocator.
pub fn readAndParse(allocator: std.mem.Allocator, git_dir: []const u8, hex_sha: []const u8) !struct { obj: Object, raw: []u8 } {
    const raw = try readLoose(allocator, git_dir, hex_sha);
    errdefer allocator.free(raw);
    const obj = try parseObject(raw);
    return .{ .obj = obj, .raw = raw };
}

/// Search packfiles for an object by its binary SHA.
/// Returns decompressed raw content (header + data). Caller must free.
pub fn readPacked(allocator: std.mem.Allocator, git_dir: []const u8, sha: [20]u8) ![]u8 {
    // List .idx files in <git_dir>/objects/pack/
    var pack_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const pack_dir_path = try std.fmt.bufPrint(&pack_dir_buf, "{s}/objects/pack", .{git_dir});

    var pack_dir = std.fs.cwd().openDir(pack_dir_path, .{ .iterate = true }) catch {
        return error.ObjectNotFound;
    };
    defer pack_dir.close();

    var iter = pack_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".idx")) continue;

        // Try to find the object in this index
        if (searchPackIndex(allocator, git_dir, pack_dir_path, entry.name, sha)) |result| {
            return result;
        } else |_| {
            continue;
        }
    }

    return error.ObjectNotFound;
}

fn searchPackIndex(
    allocator: std.mem.Allocator,
    git_dir: []const u8,
    pack_dir_path: []const u8,
    idx_name: []const u8,
    sha: [20]u8,
) ![]u8 {
    _ = git_dir;
    var idx_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const idx_path = try std.fmt.bufPrint(&idx_path_buf, "{s}/{s}", .{ pack_dir_path, idx_name });

    const idx_data = std.fs.cwd().readFileAlloc(allocator, idx_path, 100 * 1024 * 1024) catch {
        return error.ObjectNotFound;
    };
    defer allocator.free(idx_data);

    // Pack index v2 format:
    // 4 bytes magic: \377tOc
    // 4 bytes version: 2
    // 256 * 4 bytes: fanout table
    // N * 20 bytes: SHA table
    // N * 4 bytes: CRC table
    // N * 4 bytes: offset table
    // (optional large offsets)
    // 20 bytes: packfile SHA
    // 20 bytes: index SHA

    if (idx_data.len < 8 + 256 * 4) return error.InvalidPackIndex;

    // Check magic
    if (!std.mem.eql(u8, idx_data[0..4], "\xff\x74\x4f\x63")) return error.InvalidPackIndex;
    const version = std.mem.readInt(u32, idx_data[4..8], .big);
    if (version != 2) return error.UnsupportedPackVersion;

    // Fanout table starts at offset 8
    const fanout_offset: usize = 8;
    const total_objects = std.mem.readInt(u32, idx_data[fanout_offset + 255 * 4 ..][0..4], .big);

    // Binary search in the SHA table
    const sha_table_offset: usize = fanout_offset + 256 * 4;

    // Use fanout to narrow search range
    const fan_byte = sha[0];
    const lo: u32 = if (fan_byte == 0) 0 else std.mem.readInt(u32, idx_data[fanout_offset + (@as(usize, fan_byte) - 1) * 4 ..][0..4], .big);
    const hi: u32 = std.mem.readInt(u32, idx_data[fanout_offset + @as(usize, fan_byte) * 4 ..][0..4], .big);

    // Binary search
    var low = lo;
    var high = hi;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const entry_offset = sha_table_offset + @as(usize, mid) * 20;
        if (entry_offset + 20 > idx_data.len) return error.InvalidPackIndex;
        const entry_sha = idx_data[entry_offset..][0..20];
        const order = std.mem.order(u8, entry_sha, &sha);
        if (order == .lt) {
            low = mid + 1;
        } else if (order == .gt) {
            high = mid;
        } else {
            // Found it! Get the offset from offset table
            const crc_table_offset = sha_table_offset + @as(usize, total_objects) * 20;
            const offset_table_offset = crc_table_offset + @as(usize, total_objects) * 4;
            const off_entry = offset_table_offset + @as(usize, mid) * 4;
            if (off_entry + 4 > idx_data.len) return error.InvalidPackIndex;
            const pack_offset = std.mem.readInt(u32, idx_data[off_entry..][0..4], .big);

            // If MSB set, it's a large offset — bail
            if (pack_offset & 0x80000000 != 0) return error.UnsupportedPackFeature;

            // Read from the packfile
            const pack_name = std.mem.trimRight(u8, idx_name[0 .. idx_name.len - 4], "");
            var pack_path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const pack_path = try std.fmt.bufPrint(&pack_path_buf, "{s}/{s}.pack", .{ pack_dir_path, pack_name });

            return readPackObject(allocator, pack_path, pack_offset);
        }
    }

    return error.ObjectNotFound;
}

fn readPackObject(allocator: std.mem.Allocator, pack_path: []const u8, offset: u32) ![]u8 {
    const file = std.fs.cwd().openFile(pack_path, .{}) catch return error.ObjectNotFound;
    defer file.close();

    try file.seekTo(offset);

    // Read pack object header (variable length encoding)
    var byte: [1]u8 = undefined;
    _ = try file.read(&byte);
    const obj_type_bits: u3 = @truncate((byte[0] >> 4) & 0x7);
    var size: u64 = byte[0] & 0xF;
    var shift: u6 = 4;

    var b = byte[0];
    while (b & 0x80 != 0) {
        _ = try file.read(&byte);
        b = byte[0];
        size |= @as(u64, b & 0x7F) << shift;
        shift += 7;
    }

    // Object types: 1=commit, 2=tree, 3=blob, 4=tag, 6=ofs_delta, 7=ref_delta
    if (obj_type_bits == 6 or obj_type_bits == 7) {
        // Delta objects — bail out, let caller fall back to subprocess
        return error.DeltaObject;
    }

    const type_str = switch (obj_type_bits) {
        1 => "commit",
        2 => "tree",
        3 => "blob",
        4 => "tag",
        else => return error.UnknownObjectType,
    };

    // Read remaining compressed data
    const pos = try file.getPos();
    const file_size = try file.getEndPos();
    const remaining = file_size - pos;
    const compressed = try allocator.alloc(u8, @intCast(remaining));
    defer allocator.free(compressed);
    const bytes_read = try file.readAll(compressed);

    const decompressed = try zlibDecompress(allocator, compressed[0..bytes_read]);
    defer allocator.free(decompressed);

    // Build standard git object format: "<type> <size>\0<data>"
    const header = try std.fmt.allocPrint(allocator, "{s} {d}\x00", .{ type_str, decompressed.len });
    defer allocator.free(header);

    const result = try allocator.alloc(u8, header.len + decompressed.len);
    @memcpy(result[0..header.len], header);
    @memcpy(result[header.len..], decompressed);

    return result;
}

/// Read any git object (loose first, then packfiles). Returns raw decompressed content.
pub fn readObject(allocator: std.mem.Allocator, git_dir: []const u8, hex_sha: []const u8) ![]u8 {
    // Try loose first
    return readLoose(allocator, git_dir, hex_sha) catch {
        // Try packfiles
        var sha: [20]u8 = undefined;
        hexToSha(hex_sha, &sha) catch return error.InvalidSha;
        return readPacked(allocator, git_dir, sha);
    };
}

pub fn hexToSha(hex: []const u8, out: *[20]u8) !void {
    if (hex.len != 40) return error.InvalidSha;
    for (0..20) |i| {
        out[i] = std.fmt.parseInt(u8, hex[i * 2 ..][0..2], 16) catch return error.InvalidSha;
    }
}

pub fn shaToHex(sha: [20]u8) [40]u8 {
    var hex: [40]u8 = undefined;
    for (sha, 0..) |byte, i| {
        const chars = "0123456789abcdef";
        hex[i * 2] = chars[byte >> 4];
        hex[i * 2 + 1] = chars[byte & 0xf];
    }
    return hex;
}

fn zlibDecompress(allocator: std.mem.Allocator, compressed: []const u8) ![]u8 {
    var input_reader = std.Io.Reader.fixed(compressed);
    var decompressor = std.compress.flate.Decompress.init(&input_reader, .zlib, &.{});

    return decompressor.reader.allocRemaining(allocator, std.Io.Limit.limited(50 * 1024 * 1024)) catch return error.DecompressFailed;
}

test "shaToHex" {
    const sha = [20]u8{ 0xab, 0xcd, 0xef, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0x01 };
    const hex = shaToHex(sha);
    try std.testing.expectEqualStrings("abcdef0123456789abcdef0123456789abcdef01", &hex);
}

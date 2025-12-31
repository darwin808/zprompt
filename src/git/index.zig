const std = @import("std");

/// Git index file header
pub const IndexHeader = struct {
    signature: [4]u8, // "DIRC"
    version: u32,
    entry_count: u32,
};

/// A single index entry
pub const IndexEntry = struct {
    ctime_sec: u32,
    ctime_nsec: u32,
    mtime_sec: u32,
    mtime_nsec: u32,
    dev: u32,
    ino: u32,
    mode: u32,
    uid: u32,
    gid: u32,
    size: u32,
    sha1: [20]u8,
    flags: u16,
    path: []const u8,

    /// Get the stage number (0 = normal, 1-3 = merge conflict stages)
    pub fn stage(self: IndexEntry) u2 {
        return @truncate((self.flags >> 12) & 0x3);
    }

    /// Check if this entry is in a merge conflict
    pub fn isConflicted(self: IndexEntry) bool {
        return self.stage() != 0;
    }
};

/// Parsed git index
pub const Index = struct {
    header: IndexHeader,
    entries: []IndexEntry,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Index) void {
        for (self.entries) |entry| {
            self.allocator.free(entry.path);
        }
        self.allocator.free(self.entries);
    }
};

/// Parse a git index file
pub fn parse(allocator: std.mem.Allocator, data: []const u8) !Index {
    if (data.len < 12) return error.InvalidIndex;

    // Parse header
    const header = IndexHeader{
        .signature = data[0..4].*,
        .version = std.mem.readInt(u32, data[4..8], .big),
        .entry_count = std.mem.readInt(u32, data[8..12], .big),
    };

    // Verify signature
    if (!std.mem.eql(u8, &header.signature, "DIRC")) {
        return error.InvalidSignature;
    }

    // We support version 2, 3, and 4
    if (header.version < 2 or header.version > 4) {
        return error.UnsupportedVersion;
    }

    // Parse entries
    var entries: std.ArrayList(IndexEntry) = .{};
    errdefer {
        for (entries.items) |entry| {
            allocator.free(entry.path);
        }
        entries.deinit(allocator);
    }

    var offset: usize = 12;

    for (0..header.entry_count) |_| {
        if (offset + 62 > data.len) return error.UnexpectedEnd;

        const entry_start = offset;

        const entry = IndexEntry{
            .ctime_sec = std.mem.readInt(u32, data[offset..][0..4], .big),
            .ctime_nsec = std.mem.readInt(u32, data[offset + 4 ..][0..4], .big),
            .mtime_sec = std.mem.readInt(u32, data[offset + 8 ..][0..4], .big),
            .mtime_nsec = std.mem.readInt(u32, data[offset + 12 ..][0..4], .big),
            .dev = std.mem.readInt(u32, data[offset + 16 ..][0..4], .big),
            .ino = std.mem.readInt(u32, data[offset + 20 ..][0..4], .big),
            .mode = std.mem.readInt(u32, data[offset + 24 ..][0..4], .big),
            .uid = std.mem.readInt(u32, data[offset + 28 ..][0..4], .big),
            .gid = std.mem.readInt(u32, data[offset + 32 ..][0..4], .big),
            .size = std.mem.readInt(u32, data[offset + 36 ..][0..4], .big),
            .sha1 = data[offset + 40 ..][0..20].*,
            .flags = std.mem.readInt(u16, data[offset + 60 ..][0..2], .big),
            .path = undefined, // Set below
        };

        offset += 62;

        // Extended flags for version 3+
        if (header.version >= 3 and (entry.flags & 0x4000) != 0) {
            offset += 2; // Skip extended flags
        }

        // Find path (NUL-terminated)
        const path_start = offset;
        while (offset < data.len and data[offset] != 0) {
            offset += 1;
        }

        if (offset >= data.len) return error.UnexpectedEnd;

        const path = try allocator.dupe(u8, data[path_start..offset]);

        // Skip NUL terminator
        offset += 1;

        // Version 2 and 3: pad to 8-byte boundary (from entry start)
        if (header.version < 4) {
            const entry_len = offset - entry_start;
            const pad_len = (8 - (entry_len % 8)) % 8;
            offset += pad_len;
        }

        var final_entry = entry;
        final_entry.path = path;
        try entries.append(allocator, final_entry);
    }

    return Index{
        .header = header,
        .entries = try entries.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Parse index file from path
pub fn parseFile(allocator: std.mem.Allocator, index_path: []const u8) !Index {
    const data = try std.fs.cwd().readFileAlloc(allocator, index_path, 50 * 1024 * 1024);
    defer allocator.free(data);
    return parse(allocator, data);
}

test "parse index header" {
    // Minimal valid index with 0 entries
    const data = "DIRC" ++ "\x00\x00\x00\x02" ++ "\x00\x00\x00\x00";
    const allocator = std.testing.allocator;
    var index = try parse(allocator, data);
    defer index.deinit();

    try std.testing.expectEqualStrings("DIRC", &index.header.signature);
    try std.testing.expectEqual(@as(u32, 2), index.header.version);
    try std.testing.expectEqual(@as(u32, 0), index.header.entry_count);
}

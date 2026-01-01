const std = @import("std");

/// A TOML value
pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    array: []const Value,
    table: Table,

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .array => |arr| {
                for (arr) |*item| {
                    var val = item.*;
                    val.deinit(allocator);
                }
                allocator.free(arr);
            },
            .table => |*t| t.deinit(),
            else => {},
        }
    }

    pub fn asString(self: Value) ?[]const u8 {
        return if (self == .string) self.string else null;
    }

    pub fn asBool(self: Value) ?bool {
        return if (self == .boolean) self.boolean else null;
    }

    pub fn asInt(self: Value) ?i64 {
        return if (self == .integer) self.integer else null;
    }

    pub fn asArray(self: Value) ?[]const Value {
        return if (self == .array) self.array else null;
    }
};

/// A TOML table (key-value pairs)
pub const Table = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(Value),

    pub fn init(allocator: std.mem.Allocator) Table {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Table) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var val = entry.value_ptr.*;
            val.deinit(self.allocator);
        }
        self.entries.deinit();
    }

    pub fn get(self: Table, key: []const u8) ?Value {
        return self.entries.get(key);
    }

    pub fn getSection(self: Table, section: []const u8) ?Table {
        if (self.entries.get(section)) |val| {
            if (val == .table) return val.table;
        }
        return null;
    }
};

/// Parse TOML content
pub fn parse(allocator: std.mem.Allocator, content: []const u8) !Table {
    var root = Table.init(allocator);
    errdefer root.deinit();

    var current_table: *Table = &root;
    var current_section: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip empty lines and comments
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Section header [section] or [section.subsection]
        if (trimmed[0] == '[') {
            if (std.mem.indexOfScalar(u8, trimmed, ']')) |end| {
                const section_name = trimmed[1..end];
                current_section = section_name;

                // Handle nested sections like [git_status]
                // Create or get the section table
                if (root.entries.get(section_name)) |existing| {
                    if (existing == .table) {
                        // Get pointer to existing table - need to modify through entries
                        if (root.entries.getPtr(section_name)) |ptr| {
                            current_table = &ptr.table;
                        }
                    }
                } else {
                    // Create new section table
                    const section_table = Table.init(allocator);
                    const section_key = try allocator.dupe(u8, section_name);
                    try root.entries.put(section_key, .{ .table = section_table });

                    // Get pointer to the newly created table
                    if (root.entries.getPtr(section_key)) |ptr| {
                        current_table = &ptr.table;
                    }
                }
            }
            continue;
        }

        // Key = value
        if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            const value_str = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

            const value = try parseValue(allocator, value_str);
            const key_dup = try allocator.dupe(u8, key);

            try current_table.entries.put(key_dup, value);
        }
    }

    return root;
}

fn parseValue(allocator: std.mem.Allocator, input: []const u8) std.mem.Allocator.Error!Value {
    if (input.len == 0) return .{ .string = try allocator.dupe(u8, "") };

    // Boolean
    if (std.mem.eql(u8, input, "true")) return .{ .boolean = true };
    if (std.mem.eql(u8, input, "false")) return .{ .boolean = false };

    // Quoted string (double quotes)
    if (input[0] == '"') {
        return .{ .string = try parseQuotedString(allocator, input, '"') };
    }

    // Quoted string (single quotes - literal, no escapes)
    if (input[0] == '\'') {
        return .{ .string = try parseQuotedString(allocator, input, '\'') };
    }

    // Array
    if (input[0] == '[') {
        return .{ .array = try parseArray(allocator, input) };
    }

    // Integer
    if (std.fmt.parseInt(i64, input, 10)) |n| {
        return .{ .integer = n };
    } else |_| {}

    // Float
    if (std.fmt.parseFloat(f64, input)) |f| {
        return .{ .float = f };
    } else |_| {}

    // Unquoted string (bare key value - treat as string)
    return .{ .string = try allocator.dupe(u8, input) };
}

fn parseQuotedString(allocator: std.mem.Allocator, input: []const u8, quote: u8) std.mem.Allocator.Error![]u8 {
    if (input.len < 2) return try allocator.dupe(u8, "");

    // Find closing quote
    var end: usize = 1;
    var escaped = false;

    while (end < input.len) {
        if (escaped) {
            escaped = false;
            end += 1;
            continue;
        }

        if (quote == '"' and input[end] == '\\') {
            escaped = true;
            end += 1;
            continue;
        }

        if (input[end] == quote) {
            break;
        }
        end += 1;
    }

    const content = input[1..end];

    // For single quotes, no escape processing
    if (quote == '\'') {
        return try allocator.dupe(u8, content);
    }

    // For double quotes, process escapes
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < content.len) {
        if (content[i] == '\\' and i + 1 < content.len) {
            const next = content[i + 1];
            switch (next) {
                'n' => try result.append(allocator, '\n'),
                't' => try result.append(allocator, '\t'),
                'r' => try result.append(allocator, '\r'),
                '\\' => try result.append(allocator, '\\'),
                '"' => try result.append(allocator, '"'),
                else => {
                    try result.append(allocator, '\\');
                    try result.append(allocator, next);
                },
            }
            i += 2;
        } else {
            try result.append(allocator, content[i]);
            i += 1;
        }
    }

    return try result.toOwnedSlice(allocator);
}

fn parseArray(allocator: std.mem.Allocator, input: []const u8) std.mem.Allocator.Error![]const Value {
    if (input.len < 2) return try allocator.alloc(Value, 0);

    // Find matching ]
    var depth: usize = 0;
    var end: usize = 0;

    for (input, 0..) |c, i| {
        if (c == '[') depth += 1;
        if (c == ']') {
            depth -= 1;
            if (depth == 0) {
                end = i;
                break;
            }
        }
    }

    const content = std.mem.trim(u8, input[1..end], " \t\n\r");
    if (content.len == 0) return try allocator.alloc(Value, 0);

    var items: std.ArrayList(Value) = .{};
    errdefer {
        for (items.items) |*item| {
            item.deinit(allocator);
        }
        items.deinit(allocator);
    }

    // Split by comma, respecting quotes
    var start: usize = 0;
    var in_quotes = false;
    var quote_char: u8 = 0;

    for (content, 0..) |c, i| {
        if (!in_quotes and (c == '"' or c == '\'')) {
            in_quotes = true;
            quote_char = c;
        } else if (in_quotes and c == quote_char) {
            in_quotes = false;
        } else if (!in_quotes and c == ',') {
            const item_str = std.mem.trim(u8, content[start..i], " \t\n\r");
            if (item_str.len > 0) {
                const val = try parseValue(allocator, item_str);
                try items.append(allocator, val);
            }
            start = i + 1;
        }
    }

    // Last item
    const last = std.mem.trim(u8, content[start..], " \t\n\r");
    if (last.len > 0) {
        const val = try parseValue(allocator, last);
        try items.append(allocator, val);
    }

    return try items.toOwnedSlice(allocator);
}

test "parse boolean" {
    const allocator = std.testing.allocator;

    var table = try parse(allocator, "flag = true\nother = false");
    defer table.deinit();

    try std.testing.expectEqual(true, table.get("flag").?.asBool().?);
    try std.testing.expectEqual(false, table.get("other").?.asBool().?);
}

test "parse integer" {
    const allocator = std.testing.allocator;

    var table = try parse(allocator, "num = 42");
    defer table.deinit();

    try std.testing.expectEqual(@as(i64, 42), table.get("num").?.asInt().?);
}

test "parse string" {
    const allocator = std.testing.allocator;

    var table = try parse(allocator,
        \\str = "hello world"
        \\sym = "→"
    );
    defer table.deinit();

    try std.testing.expectEqualStrings("hello world", table.get("str").?.asString().?);
    try std.testing.expectEqualStrings("→", table.get("sym").?.asString().?);
}

test "parse array" {
    const allocator = std.testing.allocator;

    var table = try parse(allocator,
        \\files = ["a.js", "b.ts", "c.py"]
    );
    defer table.deinit();

    const arr = table.get("files").?.asArray().?;
    try std.testing.expectEqual(@as(usize, 3), arr.len);
    try std.testing.expectEqualStrings("a.js", arr[0].asString().?);
    try std.testing.expectEqualStrings("b.ts", arr[1].asString().?);
    try std.testing.expectEqualStrings("c.py", arr[2].asString().?);
}

test "parse section" {
    const allocator = std.testing.allocator;

    var table = try parse(allocator,
        \\[git_branch]
        \\disabled = true
        \\symbol = " "
    );
    defer table.deinit();

    const section = table.getSection("git_branch").?;
    try std.testing.expectEqual(true, section.get("disabled").?.asBool().?);
    try std.testing.expectEqualStrings(" ", section.get("symbol").?.asString().?);
}

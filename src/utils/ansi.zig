const std = @import("std");

// ANSI escape codes for colors and styles
// Using %{ %} for zsh prompt escaping

pub const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,

    pub fn format(self: Style, writer: anytype) !void {
        const has_any = self.bold or self.italic or self.underline or self.fg != null or self.bg != null;
        if (!has_any) return;

        try writer.writeAll("%{\x1b[");

        var need_sep = false;

        if (self.bold) {
            try writer.writeAll("1");
            need_sep = true;
        }
        if (self.italic) {
            if (need_sep) try writer.writeAll(";");
            try writer.writeAll("3");
            need_sep = true;
        }
        if (self.underline) {
            if (need_sep) try writer.writeAll(";");
            try writer.writeAll("4");
            need_sep = true;
        }
        if (self.fg) |fg_color| {
            if (need_sep) try writer.writeAll(";");
            try fg_color.writeFg(writer);
            need_sep = true;
        }
        if (self.bg) |bg_color| {
            if (need_sep) try writer.writeAll(";");
            try bg_color.writeBg(writer);
        }

        try writer.writeAll("m%}");
    }
};

pub const Color = union(enum) {
    basic: BasicColor,
    extended: u8, // 256-color (0-255)

    pub const BasicColor = enum(u8) {
        black = 0,
        red = 1,
        green = 2,
        yellow = 3,
        blue = 4,
        magenta = 5,
        cyan = 6,
        white = 7,
        bright_black = 8,
        bright_red = 9,
        bright_green = 10,
        bright_yellow = 11,
        bright_blue = 12,
        bright_magenta = 13,
        bright_cyan = 14,
        bright_white = 15,
    };

    // Convenience constructors for basic colors
    pub const black = Color{ .basic = .black };
    pub const red = Color{ .basic = .red };
    pub const green = Color{ .basic = .green };
    pub const yellow = Color{ .basic = .yellow };
    pub const blue = Color{ .basic = .blue };
    pub const magenta = Color{ .basic = .magenta };
    pub const cyan = Color{ .basic = .cyan };
    pub const white = Color{ .basic = .white };
    pub const bright_black = Color{ .basic = .bright_black };
    pub const bright_red = Color{ .basic = .bright_red };
    pub const bright_green = Color{ .basic = .bright_green };
    pub const bright_yellow = Color{ .basic = .bright_yellow };
    pub const bright_blue = Color{ .basic = .bright_blue };
    pub const bright_magenta = Color{ .basic = .bright_magenta };
    pub const bright_cyan = Color{ .basic = .bright_cyan };
    pub const bright_white = Color{ .basic = .bright_white };

    // 256-color palette shortcuts
    pub const orange = Color{ .extended = 208 }; // True orange

    pub fn writeFg(self: Color, writer: anytype) !void {
        switch (self) {
            .basic => |b| {
                const val = @intFromEnum(b);
                if (val < 8) {
                    try writer.print("{d}", .{30 + val});
                } else {
                    try writer.print("{d}", .{90 + (val - 8)});
                }
            },
            .extended => |c| {
                try writer.print("38;5;{d}", .{c});
            },
        }
    }

    pub fn writeBg(self: Color, writer: anytype) !void {
        switch (self) {
            .basic => |b| {
                const val = @intFromEnum(b);
                if (val < 8) {
                    try writer.print("{d}", .{40 + val});
                } else {
                    try writer.print("{d}", .{100 + (val - 8)});
                }
            },
            .extended => |c| {
                try writer.print("48;5;{d}", .{c});
            },
        }
    }
};

// Pre-defined styles matching Starship defaults
pub const reset = "%{\x1b[0m%}";

pub fn colored(writer: anytype, text: []const u8, style: Style) !void {
    try style.format(writer);
    try writer.writeAll(text);
    try writer.writeAll(reset);
}

pub fn bold(writer: anytype, text: []const u8, color: Color) !void {
    try colored(writer, text, .{ .fg = color, .bold = true });
}

pub fn fg(writer: anytype, text: []const u8, color: Color) !void {
    try colored(writer, text, .{ .fg = color });
}

// Starship-style colors - each element has a distinctive color
pub const dir_color = Color.yellow; // Directory: yellow
pub const git_branch_color = Color.cyan; // Git: cyan/teal
pub const git_status_color = Color.red;
pub const node_color = Color.green; // Node.js: green
pub const package_color = Color.orange; // Package: true orange (256-color 208)
pub const rust_color = Color.red; // Rust: red
pub const java_color = Color.magenta; // Java: purple/magenta
pub const go_color = Color.cyan; // Go: cyan
pub const python_color = Color.yellow; // Python: yellow
pub const ruby_color = Color.red; // Ruby: red
pub const docker_color = Color.blue; // Docker: blue
pub const time_color = Color.yellow;
pub const username_color = Color.yellow; // Starship default
pub const hostname_color = Color.green;
pub const duration_color = Color.yellow;
pub const success_color = Color.green;
pub const error_color = Color.red;
pub const muted_color = Color.bright_black;

test "color codes" {
    // Test basic color output
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try Color.red.writeFg(writer);
    try std.testing.expectEqualStrings("31", fbs.getWritten());

    fbs.reset();
    try Color.bright_green.writeFg(writer);
    try std.testing.expectEqualStrings("92", fbs.getWritten());

    fbs.reset();
    try Color.orange.writeFg(writer);
    try std.testing.expectEqualStrings("38;5;208", fbs.getWritten());
}

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
        var codes: [10]u8 = undefined;
        var count: usize = 0;

        if (self.bold) {
            codes[count] = 1;
            count += 1;
        }
        if (self.italic) {
            codes[count] = 3;
            count += 1;
        }
        if (self.underline) {
            codes[count] = 4;
            count += 1;
        }
        if (self.fg) |fg| {
            codes[count] = fg.toFgCode();
            count += 1;
        }
        if (self.bg) |bg| {
            codes[count] = bg.toBgCode();
            count += 1;
        }

        if (count == 0) return;

        try writer.writeAll("%{\x1b[");
        for (codes[0..count], 0..) |code, i| {
            if (i > 0) try writer.writeAll(";");
            try writer.print("{d}", .{code});
        }
        try writer.writeAll("m%}");
    }
};

pub const Color = enum(u8) {
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

    pub fn toFgCode(self: Color) u8 {
        const val = @intFromEnum(self);
        if (val < 8) {
            return 30 + val;
        } else {
            return 90 + (val - 8);
        }
    }

    pub fn toBgCode(self: Color) u8 {
        const val = @intFromEnum(self);
        if (val < 8) {
            return 40 + val;
        } else {
            return 100 + (val - 8);
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

// Common Starship colors
pub const dir_color = Color.cyan;
pub const git_branch_color = Color.magenta;
pub const git_status_color = Color.red;
pub const node_color = Color.green;
pub const duration_color = Color.yellow;
pub const success_color = Color.green;
pub const error_color = Color.red;

test "color codes" {
    try std.testing.expectEqual(@as(u8, 31), Color.red.toFgCode());
    try std.testing.expectEqual(@as(u8, 92), Color.bright_green.toFgCode());
}

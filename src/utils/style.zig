const std = @import("std");
const ansi = @import("ansi.zig");

/// Parse a Starship-style style string into an ANSI style
/// Supports: "bold red", "fg:blue", "bg:green", "underline italic cyan"
pub fn parse(style_str: []const u8) ansi.Style {
    var style = ansi.Style{};

    var iter = std.mem.tokenizeAny(u8, style_str, " \t");
    while (iter.next()) |token| {
        // Check for fg: prefix
        if (std.mem.startsWith(u8, token, "fg:")) {
            if (parseColor(token[3..])) |color| {
                style.fg = color;
            }
            continue;
        }

        // Check for bg: prefix
        if (std.mem.startsWith(u8, token, "bg:")) {
            if (parseColor(token[3..])) |color| {
                style.bg = color;
            }
            continue;
        }

        // Check for style modifiers
        if (std.mem.eql(u8, token, "bold")) {
            style.bold = true;
            continue;
        }
        if (std.mem.eql(u8, token, "italic")) {
            style.italic = true;
            continue;
        }
        if (std.mem.eql(u8, token, "underline")) {
            style.underline = true;
            continue;
        }
        if (std.mem.eql(u8, token, "dimmed") or std.mem.eql(u8, token, "dim")) {
            // Dimmed isn't directly supported, treat as no-op for now
            continue;
        }

        // Otherwise treat as a color name (foreground)
        if (parseColor(token)) |color| {
            style.fg = color;
        }
    }

    return style;
}

fn parseColor(name: []const u8) ?ansi.Color {
    // Standard colors
    if (std.mem.eql(u8, name, "black")) return ansi.Color.black;
    if (std.mem.eql(u8, name, "red")) return ansi.Color.red;
    if (std.mem.eql(u8, name, "green")) return ansi.Color.green;
    if (std.mem.eql(u8, name, "yellow")) return ansi.Color.yellow;
    if (std.mem.eql(u8, name, "blue")) return ansi.Color.blue;
    if (std.mem.eql(u8, name, "magenta") or std.mem.eql(u8, name, "purple")) return ansi.Color.magenta;
    if (std.mem.eql(u8, name, "cyan")) return ansi.Color.cyan;
    if (std.mem.eql(u8, name, "white")) return ansi.Color.white;

    // Bright colors
    if (std.mem.eql(u8, name, "bright-black") or std.mem.eql(u8, name, "bright_black")) return ansi.Color.bright_black;
    if (std.mem.eql(u8, name, "bright-red") or std.mem.eql(u8, name, "bright_red")) return ansi.Color.bright_red;
    if (std.mem.eql(u8, name, "bright-green") or std.mem.eql(u8, name, "bright_green")) return ansi.Color.bright_green;
    if (std.mem.eql(u8, name, "bright-yellow") or std.mem.eql(u8, name, "bright_yellow")) return ansi.Color.bright_yellow;
    if (std.mem.eql(u8, name, "bright-blue") or std.mem.eql(u8, name, "bright_blue")) return ansi.Color.bright_blue;
    if (std.mem.eql(u8, name, "bright-magenta") or std.mem.eql(u8, name, "bright_magenta") or
        std.mem.eql(u8, name, "bright-purple") or std.mem.eql(u8, name, "bright_purple")) return ansi.Color.bright_magenta;
    if (std.mem.eql(u8, name, "bright-cyan") or std.mem.eql(u8, name, "bright_cyan")) return ansi.Color.bright_cyan;
    if (std.mem.eql(u8, name, "bright-white") or std.mem.eql(u8, name, "bright_white")) return ansi.Color.bright_white;

    // 256-color support (e.g., "208" for orange)
    if (std.fmt.parseInt(u8, name, 10)) |color_num| {
        return ansi.Color{ .extended = color_num };
    } else |_| {}

    // Hex color support (#RGB or #RRGGBB) - use 256-color approximation
    if (name.len > 0 and name[0] == '#') {
        return hexToColor(name[1..]);
    }

    return null;
}

fn hexToColor(hex: []const u8) ?ansi.Color {
    // Parse hex color and convert to 256-color palette
    var r: u8 = 0;
    var g: u8 = 0;
    var b: u8 = 0;

    if (hex.len == 3) {
        // #RGB format
        r = (parseHexDigit(hex[0]) orelse return null) * 17;
        g = (parseHexDigit(hex[1]) orelse return null) * 17;
        b = (parseHexDigit(hex[2]) orelse return null) * 17;
    } else if (hex.len == 6) {
        // #RRGGBB format
        r = (parseHexByte(hex[0..2]) orelse return null);
        g = (parseHexByte(hex[2..4]) orelse return null);
        b = (parseHexByte(hex[4..6]) orelse return null);
    } else {
        return null;
    }

    // Convert RGB to 256-color palette (216 color cube + 24 grayscale)
    // Color cube: 16 + 36*r + 6*g + b where r,g,b are 0-5
    const r6 = @as(u8, @intCast(@min(5, @as(u16, r) * 6 / 256)));
    const g6 = @as(u8, @intCast(@min(5, @as(u16, g) * 6 / 256)));
    const b6 = @as(u8, @intCast(@min(5, @as(u16, b) * 6 / 256)));

    const color_index = 16 + 36 * r6 + 6 * g6 + b6;
    return ansi.Color{ .extended = color_index };
}

fn parseHexDigit(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

fn parseHexByte(hex: []const u8) ?u8 {
    if (hex.len != 2) return null;
    const high = parseHexDigit(hex[0]) orelse return null;
    const low = parseHexDigit(hex[1]) orelse return null;
    return high * 16 + low;
}

test "parse bold red" {
    const style = parse("bold red");
    try std.testing.expect(style.bold);
    try std.testing.expectEqual(ansi.Color.red, style.fg.?);
}

test "parse fg:blue" {
    const style = parse("fg:blue");
    try std.testing.expectEqual(ansi.Color.blue, style.fg.?);
}

test "parse bg:green" {
    const style = parse("bg:green");
    try std.testing.expectEqual(ansi.Color.green, style.bg.?);
}

test "parse complex style" {
    const style = parse("bold underline fg:cyan bg:black");
    try std.testing.expect(style.bold);
    try std.testing.expect(style.underline);
    try std.testing.expectEqual(ansi.Color.cyan, style.fg.?);
    try std.testing.expectEqual(ansi.Color.black, style.bg.?);
}

test "parse purple" {
    const style = parse("purple");
    try std.testing.expectEqual(ansi.Color.magenta, style.fg.?);
}

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
    if (std.mem.eql(u8, name, "black")) return .black;
    if (std.mem.eql(u8, name, "red")) return .red;
    if (std.mem.eql(u8, name, "green")) return .green;
    if (std.mem.eql(u8, name, "yellow")) return .yellow;
    if (std.mem.eql(u8, name, "blue")) return .blue;
    if (std.mem.eql(u8, name, "magenta") or std.mem.eql(u8, name, "purple")) return .magenta;
    if (std.mem.eql(u8, name, "cyan")) return .cyan;
    if (std.mem.eql(u8, name, "white")) return .white;

    // Bright colors
    if (std.mem.eql(u8, name, "bright-black") or std.mem.eql(u8, name, "bright_black")) return .bright_black;
    if (std.mem.eql(u8, name, "bright-red") or std.mem.eql(u8, name, "bright_red")) return .bright_red;
    if (std.mem.eql(u8, name, "bright-green") or std.mem.eql(u8, name, "bright_green")) return .bright_green;
    if (std.mem.eql(u8, name, "bright-yellow") or std.mem.eql(u8, name, "bright_yellow")) return .bright_yellow;
    if (std.mem.eql(u8, name, "bright-blue") or std.mem.eql(u8, name, "bright_blue")) return .bright_blue;
    if (std.mem.eql(u8, name, "bright-magenta") or std.mem.eql(u8, name, "bright_magenta") or
        std.mem.eql(u8, name, "bright-purple") or std.mem.eql(u8, name, "bright_purple")) return .bright_magenta;
    if (std.mem.eql(u8, name, "bright-cyan") or std.mem.eql(u8, name, "bright_cyan")) return .bright_cyan;
    if (std.mem.eql(u8, name, "bright-white") or std.mem.eql(u8, name, "bright_white")) return .bright_white;

    // Hex color support (#RGB or #RRGGBB) - map to nearest basic color
    if (name.len > 0 and name[0] == '#') {
        return hexToNearestColor(name[1..]);
    }

    return null;
}

fn hexToNearestColor(hex: []const u8) ?ansi.Color {
    // Parse hex color and map to nearest 16 colors
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

    // Simple nearest-color mapping
    const bright = (r > 127 or g > 127 or b > 127);
    const max_channel = @max(r, @max(g, b));

    // Determine base color
    if (max_channel < 50) {
        return if (bright) .bright_black else .black;
    }

    // Find dominant color(s)
    const r_dom = r > 100;
    const g_dom = g > 100;
    const b_dom = b > 100;

    if (r_dom and g_dom and b_dom) {
        return if (bright) .bright_white else .white;
    } else if (r_dom and g_dom) {
        return if (bright) .bright_yellow else .yellow;
    } else if (r_dom and b_dom) {
        return if (bright) .bright_magenta else .magenta;
    } else if (g_dom and b_dom) {
        return if (bright) .bright_cyan else .cyan;
    } else if (r_dom) {
        return if (bright) .bright_red else .red;
    } else if (g_dom) {
        return if (bright) .bright_green else .green;
    } else if (b_dom) {
        return if (bright) .bright_blue else .blue;
    }

    return .white;
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

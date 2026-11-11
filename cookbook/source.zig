const std = @import("std");

const limit = 256 * 1024;

pub fn load(a: std.mem.Allocator, io: std.Io, directory: []const u8, key: []const u8) ![]u8 {
    const path = try std.fmt.allocPrint(a, "{s}/{s}.zig", .{ directory, key });
    defer a.free(path);
    return read(a, io, path) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => try std.fmt.allocPrint(a, "Unable to read source file:\n{s}\n\n{s}", .{ path, @errorName(err) }),
    };
}

fn read(a: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(limit));
    errdefer a.free(bytes);
    if (!std.unicode.utf8ValidateSlice(bytes) or std.mem.indexOfScalar(u8, bytes, 0) != null)
        return error.InvalidSourceText;
    return bytes;
}

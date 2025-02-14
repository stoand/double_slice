const std = @import("std");
const testing = std.testing;

/// A double slice is a slice within a slice
/// its purpose is to allow for static allocation
/// at startup
pub fn DoubleSlice(comptime T: type, inner_max_used: u32) type {
    return struct {
        buffer: []align(1) T,
        used: u32 = 0,

        pub const max_used = inner_max_used;
        pub const size = @sizeOf(T) * inner_max_used;

        pub const Range = struct {
            start: u32,
            end: u32,
        };

        pub const RangedSlice = struct {
            slice: []T,
            range: Range,
        };

        pub const empty_range: Range = .{ .start = 0, .end = 0 };

        pub const CreateCloneRange = struct {
            new_item: *T,
            new_slice: []T,
            range: Range,
        };

        pub fn alloc(allocator: std.mem.Allocator) !@This() {
            return .{
                .buffer = try allocator.alloc(T, max_used),
                .used = 0,
            };
        }

        pub fn allocDef(allocator: std.mem.Allocator, default: T) !@This() {
            const buffer = try allocator.alloc(T, max_used);
            @memset(buffer, default);
            return .{
                .buffer = buffer,
                .used = 0,
            };
        }

        pub fn copyFromOther(self: *@This(), other: @This()) void {
            self.used = other.used;
            for (self.slicedBuffer(), other.slicedBuffer()) |*this, inner_other| {
                this.* = inner_other;
            }
        }

        pub fn slicedRange(self: *@This(), range: Range) []T {
            return self.buffer[range.start..range.end];
        }

        pub fn consumeRangedSlice(self: *@This(), count: u32) !RangedSlice {
            if (self.used + count >= max_used) {
                std.debug.print("DoubleSlice of '{s}' is over its memory limit of {} items\n", .{ @typeName(T), max_used });
                return error.DoubleSliceOutOfMemory;
            } else {
                const range = .{ .start = self.used, .end = self.used + count };
                const slice = self.buffer[range.start..range.end];
                self.used += count;
                return .{ .slice = slice, .range = range };
            }
        }

        // pub fn createCloneRange(self: *@This(), range: Range) !CreateCloneRange {
        //     const existing_slice = self.slicedRange(range);
        //     const existing_len: u32 = @truncate(existing_slice.len);
        //     const cloned_slice = try self.consumeRangedSlice(existing_len + 1);
        //     for (existing_slice, 0..) |existing_item, existing_slice_index| {
        //         cloned_slice.slice[existing_slice_index] = existing_item;
        //     }
        //     return .{
        //         .new_item = @constCast(&cloned_slice.slice[cloned_slice.slice.len - 1]),
        //         .new_slice = cloned_slice.slice,
        //         .range = cloned_slice.range,
        //     };
        // }

        pub fn slicedBuffer(self: @This()) []T {
            return self.buffer[0..self.used];
        }

        pub fn reset(self: *@This()) void {
            self.used = 0;
        }

        pub fn consumeMultiple(self: *@This(), count: u32) ![]T {
            return (try self.consumeRangedSlice(count)).slice;
        }

        pub fn appendDoubleSlice(self: *@This(), double_slice: T) !void {
            var new_item = try self.create();
            @memcpy(new_item.buffer, double_slice.buffer);
            new_item.used = double_slice.used;
        }

        pub fn append(self: *@This(), item: T) !void {
            if (self.used == max_used) {
                std.debug.print("DoubleSlice of '{s}' is over its memory limit of {} items\n", .{ @typeName(T), max_used });
                return error.DoubleSliceOutOfMemory;
            } else {
                self.buffer[self.used] = item;
                self.used += 1;
            }
        }

        pub fn create(self: *@This()) !*T {
            if (self.used == max_used) {
                std.debug.print("DoubleSlice of '{s}' is over its memory limit of {} items\n", .{ @typeName(T), max_used });
                return error.DoubleSliceOutOfMemory;
            } else {
                const current_used = self.used;
                self.used += 1;
                return @constCast(&self.buffer[current_used]);
            }
        }

        pub fn deleteIndex(self: *@This(), item_index: u32) bool {
            if (item_index < self.used) {
                for (item_index..self.used) |index| {
                    self.buffer[index] = self.buffer[index + 1];
                }
                self.used -= 1;

                return true;
            } else {
                return false;
            }
        }

        pub fn deleteValue(self: *@This(), value: T) u32 {
            var deletions: u32 = 0;
            for (0..self.used) |index| {
                const inner_value = self.buffer[index];
                if (std.meta.eql(value, inner_value)) {
                    if (self.deleteIndex(@intCast(index))) {
                        deletions += 1;
                    }
                }
            }

            return deletions;
        }

        pub const as_bytes_size = @sizeOf(u32) + size;

        pub fn toBytes(self: @This()) [as_bytes_size]u8 {
            var result: [as_bytes_size]u8 = undefined;
            const buffer_bytes = std.mem.sliceAsBytes(self.buffer[0..]);
            @memcpy(result[@sizeOf(u32)..], buffer_bytes);
            @memcpy(result[0..@sizeOf(u32)], std.mem.asBytes(&self.used));
            return result;
        }

        pub fn fromBytes(buffer: *[as_bytes_size]u8) @This() {
            var double_slice: @This() = undefined;
            double_slice.used = std.mem.bytesAsValue(u32, buffer[0..@sizeOf(u32)]).*;
            double_slice.buffer = @constCast(std.mem.bytesAsSlice(T, buffer[@sizeOf(u32)..]));

            return double_slice;
        }

        pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("DoubleSlice (used: {}, max: {}):\n", .{ self.used, max_used });
            for (self.slicedBuffer(), 0..) |item, item_index| {
                try writer.print("{}) - {}", .{ item_index, item });
            }
            try writer.print("\n", .{});
        }
    };
}

test "To and From Bytes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    const InitSlice = DoubleSlice(f64, 10);

    var double_slice = try InitSlice.alloc(alloc);
    try double_slice.append(33.0);
    try double_slice.append(44.0);

    const result = InitSlice.fromBytes(@constCast(&double_slice.toBytes()));

    try testing.expectEqual(double_slice.used, result.used);
    try testing.expectEqual(33.0, double_slice.buffer[0]);
    try testing.expectEqual(44.0, double_slice.buffer[1]);
}

test "Deletion" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    // deleting the first item

    {
        var double_slice = try DoubleSlice(f64, 200).alloc(alloc);
        try double_slice.append(0.0);
        try double_slice.append(1.0);
        try double_slice.append(2.0);

        _ = double_slice.deleteIndex(0);

        try testing.expectEqual(1.0, double_slice.buffer[0]);
        try testing.expectEqual(2.0, double_slice.buffer[1]);
        try testing.expectEqual(2, double_slice.used);
    }

    // deleting the last item

    {
        var double_slice = try DoubleSlice(f64, 200).alloc(alloc);
        try double_slice.append(0.0);
        try double_slice.append(1.0);
        try double_slice.append(2.0);

        _ = double_slice.deleteIndex(2);

        try testing.expectEqual(0.0, double_slice.buffer[0]);
        try testing.expectEqual(1.0, double_slice.buffer[1]);
        try testing.expectEqual(2, double_slice.used);
    }

    // does nothing if deletion index is outside of used items

    {
        var double_slice = try DoubleSlice(f64, 200).alloc(alloc);
        try double_slice.append(0.0);
        try double_slice.append(1.0);
        try double_slice.append(2.0);

        _ = double_slice.deleteIndex(3);

        try testing.expectEqual(3, double_slice.used);
    }

    // deleting a value

    {
        var double_slice = try DoubleSlice(f64, 200).alloc(alloc);
        try double_slice.append(0.0);
        try double_slice.append(1.0);
        try double_slice.append(2.0);

        const delete_count = double_slice.deleteValue(0.0);

        try testing.expectEqual(1.0, double_slice.buffer[0]);
        try testing.expectEqual(2.0, double_slice.buffer[1]);
        try testing.expectEqual(2, double_slice.used);
        try testing.expectEqual(1, delete_count);
    }
}

const timeStamp = std.time.milliTimestamp;

test "bench" {

    // std.ArrayList (initCapacity)

    {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        const alloc = arena.allocator();
        defer arena.deinit();

        var list = try std.ArrayList(usize).initCapacity(alloc, 8_000_000);
        // var list = std.ArrayList(usize).init(alloc);
        defer list.clearAndFree();

        const start = timeStamp();

        for (0..8_000_000) |i| {
            try list.append(i + 1);
        }

        // try list.resize(0);

        // for (0..8_000_000) |i| {
        //     try list.append(i + 2);
        // }

        // try list.resize(0);

        // for (0..8_000_000) |i| {
        //     try list.append(i + 3);
        // }

        std.debug.print("\n8 Million items appended to std.ArrayList (initCapacity):\n{}ms\n", .{timeStamp() - start});
    }

    // DoubleSlice

    {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        const alloc = arena.allocator();
        defer arena.deinit();

        var double_slice = try DoubleSlice(usize, 8_000_000).alloc(alloc);

        const start = timeStamp();

        for (0..8_000_000) |i| {
            try double_slice.append(i + 1);
        }

        // double_slice.reset();

        // for (0..8_000_000) |i| {
        //     try double_slice.append(i + 2);
        // }

        // double_slice.reset();

        // for (0..8_000_000) |i| {
        //     try double_slice.append(i + 3);
        // }

        std.debug.print("\n8 Million items appended to std.ArrayList:\n{}ms\n", .{timeStamp() - start});
    }
}

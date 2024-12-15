const std = @import("std");
const testing = std.testing;

const csv = @This();

const CsvError = error{
    MalformedCsv,
};

pub fn CsvRowIterator(comptime T: type) type {
    return struct {
        buffer: []const T,
        index: ?usize,
        delimiter: T,

        const Self = @This();

        pub fn next(self: *Self) CsvError!?[]const T {
            var start = self.index orelse return null;
            const end = if (self.buffer[start] == '"') outer_blk: {
                start += 1;
                const end = if (std.mem.indexOfScalarPos(T, self.buffer, start, '"')) |delim_start| blk: {
                    self.index = delim_start + 2;
                    break :blk delim_start;
                } else {
                    self.index = null;
                    return CsvError.MalformedCsv;
                };
                if (self.index.? + 2 >= self.buffer.len) {
                    self.index = null;
                }
                if (self.index != null and self.buffer[self.index.? - 1] != ',') {
                    self.index = null;
                    return CsvError.MalformedCsv;
                }
                break :outer_blk end;
            } else outer_blk: {
                const end = if (std.mem.indexOfScalarPos(T, self.buffer, start, self.delimiter)) |delim_start| {
                    self.index = delim_start + 1;
                    break :outer_blk delim_start;
                } else blk: {
                    self.index = null;
                    break :blk self.buffer.len;
                };
                break :outer_blk end;
            };
            return self.buffer[start..end];
        }

        pub fn peek(self: *Self) ?[]const T {
            var start = self.index orelse return null;
            const end = if (self.buffer[start] == '"') blk: {
                start += 1;
                const end = if (std.mem.indexOfScalarPos(T, self.buffer, start, '"')) |delim_start| delim_start else return CsvError.MalformedCsv;
                break :blk end;
            } else blk: {
                break :blk if (std.mem.indexOfScalarPos(T, self.buffer, start, self.delim)) |delim_start| delim_start else self.buffer.len;
            };
            return self.buffer[start..end];
        }

        pub fn rest(self: Self) []const T {
            const end = self.buffer.len;
            const start = self.index orelse end;
            return self.buffer[start..end];
        }

        pub fn reset(self: *Self) void {
            self.index = 0;
        }
    };
}

pub fn splitCsvRow(comptime T: type, buffer: []const T, delimiter: T) CsvRowIterator(T) {
    return .{
        .index = 0,
        .buffer = buffer,
        .delimiter = delimiter,
    };
}

pub fn countScalar(comptime T: type, slice: []const T, start_index: usize, scalar: T) usize {
    var count: usize = 0;
    var i: usize = start_index;

    if (std.simd.suggestVectorLength(T)) |block_len| {
        const Block = @Vector(block_len, T);
        if (i + 2 * block_len < slice.len) {
            while (true) {
                inline for (0..2) |_| {
                    const block: Block = slice[i..][0..block_len].*;
                    const found = std.simd.countElementsWithValue(block, scalar);
                    std.debug.print("Found: {d}\n", .{found});
                    count += found;
                    i += block_len;
                }
                if (i + 2 * block_len >= slice.len) break;
            }
        }

        inline for (0..2) |j| {
            const block_x_len = block_len / (1 << j);
            comptime if (block_x_len < 4) break;
            const BlockX = @Vector(block_x_len, T);
            if (i + block_x_len < slice.len) {
                const block: BlockX = slice[i..][0..block_x_len].*;
                const found = std.simd.countElementsWithValue(block, scalar);
                std.debug.print("Found: {d}\n", .{found});
                count += found;
            }
            i += block_x_len;
        }
        return count;
    }

    for (slice[i..]) |c| {
        if (c == scalar) {
            count += 1;
        }
    }

    return count;
}

test "split-row-test-basic" {
    const row = "testval,testval,testval";
    var iter = splitCsvRow(u8, row, ',');
    while (try iter.next()) |val| {
        try testing.expect(std.mem.eql(u8, val, "testval"));
    }
}

test "split-row-test-quotes" {
    const row = "\"test,val\",\"test,val\",\"test,val\"";
    var iter = splitCsvRow(u8, row, ',');
    while (try iter.next()) |val| {
        try testing.expect(std.mem.eql(u8, val, "test,val"));
    }
}

test "split-row-test-error1" {
    const row = "\"test,val";
    var iter = splitCsvRow(u8, row, ',');
    const val = iter.next();
    try testing.expect(val == CsvError.MalformedCsv);
}

test "split-row-test-error2" {
    const row = "\"test,val\"\"test,val\"";
    var iter = splitCsvRow(u8, row, ',');
    const val = iter.next();
    try testing.expect(val == CsvError.MalformedCsv);
}

//test "count-Scalar" {
//  const row = "test,val,test,val";
//   const count = countScalar(u8, row, 0, ',');
//  try testing.expectEqual(3, count);
//}

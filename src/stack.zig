pub const Cell = union(enum) {
    len: packed struct {
        length: u8,
        _unused: u56 = 0,
    },
    utf8: u64,
    integer: i64,
    number: f64,
    addr: packed struct {
        address: u32,
        _unused: u32 = 0,
    },
    slice: packed struct {
        address: u32,
        length: u32,
    },
    machine: *const fn (*Stack) Error!void,
};

pub const Error = error{ BadArguments, StackOverflow, MathOverflow, DivisionByZero };

pub const Stack = struct {
    bytes: [*]align(@alignOf(Cell)) u8 = undefined,
    here: usize = 0,
    stack_ptr: usize = 0,
    capacity: usize = 0,

    const pad_len = 128 * 1024;

    pub const Elem = struct {
        const info = @typeInfo(Cell).Union;
        pub const Bare = @Type(.{ .Union = .{
            .layout = .@"packed",
            .tag_type = null,
            .fields = info.fields,
            .decls = &.{},
        } });
        pub const Tag = info.tag_type.?;
        tags: Tag,
        data: Bare,

        pub fn fromCell(outer: Cell) @This() {
            const tag = meta.activeTag(outer);
            return .{
                .tags = tag,
                .data = switch (tag) {
                    inline else => |t| @unionInit(Bare, @tagName(t), @field(outer, @tagName(t))),
                },
            };
        }
        pub fn toCell(tag: Tag, bare: Bare) Cell {
            return switch (tag) {
                inline else => |t| @unionInit(Cell, @tagName(t), @field(bare, @tagName(t))),
            };
        }

        comptime {
            assert(@sizeOf(Bare) == @sizeOf(u64));
        }
    };

    pub const Field = meta.FieldEnum(Elem);
    const fields = meta.fields(Elem);
    /// `sizes.bytes` is an array of @sizeOf each T field. Sorted by alignment, descending.
    /// `sizes.fields` is an array mapping from `sizes.bytes` array index to field index.
    const sizes = blk: {
        const Data = struct {
            size: usize,
            size_index: usize,
            alignment: usize,
        };
        var data: [fields.len]Data = undefined;
        for (fields, 0..) |field_info, i| {
            data[i] = .{
                .size = @sizeOf(field_info.type),
                .size_index = i,
                .alignment = if (@sizeOf(field_info.type) == 0) 1 else field_info.alignment,
            };
        }
        const Sort = struct {
            fn lessThan(context: void, lhs: Data, rhs: Data) bool {
                _ = context;
                return lhs.alignment > rhs.alignment;
            }
        };
        mem.sort(Data, &data, {}, Sort.lessThan);
        var sizes_bytes: [fields.len]usize = undefined;
        var field_indexes: [fields.len]usize = undefined;
        for (data, 0..) |elem, i| {
            sizes_bytes[i] = elem.size;
            field_indexes[i] = elem.size_index;
        }
        break :blk .{
            .bytes = sizes_bytes,
            .fields = field_indexes,
        };
    };

    pub const Slice = struct {
        ptrs: [fields.len][*]u8,
        here: usize,
        stack_ptr: usize,
        capacity: usize,

        pub fn items(self: Slice, comptime field: Field) []FieldType(field) {
            const F = FieldType(field);
            if (self.capacity == 0) return &.{};
            const byte_ptr = self.ptrs[@intFromEnum(field)];
            const casted_ptr: [*]F = @ptrCast(@alignCast(byte_ptr));
            return casted_ptr[0..self.capacity];
        }

        pub fn get(self: Slice, index: usize) Cell {
            var res: Elem = undefined;
            inline for (fields, 0..) |field_info, i| {
                @field(res, field_info.name) = self.items(@enumFromInt(i))[index];
            }
            return Elem.toCell(res.tags, res.data);
        }

        pub fn set(self: Slice, index: usize, elem: Cell) void {
            const e = Elem.fromCell(elem);
            inline for (fields, 0..) |field_info, i| {
                self.items(@enumFromInt(i))[index] = @field(e, field_info.name);
            }
        }

        pub fn toStack(self: Slice) Stack {
            if (self.ptrs.len == 0 or self.capacity == 0) return .{};
            const unaligned_ptr = self.ptrs[sizes.fields[0]];
            const aligned_ptr: [*]align(@alignOf(Elem)) u8 = @alignCast(unaligned_ptr);
            return .{
                .bytes = aligned_ptr,
                .here = self.here,
                .stack_ptr = self.stack_ptr,
                .capacity = self.capacity,
            };
        }

        /// This function is used in the debugger pretty formatters in tools/ to fetch the
        /// child field order and entry type to facilitate fancy debug printing for this type.
        fn dbHelper(self: *Slice, child: *Elem, field: *Field, entry: *Entry) void {
            _ = self;
            _ = child;
            _ = field;
            _ = entry;
        }
    };

    fn FieldType(comptime field: Field) type {
        return meta.fieldInfo(Elem, field).type;
    }

    /// buffer memory must be valid for the lifetime of this Stack,
    /// although Stack will not free the memory
    pub fn init(buffer: []align(@alignOf(Elem)) u8) Stack {
        return .{
            .bytes = buffer.ptr,
            .stack_ptr = @divFloor(buffer.len, @sizeOf(Elem)),
            .capacity = @divFloor(buffer.len, @sizeOf(Elem)),
        };
    }

    /// Compute pointers to the start of each field of the array.
    /// If you need to access multiple fields, calling this may
    /// be more efficient than calling `items()` multiple times.
    pub fn slice(self: Stack) Slice {
        var result: Slice = .{
            .ptrs = undefined,
            .here = self.here,
            .stack_ptr = self.stack_ptr,
            .capacity = self.capacity,
        };
        var ptr: [*]u8 = self.bytes;
        for (sizes.bytes, sizes.fields) |field_size, i| {
            result.ptrs[i] = ptr;
            ptr += field_size * self.capacity;
        }
        return result;
    }

    /// Get the slice of values for a specified field.
    /// If you need multiple fields, consider calling slice()
    /// instead.
    pub fn items(self: Stack, comptime field: Field) []FieldType(field) {
        return self.slice().items(field);
    }

    /// Overwrite one array element with new data.
    pub fn set(self: *Stack, index: usize, elem: Cell) void {
        var slices = self.slice();
        slices.set(index, elem);
    }

    /// Obtain all the data for one array element.
    pub fn get(self: Stack, index: usize) Cell {
        return self.slice().get(index);
    }

    const Entry = entry: {
        var entry_fields: [fields.len]std.builtin.Type.StructField = undefined;
        for (&entry_fields, sizes.fields) |*entry_field, i| entry_field.* = .{
            .name = fields[i].name ++ "_ptr",
            .type = *fields[i].type,
            .default_value = null,
            .is_comptime = fields[i].is_comptime,
            .alignment = fields[i].alignment,
        };
        break :entry @Type(.{ .Struct = .{
            .layout = .@"extern",
            .fields = &entry_fields,
            .decls = &.{},
            .is_tuple = false,
        } });
    };
    /// This function is used in the debugger pretty formatters in tools/ to fetch the
    /// child field order and entry type to facilitate fancy debug printing for this type.
    fn dbHelper(self: *Stack, child: *Elem, field: *Field, entry: *Entry) void {
        _ = self;
        _ = child;
        _ = field;
        _ = entry;
    }

    comptime {
        if (!builtin.strip_debug_info) {
            _ = &dbHelper;
            _ = &Slice.dbHelper;
        }
    }
};

const std = @import("std");
const assert = std.debug.assert;
const meta = std.meta;
const mem = std.mem;
const builtin = @import("builtin");

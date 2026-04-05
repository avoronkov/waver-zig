const Note = @import("./note.zig");
const EofError = @import("./wave.zig").EofError;

const Self = @This();

ptr: *const anyopaque,
value_of_impl: *const fn (ptr: *const anyopaque, n: i32, t: f64, note: Note) EofError!f64,

pub fn init(ptr: anytype) Self {
    const T = @TypeOf(ptr);
    const ptr_info = @typeInfo(T);

    const gen = struct {
	pub fn value_of_impl(pointer: *const anyopaque, n: i32, t: f64, note: Note) EofError!f64 {
	    const self: T = @ptrCast(@alignCast(pointer));
	    return ptr_info.pointer.child.value_of(self, n, t, note);
	}   
    };  

    return .{
	.ptr = ptr,
	.value_of_impl = gen.value_of_impl,
    };  
}

pub fn value_of(self: Self, n: i32, t: f64, note: Note) EofError!f64 {
    return self.value_of_impl(self.ptr, n, t, note); 
}   

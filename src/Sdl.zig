const std = @import("std");
const c = @import("c.zig");
const Chip8 = @import("Chip8.zig");

window: *c.SDL_Window,
renderer: *c.SDL_Renderer,
texture: *c.SDL_Texture,

fn printSdlError() void {
    std.log.err("{s}", .{c.SDL_GetError()});
}

pub fn init(window_title: [:0]const u8, window_width: u32, window_height: u32) !@This() {
    errdefer printSdlError();

    if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO) < 0)
        return error.SdlInitFailed;
    errdefer c.SDL_Quit();

    const window = c.SDL_CreateWindow(
        window_title,
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        @intCast(window_width),
        @intCast(window_height),
        0,
    ) orelse return error.SdlWindowCreationFailed;
    errdefer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED) orelse
        return error.SdlRendererCreationFailed;
    errdefer c.SDL_DestroyRenderer(renderer);

    if (c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, c.SDL_ALPHA_OPAQUE) < 0)
        return error.SdlRenderClearFailed;

    const texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_STREAMING,
        Chip8.screen_width,
        Chip8.screen_height,
    ) orelse return error.SDLTextureCreationFailed;
    errdefer c.SDL_DestroyTexture(texture);

    return .{
        .window = window,
        .renderer = renderer,
        .texture = texture,
    };
}

pub fn presentFrame(self: *@This(), frame: *const Chip8.Frame) !void {
    errdefer printSdlError();

    if (c.SDL_RenderClear(self.renderer) < 0)
        return error.SdlRenderClearFailed;

    {
        var pixel_ptr: ?*anyopaque = undefined;
        var pitch: c_int = undefined;
        if (c.SDL_LockTexture(self.texture, null, &pixel_ptr, &pitch) < 0)
            return error.SdlTextureLockFailed;
        defer c.SDL_UnlockTexture(self.texture);

        std.debug.assert(pitch == Chip8.Frame.pitch);

        const ptr: [*]u8 = @ptrCast(pixel_ptr);
        const pixels = ptr[0..Chip8.Frame.size];
        @memcpy(pixels, &frame.pixels);
    }

    if (c.SDL_RenderCopy(self.renderer, self.texture, null, null) < 0)
        return error.SdlRenderCopyFailed;

    c.SDL_RenderPresent(self.renderer);
}

pub fn deinit(self: *@This()) void {
    c.SDL_DestroyTexture(self.texture);
    c.SDL_DestroyRenderer(self.renderer);
    c.SDL_DestroyWindow(self.window);
    c.SDL_Quit();
}

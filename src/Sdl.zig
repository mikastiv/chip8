const std = @import("std");
const c = @import("c.zig");
const Chip8 = @import("Chip8.zig");
const Frame = @import("Frame.zig");

window: *c.SDL_Window,
renderer: *c.SDL_Renderer,
texture: *c.SDL_Texture,
audio_format: c.SDL_AudioSpec,
audio_device: c.SDL_AudioDeviceID,

fn printSdlError() void {
    std.log.err("{s}", .{c.SDL_GetError()});
}

pub fn init(window_title: [:0]const u8, window_width: u32, window_height: u32, sample_rate: u32, audio_ptr: *anyopaque) !@This() {
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
    ) orelse return error.SdlTextureCreationFailed;
    errdefer c.SDL_DestroyTexture(texture);

    const wanted_audio_spec: c.SDL_AudioSpec = .{
        .freq = @intCast(sample_rate),
        .format = c.AUDIO_F32,
        .channels = 1,
        .samples = 2048,
        .callback = Chip8.audioCallback,
        .userdata = audio_ptr,
        .silence = 0,
        .size = 0,
        .padding = 0,
    };
    var obtained_audio_spec: c.SDL_AudioSpec = undefined;
    const audio_device = c.SDL_OpenAudioDevice(
        null,
        0,
        &wanted_audio_spec,
        &obtained_audio_spec,
        c.SDL_AUDIO_ALLOW_FORMAT_CHANGE,
    );
    if (audio_device == 0) return error.SdlAudioDeviceCreationFailed;

    return .{
        .window = window,
        .renderer = renderer,
        .texture = texture,
        .audio_format = obtained_audio_spec,
        .audio_device = audio_device,
    };
}

pub fn presentFrame(self: *@This(), frame: *const Frame) !void {
    errdefer printSdlError();

    if (c.SDL_RenderClear(self.renderer) < 0)
        return error.SdlRenderClearFailed;

    {
        var pixel_ptr: ?*anyopaque = undefined;
        var pitch: c_int = undefined;
        if (c.SDL_LockTexture(self.texture, null, &pixel_ptr, &pitch) < 0)
            return error.SdlTextureLockFailed;
        defer c.SDL_UnlockTexture(self.texture);

        std.debug.assert(pitch == Frame.pitch);

        const ptr: [*]u8 = @ptrCast(pixel_ptr);
        const pixels = ptr[0..Frame.size];
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

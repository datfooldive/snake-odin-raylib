package game

import rl "vendor:raylib"

// Web/desktop entry plumbing (see source/main_web/main_web.odin)

run:       bool
g:         Game
screen:    Screen = .MENU
game_mode: Game_Mode = .SINGLE

init :: proc() {
	run = true
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(W, H, "snake — Q: slow-time  E: phase")
	rl.SetExitKey(.KEY_NULL)
	rl.SetTargetFPS(60)
	ai_self_check()
	init_audio()
}

update :: proc() {
	update_audio()
	if screen == .MENU {
		update_menu()
	} else if screen == .SETTINGS {
		update_settings()
	} else if screen == .PAUSED {
		update_pause()
	} else if rl.IsKeyPressed(.ESCAPE) {
		screen = .PAUSED
	} else {
		update_game(&g, rl.GetFrameTime())
	}
	rl.BeginDrawing()
	if screen == .MENU {
		draw_menu()
	} else if screen == .SETTINGS {
		draw_settings()
	} else {
		draw(&g)
		if screen == .PAUSED {
			draw_pause()
		}
	}
	rl.EndDrawing()
}

should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			run = false
		}
	}

	return run
}

shutdown :: proc() {
	if audio_ok {
		rl.CloseAudioDevice()
	}
	rl.CloseWindow()
}

// ponytail: fixed-size game, ignore browser resize
parent_window_size_changed :: proc(w, h: int) {}

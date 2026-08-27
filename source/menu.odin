package game

import "core:c"
import rl "vendor:raylib"

menu_button :: proc(label: cstring, y: c.int) -> bool {
	r := rl.Rectangle{W / 2 - 140, f32(y), 280, 48}
	hover := rl.CheckCollisionPointRec(rl.GetMousePosition(), r)
	rl.DrawRectangleRec(r, rl.Color{45, 42, 66, 255} if hover else rl.Color{31, 29, 47, 255})
	rl.DrawRectangleLinesEx(r, 2, rl.SKYBLUE if hover else rl.Color{85, 82, 110, 255})
	w := rl.MeasureText(label, 24)
	rl.DrawText(label, (W - w) / 2, y + 12, 24, rl.WHITE)
	return hover && rl.IsMouseButtonPressed(.LEFT)
}

start_game :: proc(mode: Game_Mode) {
	game_mode = mode
	reset(&g)
	screen = .PLAYING
}

toggle_bgm :: proc() {
	set_bgm(!bgm_on)
}

toggle_sfx :: proc() {
	sfx_on = !sfx_on
}

update_menu :: proc() {
	if rl.IsKeyPressed(.ONE) {
		start_game(.SINGLE)
	}
	if rl.IsKeyPressed(.TWO) {
		start_game(.VERSUS)
	}
	if rl.IsKeyPressed(.S) {
		screen = .SETTINGS
	}
}

update_settings :: proc() {
	if rl.IsKeyPressed(.B) {
		toggle_bgm()
	}
	if rl.IsKeyPressed(.F) {
		toggle_sfx()
	}
	if rl.IsKeyPressed(.ESCAPE) {
		screen = .MENU
	}
}

restart_game :: proc() {
	reset(&g)
	screen = .PLAYING
}

update_pause :: proc() {
	if rl.IsKeyPressed(.ESCAPE) {
		screen = .PLAYING
	}
	if rl.IsKeyPressed(.R) {
		restart_game()
	}
	if rl.IsKeyPressed(.M) {
		screen = .MENU
	}
}

draw_title :: proc() {
	rl.DrawText("SNAKE", (W - rl.MeasureText("SNAKE", 68)) / 2, 76, 68, rl.GOLD)
	rl.DrawText("eat, grow, survive", (W - rl.MeasureText("eat, grow, survive", 22)) / 2, 150, 22, rl.SKYBLUE)
}

draw_menu :: proc() {
	rl.ClearBackground({18, 17, 27, 255})
	draw_title()
	if menu_button("[1] SINGLE", 235) {
		start_game(.SINGLE)
	}
	if menu_button("[2] VERSUS AI", 300) {
		start_game(.VERSUS)
	}
	if menu_button("[S] SETTINGS", 365) {
		screen = .SETTINGS
	}
	rl.DrawText("Arrows move   Q slow   E phase", (W - rl.MeasureText("Arrows move   Q slow   E phase", 18)) / 2, 460, 18, rl.Color{145, 142, 165, 255})
}

draw_settings :: proc() {
	rl.ClearBackground({18, 17, 27, 255})
	draw_title()
	rl.DrawText("SETTINGS", (W - rl.MeasureText("SETTINGS", 32)) / 2, 205, 32, rl.WHITE)
	bgm_label: cstring = "[B] BGM: OFF" if !bgm_on else "[B] BGM: ON"
	sfx_label: cstring = "[F] SFX: OFF" if !sfx_on else "[F] SFX: ON"
	if menu_button(bgm_label, 275) {
		toggle_bgm()
	}
	if menu_button(sfx_label, 340) {
		toggle_sfx()
	}
	if menu_button("[ESC] BACK", 420) {
		screen = .MENU
	}
}

draw_pause :: proc() {
	rl.DrawRectangle(0, 0, W, H, rl.Fade(rl.BLACK, 0.72))
	rl.DrawText("PAUSED", (W - rl.MeasureText("PAUSED", 46)) / 2, 150, 46, rl.GOLD)
	if menu_button("[ESC] RESUME", 235) {
		screen = .PLAYING
	}
	if menu_button("[R] RESTART", 300) {
		restart_game()
	}
	if menu_button("[M] MAIN MENU", 365) {
		screen = .MENU
	}
}

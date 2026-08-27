package game

import "core:c"
import "core:math"
import rl "vendor:raylib"

skill_color :: proc(active, cd: f32, energy_ok: bool) -> rl.Color {
	if active > 0 {
		return rl.SKYBLUE
	}
	if cd <= 0 && energy_ok {
		return rl.WHITE
	}
	return {110, 110, 125, 255}
}

draw_skill :: proc(g: ^Game, x: c.int, label: cstring, active, cd: f32) {
	col := skill_color(active, cd, g.energy >= COST)
	t := c.int(math.ceil(math.max(cd, active)))
	if t > 0 {
		tag: cstring = "CD " if cd > active else ""
		rl.DrawText(rl.TextFormat("%s %s%ds", label, tag, t), x, ROWS * CELL + 12, 20, col)
	} else {
		rl.DrawText(label, x, ROWS * CELL + 12, 20, col)
	}
}

draw_hud :: proc(g: ^Game) {
	hy: c.int = ROWS * CELL
	rl.DrawRectangle(0, hy, W, HUD, {13, 12, 19, 255})
	rl.DrawText(rl.TextFormat("LV %d", g.level), 8, hy + 13, 18, rl.WHITE)
	if game_mode == .VERSUS {
		rl.DrawText(rl.TextFormat("YOU %d", g.eaten), 65, hy + 13, 18, rl.SKYBLUE)
		rl.DrawText(rl.TextFormat("CPU %d", g.rival_eaten), 135, hy + 13, 18, rl.ORANGE)
		rl.DrawText(rl.TextFormat("/ %d", g.target), 205, hy + 13, 18, rl.WHITE)
	} else {
		rl.DrawText(rl.TextFormat("FOOD %d / %d", g.eaten, g.target), 75, hy + 13, 18, rl.SKYBLUE)
	}

	for i in 0 ..< EMAX {
		pip := rl.Color{55, 55, 65, 255}
		if i < g.energy {
			pip = rl.Color{250, 210, 80, 255}
		}
		rl.DrawRectangle(c.int(255 + i * 13), hy + 17, 9, 11, pip)
	}

	draw_skill(g, 390, "[Q] SLOW", g.slow_t, g.cd_slow)
	draw_skill(g, 545, "[E] PHASE", g.phase_t, g.cd_phase)
}

draw :: proc(g: ^Game) {
	rl.ClearBackground({18, 17, 27, 255})

	ox := math.sin(g.t * 83.0) * g.shake * 14
	oy := math.cos(g.t * 71.0) * g.shake * 14
	cam := rl.Camera2D {
		offset = {ox, oy},
		zoom   = 1,
	}
	rl.BeginMode2D(cam)

	// board
	for y in 0 ..< ROWS {
		for x in 0 ..< COLS {
			c := rl.Color{29, 27, 42, 255}
			if (x + y) & 1 == 0 {
				c = rl.Color{33, 31, 48, 255}
			}
			rl.DrawRectangleV({f32(x) * CELL, f32(y) * CELL}, {CELL, CELL}, c)
		}
	}

	// obstacles
	for i in 0 ..< g.n_obs {
		p := center(g.obs[i])
		rl.DrawRectangleV(
			{p.x - CELL / 2 + 2, p.y - CELL / 2 + 2},
			{CELL - 4, CELL - 4},
			{78, 84, 108, 255},
		)
		rl.DrawRectangleV(
			{p.x - CELL / 2 + 2, p.y - CELL / 2 + 2},
			{CELL - 4, 4},
			{115, 122, 150, 255},
		)
	}

	// food: pulsing glow
	fp := center(g.food)
	pr := 4 + math.sin(g.t * 6) * 1.5
	rl.DrawCircleV(fp, 13, rl.Fade(rl.GOLD, 0.25 + 0.1 * math.sin(g.t * 6)))
	rl.DrawCircleV(fp, pr + 2, rl.GOLD)
	rl.DrawCircleV({fp.x - 2, fp.y - 2}, 2, rl.Color{255, 245, 200, 255})

	// rival snake
	for i := g.rival_len - 1; i >= 0; i -= 1 {
		p := center(g.rival[i])
		v := 1.0 - f32(i) / f32(g.rival_len)
		col := rl.Color{255, u8(80 + 100 * v), u8(35 + 30 * v), 255}
		inset: f32 = 2 if i != 0 else 1
		rl.DrawRectangleV(
			{p.x - CELL / 2 + inset, p.y - CELL / 2 + inset},
			{CELL - inset * 2, CELL - inset * 2},
			col,
		)
	}
	if g.rival_len > 0 {
		rd := rl.Vector2{f32(g.rival_dir.x), f32(g.rival_dir.y)}
		rs := rl.Vector2{-rd.y, rd.x}
		rh := center(g.rival[0])
		rl.DrawCircleV(rh + rd * 5 + rs * 4.5, 2.6, rl.BLACK)
		rl.DrawCircleV(rh + rd * 5 - rs * 4.5, 2.6, rl.BLACK)
	}

	// player snake, gradient tail -> head
	phasing := g.phase_t > 0
	for i := g.len - 1; i >= 0; i -= 1 {
		p := center(g.snake[i])
		c: rl.Color
		if phasing {
			c = rl.Color{80, 230, 255, u8(140 + math.sin(g.t * 20) * 60)}
		} else {
			c = rl.ColorFromHSV(
				math.mod(g.hue + f32(i) * 1.6, 360),
				0.55,
				(1.0 if i == 0 else 0.85 - f32(i) / f32(g.len) * 0.35),
			)
		}
		inset: f32 = 2
		if i == 0 {
			inset = 1
		}
		rl.DrawRectangleV(
			{p.x - CELL / 2 + inset, p.y - CELL / 2 + inset},
			{CELL - inset * 2, CELL - inset * 2},
			c,
		)
	}

	// eyes on head
	d := rl.Vector2{f32(g.dir.x), f32(g.dir.y)}
	side := rl.Vector2{-d.y, d.x}
	hp := center(g.snake[0])
	e1 := hp + d * 5 + side * 4.5
	e2 := hp + d * 5 - side * 4.5
	rl.DrawCircleV(e1, 2.6, rl.BLACK)
	rl.DrawCircleV(e2, 2.6, rl.BLACK)

	// particles
	n := min(g.np, MAX_PART)
	for i in 0 ..< n {
		p := &g.parts[i]
		if p.life <= 0 {
			continue
		}
		a := p.life / p.max
		rl.DrawCircleV(p.pos, p.size * a, rl.Fade(p.col, a))
	}

	rl.EndMode2D()

	if g.flash > 0 {
		rl.DrawRectangle(0, 0, W, H, rl.Fade(rl.WHITE, g.flash))
	}

	draw_hud(g)

	if !g.alive {
		rl.DrawRectangle(0, 0, W, H, rl.Fade(rl.BLACK, 0.55))
		msg := rl.TextFormat("GAME OVER — reached LV %d", g.level)
		if g.rival_won {
			msg = rl.TextFormat("RIVAL WINS — %d / %d", g.rival_eaten, g.target)
		}
		sub: cstring = "[R] restart"
		rl.DrawText(msg, (W - rl.MeasureText(msg, 44)) / 2, H / 2 - 50, 44, rl.RED)
		rl.DrawText(sub, (W - rl.MeasureText(sub, 22)) / 2, H / 2 + 10, 22, rl.WHITE)
	}
}

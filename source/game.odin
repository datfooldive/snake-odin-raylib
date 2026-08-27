package game

import "core:c"
import "core:math"
import rl "vendor:raylib"

CELL :: 24
COLS :: 30
ROWS :: 22
HUD :: 44
W :: COLS * CELL
H :: ROWS * CELL + HUD

MAX_SNAKE :: 1024
MAX_PART :: 800
MAX_OBS :: 150
COST :: 3 // skill energy cost
EMAX :: 9

Vec2i :: struct {
	x, y: i32,
}

Particle :: struct {
	pos, vel:        rl.Vector2,
	life, max, size: f32,
	col:             rl.Color,
}

Game :: struct {
	snake:    [MAX_SNAKE]Vec2i,
	len:      int,
	dir:      Vec2i,
	q:        [2]Vec2i, // queued turns, max 2
	qn:       int,
	food:     Vec2i,
	obs:      [MAX_OBS]Vec2i,
	n_obs:    int,
	level:    int,
	eaten:    int,
	target:   int, // lv1: 5, each next level +5
	timer:    f32,
	interval: f32,
	alive:    bool,
	t:        f32, // clock for pulses
	shake:    f32,
	flash:    f32,
	hue:      f32,
	parts:    [MAX_PART]Particle,
	np:       int,
	energy:   int,
	slow_t:   f32,
	phase_t:  f32,
	cd_slow:  f32,
	cd_phase: f32,
}

rnd :: proc(lo, hi: i32) -> i32 {
	return i32(rl.GetRandomValue(c.int(lo), c.int(hi)))
}

rf :: proc() -> f32 {
	return f32(rl.GetRandomValue(0, 1000)) / 1000.0
}

center :: proc(c: Vec2i) -> rl.Vector2 {
	return {f32(c.x) * CELL + CELL / 2, f32(c.y) * CELL + CELL / 2}
}

occupied :: proc(g: ^Game, c: Vec2i) -> bool {
	for i in 0 ..< g.len {
		if g.snake[i] == c {
			return true
		}
	}
	for i in 0 ..< g.n_obs {
		if g.obs[i] == c {
			return true
		}
	}
	return false
}

try_turn :: proc(g: ^Game, d: Vec2i) {
	last := g.dir
	if g.qn > 0 {
		last = g.q[g.qn - 1]
	}
	if (d.x != 0) == (last.x != 0) { 	// same axis: reversal or no-op
		return
	}
	if g.qn < 2 {
		g.q[g.qn] = d
		g.qn += 1
	}
}

reachable :: proc(g: ^Game) -> [COLS * ROWS]bool {
	seen: [COLS * ROWS]bool
	queue: [COLS * ROWS]Vec2i
	h := g.snake[0]
	seen[h.y * COLS + h.x] = true
	queue[0] = h
	qn := 1
	dx := [4]i32{1, -1, 0, 0}
	dy := [4]i32{0, 0, 1, -1}
	for qn > 0 {
		qn -= 1
		c := queue[qn]
		for k in 0 ..< 4 {
			n := Vec2i{c.x + dx[k], c.y + dy[k]}
			if n.x < 0 || n.x >= COLS || n.y < 0 || n.y >= ROWS {
				continue
			}
			i := n.y * COLS + n.x
			if seen[i] {
				continue
			}
			blocked := occupied(g, n)
			if blocked {
				continue
			}
			seen[i] = true
			queue[qn] = n
			qn += 1
		}
	}
	return seen
}

spawn_food :: proc(g: ^Game) {
	ok := reachable(g)
	for i in 0 ..< COLS * ROWS {
		f := Vec2i{rnd(0, COLS - 1), rnd(0, ROWS - 1)}
		if !occupied(g, f) && ok[f.y * COLS + f.x] {
			g.food = f
			return
		}
	}
	die(g) // board full / nowhere reachable
}

build_level :: proc(g: ^Game) {
	g.n_obs = 0
	n := min(MAX_OBS, 4 * g.level)
	attempts := 0
	for n > 0 && attempts < 2000 {
		attempts += 1
		c := Vec2i{rnd(0, COLS - 1), rnd(0, ROWS - 1)}
		head := g.snake[0]
		if !occupied(g, c) && math.abs(c.x - head.x) + math.abs(c.y - head.y) > 4 {
			g.obs[g.n_obs] = c
			g.n_obs += 1
			n -= 1
		}
	}
}

add_part :: proc(g: ^Game, p: Particle) {
	// ponytail: ring buffer overwrite, fine for cosmetic particles
	g.parts[g.np % MAX_PART] = p
	g.np += 1
}

burst :: proc(g: ^Game, p: rl.Vector2, col: rl.Color, n: int, spd: f32) {
	for i in 0 ..< n {
		a := rf() * 2 * math.PI
		v := spd * (0.25 + rf())
		add_part(
			g,
			Particle {
				pos = p,
				vel = {math.cos(a) * v, math.sin(a) * v},
				life = 0.35 + rf() * 0.5,
				max = 0.85,
				size = 2 + rf() * 4,
				col = col,
			},
		)
	}
}

reset :: proc(g: ^Game) {
	g^ = Game{}
	g.level = 1
	g.target = 5
	g.interval = 0.15
	cx: i32 = COLS / 2
	cy: i32 = ROWS / 2
	g.len = 4
	for i in 0 ..< 4 {
		g.snake[i] = {cx - i32(i), cy}
	}
	g.dir = {1, 0}
	g.alive = true
	build_level(g)
	spawn_food(g)
}

die :: proc(g: ^Game) {
	g.alive = false
	play(sfx_die)
	g.shake = 0.7
	for i in 0 ..< g.len {
		c := rl.ColorFromHSV(g.hue + f32(i) * 2, 0.7, 0.95)
		burst(g, center(g.snake[i]), c, 5, 260)
	}
}

level_up :: proc(g: ^Game) {
	play(sfx_level)
	g.level += 1
	g.eaten = 0
	g.target += 5
	g.interval = math.max(0.055, 0.15 * math.pow(0.93, f32(g.level - 1)))
	build_level(g)
	g.flash = 0.45
	g.shake = 0.55
	g.energy = min(EMAX, g.energy + 2)
	burst(g, center(g.snake[0]), rl.WHITE, 60, 320)
}

step :: proc(g: ^Game) {
	if g.qn > 0 {
		g.dir = g.q[0]
		g.q[0] = g.q[1]
		g.qn -= 1
	}
	h := Vec2i{g.snake[0].x + g.dir.x, g.snake[0].y + g.dir.y}
	phasing := g.phase_t > 0
	eat := h == g.food

	if phasing {
		h.x = ((h.x % COLS) + COLS) % COLS
		h.y = ((h.y % ROWS) + ROWS) % ROWS
		eat = h == g.food // re-check after wrap
	} else {
		if h.x < 0 || h.x >= COLS || h.y < 0 || h.y >= ROWS {
			die(g)
			return
		}
		for i in 0 ..< g.n_obs {
			if g.obs[i] == h {
				die(g)
				return
			}
		}
		// tail tip moves away this tick — unless eating, when it stays put
		tail_free := 0 if eat else 1
		for i in 0 ..< (g.len - tail_free) {
			if g.snake[i] == h {
				die(g)
				return
			}
		}
	}

	if !eat {
		g.len -= 1
	}
	for i := g.len; i > 0; i -= 1 {
		g.snake[i] = g.snake[i - 1]
	}
	g.snake[0] = h
	g.len += 1

	if eat {
		play(sfx_eat)
		g.eaten += 1
		g.energy = min(EMAX, g.energy + 1)
		g.hue = math.mod(g.hue + 37, 360)
		g.shake = math.max(g.shake, 0.3)
		burst(g, center(g.food), rl.ColorFromHSV(g.hue, 0.8, 1), 45, 280)
		if g.eaten >= g.target {
			level_up(g)
		}
		spawn_food(g)
	}
}

update_parts :: proc(g: ^Game, dt: f32) {
	n := min(g.np, MAX_PART)
	for i in 0 ..< n {
		p := &g.parts[i]
		if p.life <= 0 {
			continue
		}
		p.life = math.max(0, p.life - dt)
		p.vel.y += 380 * dt // gravity
		p.vel = p.vel * (1 - 2.2 * dt) // drag
		p.pos = p.pos + p.vel * dt
	}
}

update_game :: proc(g: ^Game, dt: f32) {
	// ponytail: clamp lag spikes; drag factor goes negative past dt ~0.45
	d := math.min(dt, 0.05)
	kp :: rl.IsKeyPressed
	g.t += d
	g.shake = math.max(0, g.shake - d * 1.6)
	g.flash = math.max(0, g.flash - d * 2)
	g.cd_slow = math.max(0, g.cd_slow - d)
	g.cd_phase = math.max(0, g.cd_phase - d)
	g.slow_t = math.max(0, g.slow_t - d)
	g.phase_t = math.max(0, g.phase_t - d)

	update_parts(g, d)

	if !g.alive {
		if kp(.R) {
			reset(g)
		}
		return
	}

	if kp(.UP) {
		try_turn(g, {0, -1})
	}
	if kp(.DOWN) {
		try_turn(g, {0, 1})
	}
	if kp(.LEFT) {
		try_turn(g, {-1, 0})
	}
	if kp(.RIGHT) {
		try_turn(g, {1, 0})
	}

	if kp(.Q) && g.cd_slow <= 0 && g.energy >= COST {
		g.energy -= COST
		g.slow_t = 4
		g.cd_slow = 9
		play(sfx_slow)
	}
	if kp(.E) && g.cd_phase <= 0 && g.energy >= COST {
		g.energy -= COST
		g.phase_t = 4
		g.cd_phase = 9
		play(sfx_phase)
	}

	gdt := d
	if g.slow_t > 0 {
		gdt *= 0.4
	}
	g.timer += gdt
	for g.timer >= g.interval && g.alive {
		g.timer -= g.interval
		step(g)
	}
}

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
	rl.DrawText(rl.TextFormat("LV %d", g.level), 12, hy + 12, 20, rl.WHITE)
	rl.DrawText(rl.TextFormat("%d / %d", g.eaten, g.target), 90, hy + 12, 20, rl.SKYBLUE)

	for i in 0 ..< EMAX {
		pip := rl.Color{55, 55, 65, 255}
		if i < g.energy {
			pip = rl.Color{250, 210, 80, 255}
		}
		rl.DrawRectangle(c.int(190 + i * 15), hy + 17, 10, 11, pip)
	}

	draw_skill(g, 370, "[Q] SLOW", g.slow_t, g.cd_slow)
	draw_skill(g, 530, "[E] PHASE", g.phase_t, g.cd_phase)
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

	// snake, gradient tail -> head
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
		sub: cstring = "[R] restart"
		rl.DrawText(msg, (W - rl.MeasureText(msg, 44)) / 2, H / 2 - 50, 44, rl.RED)
		rl.DrawText(sub, (W - rl.MeasureText(sub, 22)) / 2, H / 2 + 10, 22, rl.WHITE)
	}
}

// Web/desktop entry plumbing (see source/main_web/main_web.odin)

run: bool
g: Game

init :: proc() {
	run = true
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(W, H, "snake — Q: slow-time  E: phase")
	rl.SetTargetFPS(60)
	init_audio()
	reset(&g)
}

update :: proc() {
	update_audio()
	update_game(&g, rl.GetFrameTime())
	rl.BeginDrawing()
	draw(&g)
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

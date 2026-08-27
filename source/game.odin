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

Screen :: enum {
	MENU,
	SETTINGS,
	PLAYING,
}

Game_Mode :: enum {
	SINGLE,
	VERSUS,
}

Game :: struct {
	snake:        [MAX_SNAKE]Vec2i,
	len:          int,
	dir:          Vec2i,
	q:            [2]Vec2i, // queued turns, max 2
	qn:           int,
	rival:        [MAX_SNAKE]Vec2i,
	rival_len:    int,
	rival_dir:    Vec2i,
	rival_eaten:  int,
	rival_won:    bool,
	food:         Vec2i,
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
	for i in 0 ..< g.rival_len {
		if g.rival[i] == c {
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

in_bounds :: proc(p: Vec2i) -> bool {
	return p.x >= 0 && p.x < COLS && p.y >= 0 && p.y < ROWS
}

rival_blocked :: proc(g: ^Game, p: Vec2i, tail_free: bool) -> bool {
	if !in_bounds(p) {
		return true
	}
	for i in 0 ..< g.n_obs {
		if g.obs[i] == p {
			return true
		}
	}
	for i in 0 ..< g.len {
		if g.snake[i] == p {
			return true
		}
	}
	limit := g.rival_len - (1 if tail_free else 0)
	for i in 0 ..< limit {
		if g.rival[i] == p {
			return true
		}
	}
	return false
}

rival_options :: proc(d: Vec2i) -> [3]Vec2i {
	return {d, {d.y, -d.x}, {-d.y, d.x}} // straight, left, right
}

rival_space :: proc(g: ^Game, start: Vec2i) -> int {
	seen: [COLS * ROWS]bool
	queue: [COLS * ROWS]Vec2i
	seen[start.y * COLS + start.x] = true
	queue[0] = start
	head, tail := 0, 1
	dirs := [4]Vec2i{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
	for head < tail {
		p := queue[head]
		head += 1
		for d in dirs {
			n := Vec2i{p.x + d.x, p.y + d.y}
			if rival_blocked(g, n, true) {
				continue
			}
			i := n.y * COLS + n.x
			if seen[i] {
				continue
			}
			seen[i] = true
			queue[tail] = n
			tail += 1
		}
	}
	return tail
}

rival_turn :: proc(g: ^Game) -> (Vec2i, bool) {
	head := g.rival[0]
	queue: [COLS * ROWS]Vec2i
	seen: [COLS * ROWS]bool
	first: [COLS * ROWS]Vec2i
	seen[head.y * COLS + head.x] = true
	qn := 0

	for d in rival_options(g.rival_dir) {
		n := Vec2i{head.x + d.x, head.y + d.y}
		if rival_blocked(g, n, n != g.food) {
			continue
		}
		i := n.y * COLS + n.x
		seen[i] = true
		first[i] = d
		queue[qn] = n
		qn += 1
	}

	dirs := [4]Vec2i{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
	for qi := 0; qi < qn; qi += 1 {
		p := queue[qi]
		pi := p.y * COLS + p.x
		if p == g.food {
			return first[pi], true
		}
		for d in dirs {
			n := Vec2i{p.x + d.x, p.y + d.y}
			if rival_blocked(g, n, true) {
				continue
			}
			i := n.y * COLS + n.x
			if seen[i] {
				continue
			}
			seen[i] = true
			first[i] = first[pi]
			queue[qn] = n
			qn += 1
		}
	}

	// Food unreachable: choose safest legal turn by open area.
	best, best_area, best_dist := Vec2i{}, -1, COLS + ROWS + 1
	for d in rival_options(g.rival_dir) {
		n := Vec2i{head.x + d.x, head.y + d.y}
		if rival_blocked(g, n, n != g.food) {
			continue
		}
		area := rival_space(g, n)
		dist := int(math.abs(n.x - g.food.x) + math.abs(n.y - g.food.y))
		if area > best_area || area == best_area && dist < best_dist {
			best, best_area, best_dist = d, area, dist
		}
	}
	return best, best_area >= 0
}

spawn_rival :: proc(g: ^Game) -> bool {
	g.rival_len = 0
	dirs := [4]Vec2i{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
	for yi in 0 ..< ROWS {
		y := i32((ROWS / 2 + yi) % ROWS)
		for xi in 0 ..< COLS {
			x := i32(COLS - 1 - xi)
			for d in dirs {
				body: [4]Vec2i
				free := true
				for i in 0 ..< 4 {
					body[i] = {x - d.x * i32(i), y - d.y * i32(i)}
					if !in_bounds(body[i]) || occupied(g, body[i]) || body[i] == g.food {
						free = false
						break
					}
				}
				if free {
					g.rival_len = 4
					g.rival_dir = d
					for i in 0 ..< 4 {
						g.rival[i] = body[i]
					}
					return true
				}
			}
		}
	}
	return false
}

ai_self_check :: proc() {
	test := Game{}
	test.len = 1
	test.snake[0] = {20, 20}
	test.rival_len = 2
	test.rival[0] = {5, 5}
	test.rival[1] = {4, 5}
	test.rival_dir = {1, 0}
	test.food = {5, 3}
	d, ok := rival_turn(&test)
	assert(ok && d == Vec2i{0, -1}, "rival must turn toward reachable food")
	test.obs[0], test.n_obs = {5, 4}, 1
	d, ok = rival_turn(&test)
	assert(ok && d != Vec2i{0, -1}, "rival must avoid obstacle")
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
		rival_far := g.rival_len == 0 || math.abs(c.x - g.rival[0].x) + math.abs(c.y - g.rival[0].y) > 4
		if !occupied(g, c) && math.abs(c.x - head.x) + math.abs(c.y - head.y) > 4 && rival_far {
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
	if game_mode == .VERSUS {
		cx = COLS / 4
	}
	cy: i32 = ROWS / 2
	g.len = 4
	for i in 0 ..< 4 {
		g.snake[i] = {cx - i32(i), cy}
	}
	g.dir = {1, 0}
	g.alive = true
	if game_mode == .VERSUS {
		spawn_rival(g)
	}
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
	g.rival_eaten = 0
	g.target += 5
	g.interval = math.max(0.055, 0.15 * math.pow(0.93, f32(g.level - 1)))
	g.n_obs = 0
	if game_mode == .VERSUS {
		spawn_rival(g)
	}
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
		for i in 0 ..< g.rival_len {
			if g.rival[i] == h {
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

step_rival :: proc(g: ^Game) {
	if g.rival_len == 0 {
		spawn_rival(g)
		return
	}
	d, safe := rival_turn(g)
	if !safe {
		burst(g, center(g.rival[0]), rl.ORANGE, 30, 220)
		spawn_rival(g)
		return
	}
	g.rival_dir = d
	h := Vec2i{g.rival[0].x + d.x, g.rival[0].y + d.y}
	eat := h == g.food
	if !eat {
		g.rival_len -= 1
	}
	for i := g.rival_len; i > 0; i -= 1 {
		g.rival[i] = g.rival[i - 1]
	}
	g.rival[0] = h
	g.rival_len += 1

	if eat {
		play(sfx_eat)
		g.rival_eaten += 1
		g.shake = math.max(g.shake, 0.2)
		burst(g, center(g.food), rl.ORANGE, 35, 240)
		if g.rival_eaten >= g.target {
			g.rival_won = true
			die(g)
			return
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
		if g.alive && game_mode == .VERSUS {
			step_rival(g)
		}
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
		set_bgm(!bgm_on)
	}
	if rl.IsKeyPressed(.F) {
		sfx_on = !sfx_on
	}
	if rl.IsKeyPressed(.ESCAPE) {
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
		set_bgm(!bgm_on)
	}
	if menu_button(sfx_label, 340) {
		sfx_on = !sfx_on
	}
	if menu_button("[ESC] BACK", 420) {
		screen = .MENU
	}
}

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
	} else {
		if rl.IsKeyPressed(.ESCAPE) {
			screen = .MENU
		} else {
			update_game(&g, rl.GetFrameTime())
		}
	}
	rl.BeginDrawing()
	if screen == .MENU {
		draw_menu()
	} else if screen == .SETTINGS {
		draw_settings()
	} else {
		draw(&g)
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

package game

import "core:c"
import "core:math"
import rl "vendor:raylib"

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

reachable :: proc(g: ^Game) -> [COLS * ROWS]bool {
	seen: [COLS * ROWS]bool
	queue: [COLS * ROWS]Vec2i
	h := g.snake[0]
	seen[h.y * COLS + h.x] = true
	queue[0] = h
	qn := 1
	for qn > 0 {
		qn -= 1
		c := queue[qn]
		for d in CARDINAL_DIRS {
			n := Vec2i{c.x + d.x, c.y + d.y}
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
		g.score += 1
		record_score(g.score)
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
		if g.alive && game_mode == .VERSUS {
			step_rival(g)
		}
	}
}

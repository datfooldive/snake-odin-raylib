package game

import "core:math"
import rl "vendor:raylib"

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
	for head < tail {
		p := queue[head]
		head += 1
		for d in CARDINAL_DIRS {
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

	for qi := 0; qi < qn; qi += 1 {
		p := queue[qi]
		pi := p.y * COLS + p.x
		if p == g.food {
			return first[pi], true
		}
		for d in CARDINAL_DIRS {
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
	for yi in 0 ..< ROWS {
		y := i32((ROWS / 2 + yi) % ROWS)
		for xi in 0 ..< COLS {
			x := i32(COLS - 1 - xi)
			for d in CARDINAL_DIRS {
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

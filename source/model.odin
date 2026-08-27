package game

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

CARDINAL_DIRS :: [4]Vec2i{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

Particle :: struct {
	pos, vel:        rl.Vector2,
	life, max, size: f32,
	col:             rl.Color,
}

Screen :: enum {
	MENU,
	SETTINGS,
	PLAYING,
	PAUSED,
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
	score:    int,
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

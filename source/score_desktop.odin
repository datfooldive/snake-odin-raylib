#+build !js
package game

import "core:os"
import "core:path/filepath"
import "core:strconv"

score_path :: proc() -> (string, bool) {
	base, base_err := os.user_data_dir(context.temp_allocator)
	if base_err != nil {
		return "", false
	}
	dir, dir_err := filepath.join({base, "snake-odin-raylib"}, context.temp_allocator)
	if dir_err != nil || os.make_directory_all(dir) != nil {
		return "", false
	}
	path, path_err := filepath.join({dir, "high_score"}, context.temp_allocator)
	return path, path_err == nil
}

load_high_score :: proc() -> int {
	path, ok := score_path()
	if !ok {
		return 0
	}
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return 0
	}
	score, valid := strconv.parse_int(string(data))
	if !valid || score < 0 {
		return 0
	}
	return score
}

save_high_score :: proc(score: int) {
	path, ok := score_path()
	if !ok {
		return
	}
	buf: [32]byte
	text := strconv.write_int(buf[:], i64(score), 10)
	_ = os.write_entire_file(path, text)
}

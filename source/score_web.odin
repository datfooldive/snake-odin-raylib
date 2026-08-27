#+build js
package game

foreign import "odin_env"

@(default_calling_convention="c")
foreign odin_env {
	@(link_name="load_high_score")
	web_load_high_score :: proc() -> i32 ---
	@(link_name="save_high_score")
	web_save_high_score :: proc(score: i32) ---
}

load_high_score :: proc() -> int {
	return max(0, int(web_load_high_score()))
}

save_high_score :: proc(score: int) {
	web_save_high_score(i32(score))
}

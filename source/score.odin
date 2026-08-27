package game

high_score: int

load_score :: proc() {
	high_score = load_high_score()
}

record_score :: proc(score: int) {
	if score <= high_score {
		return
	}
	high_score = score
	save_high_score(high_score)
}

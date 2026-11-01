extends Node
## Global game state and configuration shared between scenes

enum Difficulty { EASY, MEDIUM, HARD }
enum Language { EN, TR }

var difficulty: Difficulty = Difficulty.EASY
var language: Language = Language.EN

func get_health_decay_multiplier() -> float:
	match difficulty:
		Difficulty.EASY:
			return 1.0
		Difficulty.MEDIUM:
			return 1.5
		Difficulty.HARD:
			return 2.0
		_:
			return 1.0


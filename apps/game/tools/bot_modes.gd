extends RefCounted

## One rule shared by the play bot and its test: how many loops a run plays.
##
## A gauntlet run is one guardian fight, always; a natural run draws one to `loops_max`, the `loops=`
## argument. It lives here, away from the bot, so the test can read it without starting the game: the bot
## scene pulls in the arena, which only runs inside a started run.

static func loops_target_for(gauntlet: bool, loops_max: int, rng: RandomNumberGenerator) -> int:
	if gauntlet:
		return 1
	return rng.randi_range(1, loops_max)

extends Node2D

## Moonlit Beacon arena.
##
## Three beacons → guardian → the next cycle is one loop. Closing a cycle also
## advances terrain and time of day. Long fights stay on one loop without the screen freezing into a single still.

## Time to brighten. Kept longer than the catch time (`Beacon.IGNITE_SECONDS`, 0.45s) so
## the beacon flames first and the forest brightens after.
const BRIGHTEN_SECONDS: float = 1.1

## How long the hit flash lasts.
const HIT_FLASH_SECONDS: float = 0.42

## Zoom the world alone by 4/3. HUD and touch stay on the CanvasLayer's 808×360 coords;
## on a Pixel 10 one internal pixel becomes exactly 4 screen px instead of 3.
## Characters, enemies, projectiles, and terrain scale together so hitboxes and art keep the same relative size.
const WORLD_CAMERA_ZOOM: float = Room.WORLD_CAMERA_ZOOM

## Health.
##
## Through Lesson 17 this was 3. Once spirits could be cut, diving in became the play,
## but three hearts meant one bad dive ended the run, so players stopped trying.
## Raised to 5 together with the heal pickup (moon dew).
const MAX_HEALTH: int = 5
## Hero, permanent grace, and in-run relics all stop here. When hearts near two rows,
## one hit stops mattering and the time to the result screen gets too long.
const MAX_HEALTH_LIMIT: int = 8
## After a guardian falls, do not wipe combat damage — heal only one heart.
const CYCLE_HEAL: int = 1

## After a hit, stay immune for this long.
##
## Each spirit has its own cooldown (`Spirit.HIT_COOLDOWN`), and up to three can stick at once.
## Without i-frames, three overlapping contacts **drain three hearts in one frame.**
const HIT_INVULNERABLE: float = 0.8

## Spirit spawn points. They ring the inside of the large map's rim.
## They walk in from off-screen, so "coming out of the dark" is literal.
const SPAWN_POINTS: Array[Vector2] = [
	Vector2(160, 160), Vector2(950, 130), Vector2(1740, 160),
	Vector2(130, 590), Vector2(1770, 590),
	Vector2(160, 1020), Vector2(950, 1050), Vector2(1740, 1020),
]

## How often a pack is released. **It never ends.**
##
## Over 80 seconds it tightens from 2.4s to 1.0s, then keeps edging faster until
## it floors at 0.34s. The longer you last, the fuller the forest gets with spirits — that is this
## game's pressure. 6.0s·2min → 4.6s·100s → pulled twice so far. The last
## feedback was "still no rhythm; mobs arrive one or two at a time," and shortening only
## the interval just makes one spirit arrive a bit more often, so `_spawn_burst()` below also
## adds **pack units.**
const SPAWN_INTERVAL_START: float = 2.4
const SPAWN_INTERVAL_END: float = 1.0

## Never keep more than this alive at once. The map is 1900×1180, so twenty-four is not dense.
## The 4/3 camera's visible world (~606×270) shows only some of them — the rest are
## still approaching from the dark.
## As cycles rise, `spirit_cap()` grows past this value.
const MAX_SPIRITS: int = 24

## Gap between raids, and how many to call at once.
##
## 32s is just before "again?" shows up. At 20s raids became the baseline and the
## contrast vanished; at 50s they arrived only after you had forgotten them.
const RAID_EVERY: float = 32.0
const RAID_BASE: int = 7
## Raid formation baseline distance. The 4/3 camera's world radius is ~303px wide · 135px tall, so
## vertical packs enter from the rim and horizontal lines can already be on screen. Prefer ambush,
## crossfire, and escort entry shapes over a pure off-screen spawn.
const RAID_RING: float = 210.0
## Quiet after a raid.
const RAID_LULL: float = 4.5
## Spawning a whole raid pack in one frame stacks every spirit's SpriteFrames build.
## Stagger them at a short step (about two visible at a time) to avoid mobile hitching.
const RAID_SPAWN_STEP: float = 0.08

## New kinds unlock with time survived.
##
## Unlock everything at once and players see it all in 30s and get bored. **New faces as you last**
## is why they keep going. Earlier kinds still spawn; later ones mix in.
##
## Each entry is [unlock time (seconds), resource path].
## When the spawn ramp was pulled to 80s, this table moved with it (~×0.8). The gap between
## new faces *is* the rhythm — raise density alone and open kinds late, and the run is only
## the same spirit flooding in.
const SPIRIT_UNLOCKS: Array = [
	[0.0,   "res://resources/wisp.tres"],      # Wandering spirit — chases
	[16.0,  "res://resources/drifter.tres"],   # Night bat — chases fast
	[36.0,  "res://resources/weaver.tres"],    # Orbiting soul — circles
	[60.0,  "res://resources/ember.tres"],     # Ember spirit — faster than the player
	[84.0,  "res://resources/stalker.tres"],   # Night stalker — locks on and lunges
	[112.0, "res://resources/caster.tres"],    # Moonlight caster — keeps distance and shoots
	[144.0, "res://resources/swarm.tres"],     # Tiny ember — weak and very fast
]

const RIPPLE_SCENE: PackedScene = preload("res://scenes/items/moon_ripple.tscn")
const MISSILE_SCENE: PackedScene = preload("res://scenes/actors/moon_missile.tscn")
const MISSILE_CORE_SCENE: PackedScene = preload(
	"res://scenes/items/missile_core.tscn")
const MISSILE_CORE_TEXTURE_PATH: String = \
	"res://assets/custom/items/pickups/power_gem.png"
const MISSILE_CORE_TEXTURE: Texture2D = preload(
	"res://assets/custom/items/pickups/power_gem.png")
const EMBER_SCENE: PackedScene = preload("res://scenes/items/moon_ember.tscn")

## Sandbox handshake used only when a store device capture explicitly asks the debug APK.
## Release builds have no debug tools, and the paths below also refuse under OS.is_debug_build(),
## so normal play banners and save data are untouched.
const DEBUG_MISSILE_CAPTURE_REQUEST_PATH: String = \
	"user://store_capture_missile_core.request"
const DEBUG_MISSILE_CAPTURE_STATE_PATH: String = \
	"user://store_capture_state.json"
const DEBUG_MISSILE_CAPTURE_TEMP_PATH: String = \
	"user://store_capture_state.tmp"
const TEST_HERO_REQUEST: Script = preload("res://scripts/dev/test_hero_request.gd")
const STORE_CAPTURE_PROBE: Script = preload(
	"res://scripts/dev/store_capture_probe.gd")

## Real runtime groups counted as loot in the hero-direction matrix. Pending spawn counts are proven
## in a separate field so a one-frame gap around queue_free is not mistaken for clean.
const HERO_DIRECTION_PICKUP_GROUPS: Array[StringName] = [
	&"moon_embers", &"power_orbs", &"missile_cores", &"moon_dews",
]

const SPIRIT_SCENE: PackedScene = preload("res://scenes/actors/spirit.tscn")
const DEW_SCENE: PackedScene = preload("res://scenes/items/moon_dew.tscn")
const ROOM_SCENE: PackedScene = preload("res://scenes/gameplay/room.tscn")
const ARROW_SCENE: PackedScene = preload("res://scenes/actors/moon_arrow.tscn")

## Moon arrow — the second weapon.
##
## Slash alone makes the screen dull. Survivor fun comes from **several weapons firing on their own
## and visibly getting stronger.** Start with it equipped and grow it through relics.
const ARROW_COOLDOWN: float = 1.15
## Arrow reach. Much farther than slash (34) — you can chip before they close in.
const ARROW_RANGE: float = 240.0
## The debug late-game preset must rebuild the same worst-case load every run so before/after numbers
## compare. Order: max meteor fire · 8-shot volley plus ring · ripple · full-moon slash together.
## Not used by the live card-offer rules.
const TEST_STRESS_RELICS: Array[String] = [
	"res://resources/relics/twin_arrow.tres",
	"res://resources/relics/quick_arrow.tres",
	"res://resources/relics/pierce_arrow.tres",
	"res://resources/relics/quick_arrow.tres",
	"res://resources/relics/quick_arrow.tres",
	"res://resources/relics/quick_arrow.tres",
	"res://resources/relics/twin_arrow.tres",
	"res://resources/relics/twin_arrow.tres",
	"res://resources/relics/twin_arrow.tres",
	"res://resources/relics/twin_arrow.tres",
	"res://resources/relics/heavy_arrow.tres",
	"res://resources/relics/moon_ring.tres",
	"res://resources/relics/moon_ripple.tres",
	"res://resources/relics/moon_ring.tres",
	"res://resources/relics/moon_ripple.tres",
	"res://resources/relics/wide_arc.tres",
	"res://resources/relics/long_blade.tres",
	"res://resources/relics/swift_hand.tres",
	"res://resources/relics/shadow_veil.tres",
]
## Auto weapons do not replace the choice to step in and slash.
##
## Blade, moon wheel, ring, and ripple once all started at damage 10, so two early cards
## melted spirits before the player touched them. Auto attacks open a path; the blade finishes.
const ARROW_BASE_HIT: int = 5
const AUX_BASE_HIT: int = 5

## Terrain per cycle step.
##
## Night forest → open field → abandoned camp, then back to forest.
## Small props are passable; unique structures actually block. All three terrains share
## `Room.PLAY` and reserve entrances/spawns, so combat coords stay safe when the room changes.
const WORLD_STEPS: Array[Dictionary] = [
	{
		"room": "res://resources/rooms/forest.tres",
		"name": "WORLD_FOREST",
		"guardian": "res://resources/guardian_forest.tres",
		"guardians": [
			"res://resources/guardian_forest.tres",
			"res://resources/guardian_forest_thorn.tres",
		],
	},
	{
		"room": "res://resources/rooms/field.tres",
		"name": "WORLD_FIELD",
		"guardian": "res://resources/guardian_field.tres",
		"guardians": [
			"res://resources/guardian_field.tres",
			"res://resources/guardian_field_storm.tres",
		],
	},
	{
		"room": "res://resources/rooms/camp.tres",
		"name": "WORLD_CAMP",
		"guardian": "res://resources/guardian_camp.tres",
		"guardians": [
			"res://resources/guardian_camp.tres",
			"res://resources/guardian_camp_siege.tres",
		],
	},
]
## Real frame sources allowed for the field guardian in store shot 04. Reading the expected sheet back
## from the current `kind` misses the case where a wrong sheet is stuck on both kind and Sprite.
##
## Keep both the base and storm variants. The capture setup is cycle 3, so the evolved storm form
## is what actually appears; what we block is a guardian from **another world** landing in the field
## cut — not the stronger form of the same field guardian.
## Field-guardian bodies allowed for shot 04. Two variants for the same reason as the texture list.
const FIELD_GUARDIAN_CAPTURE_KINDS: Array[String] = [
	"res://resources/guardian_field.tres",
	"res://resources/guardian_field_storm.tres",
]
const FIELD_GUARDIAN_CAPTURE_TEXTURES: Array[String] = [
	"res://assets/custom/actors/guardians/field.png",
	"res://assets/custom/actors/guardians/field_windup_cross.png",
	"res://assets/custom/actors/guardians/field_windup_radial.png",
	"res://assets/custom/actors/guardians/field_recover.png",
	"res://assets/custom/actors/guardians/field_storm.png",
	"res://assets/custom/actors/guardians/field_storm_windup_cross.png",
	"res://assets/custom/actors/guardians/field_storm_windup_radial.png",
	"res://assets/custom/actors/guardians/field_storm_recover.png",
]
## `SpiritKind.duplicate()` does not keep the original `resource_path`. Pin the source path used for
## summon onto the guardian node itself so capture neither treats an empty path as a real field
## guardian nor fails a valid boss proof.
const GUARDIAN_KIND_SOURCE_PATH_META: StringName = \
	&"moonlit_guardian_kind_source_path"
## Do not accept a guardian with only a 1px edge on screen as a "visible boss" for an ad shot.
## Frame animation keeps the same size, so requiring 12px on one edge and 35% of total area at once
## still leaves normal placements plenty of room while the body stays readable.
const GUARDIAN_CAPTURE_MIN_VISIBLE_EDGE: float = 12.0
const GUARDIAN_CAPTURE_MIN_VISIBLE_FRACTION: float = 0.35
## Shot 04's guardian must not merely clip the screen edge. Keep the full live frame inside the
## central 56% × 64% zone and separate it from the player so the silhouette reads.
const GUARDIAN_CAPTURE_FOCUS_POSITION: Vector2 = Vector2(0.22, 0.24)
const GUARDIAN_CAPTURE_FOCUS_SIZE: Vector2 = Vector2(0.56, 0.64)
const GUARDIAN_CAPTURE_TARGET_LEFT_X: float = 0.38
const GUARDIAN_CAPTURE_TARGET_RIGHT_X: float = 0.62
const GUARDIAN_CAPTURE_TARGET_Y: float = 0.64
const GUARDIAN_CAPTURE_MIN_PLAYER_SEPARATION: float = 72.0
## Normal spirits use a 24px frame. If any axis is under 2px or the intersection area is under
## 16px², it is only a 1px rim line or a tiny scale — not an enemy that reads in an ad.
const ENEMY_CAPTURE_MIN_VISIBLE_EDGE: float = 2.0
const ENEMY_CAPTURE_MIN_VISIBLE_AREA: float = 16.0

## The stretch after lighting one beacon when you run for the next terrain.
##
## If terrain only changes after the boss, you sit in one room until the first boss and barely feel
## that three maps exist. The first two beacons open a far-rim gate; you must break through the chase
## to that gate to move to the next terrain.
const ZONE_FADE_SECONDS: float = 0.38
const ESCAPE_WAVE_INTERVAL: float = 3.0
const ESCAPE_WAVE_COUNT: int = 3
const ESCAPE_WAVE_MAX: int = 3
const GATE_EDGE_INSET: float = 34.0
## Real collision radius used to push permanent/recoverable loot clear of new structures on terrain change.
const POWER_ORB_TERRAIN_RADIUS: float = 12.0
const MISSILE_CORE_TERRAIN_RADIUS: float = 10.0

## Four times of day as beacons push the night back.
##
## Do not use a global `CanvasModulate`. It would tint the player, spirits, and beacon flames too,
## and combat readability drops. Tint only the background container so characters and projectiles stay
## sharp, and both night and day show inside the first cycle.
const TIME_STEPS: Array[Dictionary] = [
	{"name": "TIME_NIGHT", "tone": Color(1.00, 1.00, 1.00, 1)},
	{"name": "TIME_BLUE_DAWN", "tone": Color(1.12, 1.10, 1.04, 1)},
	{"name": "TIME_SUNRISE", "tone": Color(1.32, 1.20, 1.00, 1)},
	{"name": "TIME_DAY", "tone": Color(1.55, 1.38, 1.12, 1)},
]

## Chance moon dew drops when a spirit scatters.
##
## Baseline tuned through late game where kill counts climb hard. Live dew caps at three and
## despawns after 18s, so the whole map does not become a heal warehouse.
const DEW_CHANCE: float = 0.08
## When one heart is left. Only rises near death.
const DEW_CHANCE_LOW: float = 0.20
const DEW_LIMIT: int = 3
## Even when late-game kill rate climbs, heal throughput must not scale forever with kills.
## Elite rescue dew alone skips this limit.
const DEW_DROP_COOLDOWN: float = 12.0
## Score given instead when health is full so dew is not dropped.
const DEW_FULL_HEALTH_SCORE: int = 150
const ARENA_THEME: AudioStream = preload("res://assets/third_party/ninja_adventure/audio/music/arena_theme.ogg")

const VOICE_PANEL: Script = preload("res://scripts/ui/voice_panel.gd")

## BGM tempo. The source track is exploration music — too leisurely for survivor hands —
## so the goal is "bright and urgent like Cookie Run." No new track; playback rate does it.
## Pitch rises a little each cycle so late-game squeeze is heard as well as seen.
const BGM_PITCH_BASE: float = 1.14
const BGM_PITCH_PER_CYCLE: float = 0.03
const BGM_PITCH_MAX: float = 1.32
const GUARDIAN_THEME: AudioStream = preload("res://assets/third_party/ninja_adventure/audio/music/guardian_theme.ogg")

## Moon embers enemies leave, and moonfire awakening.
##
## If kills only bump a level number, the field has no loot left on it.
## Every spirit drops one ember; gather ten and every weapon briefly heats up.
## Elites drop a ×4 ember so "kill that big one first" has a reason.
const MOONFIRE_MAX: float = 10.0
const MOONFIRE_SECONDS: float = 6.5
const MOONFIRE_DAMAGE: float = 1.22
const MOONFIRE_HASTE: float = 0.86
const EMBER_CHARGE: float = 1.0
const ELITE_EMBER_CHARGE: float = 4.0
## Cap on live ember nodes. Overflow goes straight into the gauge to save frames.
const EMBER_LIMIT: int = 36
## Fill from one beacon. Three fill an empty gauge.
const BEACON_CHARGE: float = MOONFIRE_MAX / 3.0
## Lighting a beacon during awakening extends by this much instead of filling the gauge.
## Kept distinct from a small ember extension so the banner can show the exact value.
const BEACON_MOONFIRE_EXTENSION: float = 0.5

## Beacon defense chosen instead of stable lighting. Long enough to read one dash and two raids,
## without stretching into a guardian fight.
const OVERCHARGE_SECONDS: float = 6.5
const OVERCHARGE_RADIUS: float = 88.0
const OVERCHARGE_ABANDON_RADIUS: float = 148.0
const OVERCHARGE_ABANDON_GRACE: float = 0.8
const OVERCHARGE_DECAY_SCALE: float = 0.5
const OVERCHARGE_WAVE_AT: float = 0.48
const OVERCHARGE_BASE_WAVE: int = 5

## Kill streak (heat).
##
## **Pushing a pack must pay on its own.** Until now kills only fed level, and level rises slowly,
## so kiting and diving felt the same in the hand.
## Dive and get stronger on the spot, or there is no reason to dive.
##
## Landing the next kill inside this window continues the streak. Too short and it cannot hold;
## too long and you are always heated, so it means nothing.
const COMBO_WINDOW: float = 3.2
## Kills per tier step.
const COMBO_STEP: int = 5
## Max tier. Unlimited climb breaks late game.
const COMBO_MAX_TIER: int = 4
## Attack interval shortens by this much per tier. Cap is 24%, so even stacked with awakening and
## relics the early attack animation does not vanish entirely.
const COMBO_HASTE: float = 0.06

## Kills needed to go from level 1 to 2.
##
## A card after the first three leaves no room to learn basic slash and a single moon wheel.
## Five kills is about 10–15s — first change comes soon, but the starting weapon's feel lands first.
const LEVEL_FIRST: int = 5
## Each level makes the next one farther.
##
## 1.20 collapses late game. Level 20 needed 686 cumulative kills; level 40 needed 28,509 —
## at roughly two kills per second, level 40 is **four hours.**
## Growth you cannot reach is growth that does not exist.
##
## Lowered to 1.12 and **capped the threshold itself.** Multiply-only curves, however gentle, are still
## exponential and hit the same wall. Keep one level under thirty kills and late game still sees a
## card about every 15s — the answer to "power-ups need to come fast."
const LEVEL_GROWTH: float = 1.14
## Ceiling on kills required per level.
const LEVEL_CAP: int = 28

## Where back goes while paused.
const TITLE_SCENE: String = "res://scenes/menus/title_menu.tscn"
## One-shot flag passed to the title when the result screen picks the shrine.
const OPEN_SHRINE_META: StringName = &"moonlit_open_shrine"
## Flag asking the title to open the real-money shop.
## Shrine (shards) and shop (cash) are different screens — coins sell only in the shop.
const OPEN_STORE_META: StringName = &"moonlit_open_store"

enum ResultAction {
	NONE,
	RESTART,
	SHRINE,
}

@onready var _rooms_root: Node2D = $Rooms
@onready var _beacons: Array[Node2D] = [$BeaconWest, $BeaconEast, $BeaconNorth]
@onready var _player: Player = $Player
@onready var _camera: Camera2D = $Player/Cam
## Move stick. **Covers the full screen.**
##
## Used to split left/right halves — move left, dash right (Brawl Stars style).
## Survivor standard is one move stick + auto attack; the half-split caused
## **"I pressed the middle and it slid"** confusion. The boundary was screen center with
## no mark at all.
@onready var _stick: Control = $Ui/MoveStick
@onready var _dash_button: Control = $Ui/Dash
@onready var _spirit: Node2D = $Spirit
@onready var _hit_flash: ColorRect = $Ui/HitFlash
@onready var _gate: Node2D = $MoonGate
@onready var _result: Control = $Ui/Result
@onready var _analytics_consent: AnalyticsConsentPanel = $Ui/AnalyticsConsent
@onready var _hud: Control = $Ui/Hud
@onready var _bgm: AudioStreamPlayer = $Bgm
@onready var _pause: Control = $Ui/Pause
@onready var _settings: Control = $Ui/Settings
@onready var _credits: Control = $Ui/Credits
@onready var _relic: Control = $Ui/Relic
@onready var _ladder: Control = $Ui/Ladder
@onready var _dialogue: Control = $Ui/Dialogue
@onready var _run_choice: RunChoicePanel = $Ui/RunChoice
@onready var _compass: Control = $Ui/Compass
@onready var _event_sfx: AudioStreamPlayer = $EventSfx
@onready var _pickup_sfx: AudioStreamPlayer = $PickupSfx
@onready var _zone_wipe: ColorRect = $Ui/ZoneWipe
@onready var _zone_wipe_label: Label = $Ui/ZoneWipe/Label

var _lit_count: int = 0
var _brighten: Tween = null
var _flash: Tween = null
var _health: int = MAX_HEALTH
var _over: bool = false
## Debug invulnerability. Only on when chaining several cycles to inspect.
## The only path that sets this is `scripts/dev/arena_tools.gd`, and that vanishes in release.
var _shielded: bool = false
## Values to ask the ladder after the result screen is dismissed.
var _board_score: int = 0
var _board_rank: String = "D"
var _board_cycles: int = 0
## Hero this run started with. Refunds or shrine re-picks apply from the next run.
##
## Re-reading Vault mid-fight after a refund can leave look and opening relics as Keeper while stats and
## ladder name flip to Warden — a half switch. Pin resource and path as a pair so recompute and
## result submission keep the same hero.
var _run_hero: Hero = null
var _run_hero_path: String = ""
## Remember the next action chosen on the result screen even while name entry runs.
var _pending_result_action: ResultAction = ResultAction.NONE
var _spawn_timer: float = SPAWN_INTERVAL_START
var _spirits: Array[Node2D] = []
var _guardian: Node2D = null
## While a coordinate-free device-capture request is live, lock the real field guardian's framing.
## In release, debug_prepare_store_capture() returns immediately, so combat is untouched.
var _debug_guardian_capture_active: bool = false
## Debug-only quiet board that shoots Pixel 10's 6 heroes × 4 directions in real move poses.
## In release, debug_prepare_store_capture()'s guard cannot be passed.
var _debug_hero_direction_capture_active: bool = false
var _debug_hero_direction_clean_frames: int = 0
var _debug_hero_direction_last_process_frame: int = -1
var _debug_hero_direction_request_signature: String = ""
## Which cycle. Three beacons → guardian → kill it → three beacons again.
##
## **This gives endless survival a goal.** Early redesign lit three beacons, spawned a guardian,
## and after the kill nothing happened — spawns froze forever and you were **alone on an empty map.**
## Cycles keep "where's the next beacon" coming.
## Hero voice lines. Reset each run so the same line is not heard twice.
var _voice: HeroVoice = HeroVoice.new()
var _voice_panel: VoicePanel = null

var _cycle: int = 1
## Terrain index inside one cycle. Advances 0→1→2 per beacon.
var _zone_index: int = 0
## On only while running for the gate after the first two beacons.
var _escape_active: bool = false
var _escape_wave_left: float = 0.0
var _escape_waves_spawned: int = 0
## Outward direction of the current gate. On the next terrain the same vector is the inward run direction.
var _gate_direction: Vector2 = Vector2.RIGHT
var _transitioning: bool = false
## Increments on every terrain cross. A deferred callback from the old terrain must not banner the new room.
var _zone_serial: int = 0
## Time to the next raid. First raid arrives within 15s — at 1.4× (45s) the first minute was a stroll,
## and 0.9× (29s) still felt loose.
## Learning time comes from the quiet between raids (RAID_LULL).
var _raid_left: float = RAID_EVERY * 0.45
## Spirits queued for this terrain's raid. Counted toward the cap with actives.
var _raid_queue: Array[Dictionary] = []
var _raid_spawn_left: float = 0.0
var _invulnerable: float = 0.0
## Lesson 17. Kill count goes to the HUD; kill score goes to the result screen.
var _kills: int = 0
var _kill_score: int = 0

## Values relics change. Constants cannot rise mid-run.
var _max_health: int = MAX_HEALTH
var _invulnerable_time: float = HIT_INVULNERABLE
var _dew_multiplier: float = 1.0
## Dew only reserved from a physics callback still counts toward the cap.
var _pending_dews: int = 0
## Normal dew shares one clock across the whole field.
var _dew_drop_cooldown: float = 0.0
## Attack-interval multiplier relics stacked. Kept apart from heat so they do not overwrite each other.
## Mounted weapons. Stacking a relic grows this reference instead of making a new one.
## In pickup order. Hits keep relics; only missile power ejects one rank.
## Damage multiplier. **Multiply, do not add.**
##
## Used to be `attack_damage += 1`. First stack is +100% (1→2) but the tenth is only
## +9% (11→12). Spirit HP grows ×1.35 per cycle — exponential.
## Different dimensions, so the gap only widened — kills/sec fell from 3.5 at 2 minutes to
## 0.35 at 15 minutes. The screen looked loud while spirits would not die.
##
## Multiply and the player grows exponentially too. Same dimension to compete in.
var _damage_mult: float = 1.0
var _arrow_mult: float = 1.0
## **Raw** interval multiplier from relics, before the floor.
## `_settle_rates()` derives the effective interval and overflow from this.
var _arrow_haste: float = 1.0
## Relics still owed, and when a card was last shown.
var _owed: int = 0
var _last_offer: float = -99.0
## Kill signals arrive inside a physics tick. Opening the card panel and pausing the tree there
## bills UI setup to physics time, so queue once on the idle boundary.
var _relic_offer_queued: bool = false
var _taken: Array[Relic] = []
var _ring: MoonRing = null
var _ripple: MoonRipple = null
var _focus_family: Relic.Family = Relic.Family.NONE
var _full_moon_swings: int = 0
var _full_moon_primed: bool = false
var _starfall_primed: bool = false

var _relic_haste: float = 1.0

## Current moon-arrow stats. Relics grow these.
var _arrow_cooldown: float = ARROW_COOLDOWN
var _arrow_count: int = 1
var _arrow_pierce: int = 1
var _arrow_damage: int = ARROW_BASE_HIT
var _arrow_timer: float = 0.6
## Park the leftover shot of an even-count volley on alternating sides. Center shot always stays.
var _arrow_fan_side: float = 1.0
## Missile power from kill cores. Separate from relic cards so the first upgrade timing is fixed.
var _missile_power: int = 0
var _missile_progress: int = 0
## Store capture has pinned HUD numbers. Only on the debug capture path.
var _capture_progress_frozen: bool = false
## Spawning the first core on the floor is not the same as collecting it. Miss it and the first
## 2-kill threshold is reused; only after pickup does the next-rank curve begin.
var _first_missile_core_collected: bool = false
var _regular_cores_outstanding: int = 0
## Progress actually deducted when spawning a floor regular core. Outstanding ejected cores can change
## the live threshold, so result/continue restore the exact escrow instead of recomputing.
var _regular_core_progress_escrow: int = 0
var _ejected_cores_outstanding: int = 0
var _missile_core_help_shown: bool = false
## True only while debug store-capture state is live together with a real ejected core.
## Collect/expire signals immediately discard the proof file and the pinned banner together.
var _debug_missile_capture_active: bool = false
## If the next core quota fills while a floor core sits ignored, place it at this last kill spot.
var _missile_last_kill_at: Vector2 = Room.MAP * 0.5
## Hearts filled only at the first beacon each cycle. Picking `Warm Beacon` sets this to 1.
var _beacon_heal: int = 0
var _beacon_healed_cycle: int = 0

var _room: Room = null

## Time survived. **Counts up, never down.**
##
## A 90s countdown was this game's biggest chain. Put an end clock on an endlessly growing run
## and the run ends before growth starts.
var _survived: float = 0.0

## Level and kills left to the next one.
##
## Dropped "relics only after three beacons." Three picks and stop is not endless growth.
## **Kills raise level, and each level picks one relic.** No end.
var _level: int = 1
var _to_next: int = LEVEL_FIRST
var _level_progress: int = 0

## Kill streak and time left on it.
var _combo: int = 0
var _combo_left: float = 0.0
var _combo_tier: int = 0
## Embers picked up on the field, and awakening time left.
var _moonfire_charge: float = 0.0
var _moonfire_left: float = 0.0
var _moonfire_on: bool = false
## After the third beacon lights, stays on until the guardian falls.
var _moonfire_locked: bool = false
## Brief tip for the first moon ember only. Once per run is enough to learn the loop.
var _ember_help_shown: bool = false
## Embers to attach after leaving the physics callback. Multi-kills in one frame still count to the node cap.
var _pending_embers: int = 0
## Do not instance dozens of Ember scenes from one physics tick's AoE kills — queue positions and
## attach four per render frame.
var _ember_positions: Array[Vector2] = []
var _ember_elites: Array[bool] = []
## Flag to show the next-cycle guide after the guardian loot pick.
var _cycle_reward_pending: bool = false
var _cycle_reward_queued: bool = false
var _cycle_reward_grant_count: int = 1
var _cycle_decision_queued: bool = false
var _completed_cycle: int = 0
var _completed_cycle_overcharges: int = 0
## A beacon waiting for the post-charge choice is not the same as one under defense after the pick.
## The first is a paused modal; the second is a live world state with combat flowing.
var _pending_beacon_choice: Node2D = null
var _overcharge_beacon: Node2D = null
var _overcharge_progress: float = 0.0
var _overcharge_abandon_left: float = 0.0
var _overcharge_second_wave_sent: bool = false
var _overcharge_successes: int = 0
## Analytics uses a per-run temp ID only. Without consent or a configured key every call is an
## immediate no-op and never waits on combat.
var _analytics_run_id: String = ""
var _analytics_run_eligible: bool = false
var _analytics_guardian_started_ms: int = 0
var _analytics_overcharge_started_ms: int = 0
var _analytics_total_beacons: int = 0
var _analytics_guardians: int = 0
var _analytics_continues: int = 0
var _analytics_tutorial_steps: Dictionary = {}
var _analytics_run_end_reason: String = ""
var _analytics_run_end_tracked: bool = false
## Shards already paid on the defeat screen. When continue re-settles the same cumulative score,
## grant only the delta to the target shard total so one run's score is not rewarded twice.
var _run_shards_awarded: int = 0
## If result save fails briefly, retry before leaving the run. The side that saved drops out of
## pending, so a stuck other side cannot duplicate shards or a new record.
var _run_settlement_pending: bool = false
var _pending_run_settlement_score: int = 0
var _record_submission_pending: bool = false
var _pending_record_score: int = 0
var _pending_record_rank: String = "D"
var _analytics_consent_prompt_shown: bool = false
## Regression tests alone replay the release first-result consent flow. Normal debug and store
## capture have no caller that sets this, so the consent panel never opens.
var _debug_allow_analytics_consent_prompt: bool = false
## Ignore input for the one frame Android back opens the title.
var _leaving_for_title: bool = false
## Run seed. Room layout comes from this. The forest changes every run.
var _run_seed: int = 0
## Teach only the first run's three actions briefly. Do not block start behind a separate how-to screen.
var _tutorial_step: int = 0
var _tutorial_origin: Vector2 = Vector2.ZERO
## First run? Show concept tips once, only for first-time players.
##
## Kept apart from `_tutorial_step`. That one is the linear move→dash→beacon ladder, and the
## capture contract treats `>= 4` as "tips done." Adding steps here would break
## that contract.
## How long first-learn copy stays on screen. Combat banners at 1.5s vanish before they can be
## read.
const STORE_CAPTURE_BOOT: Script = preload(
	"res://scripts/dev/store_capture_boot.gd")
const ONBOARD_HOLD: float = 3.6
const BEACON_HINT_RADIUS: float = 104.0
var _onboarding: bool = false
var _onboarded: Dictionary = {}
## Single screen-shake state so stacked kills do not each spawn a Tween.
var _shake_power: float = 0.0
var _shake_left: float = 0.0
var _shake_step_left: float = 0.0
var _combat_hud_queued: bool = false


func _ready() -> void:
	_camera.zoom = Vector2.ONE * WORLD_CAMERA_ZOOM
	get_viewport().size_changed.connect(_recenter)
	_recenter()

	# Start the first run bright too. Bgm is autoplay, so only pitch is applied here.
	_bgm.pitch_scale = _arena_bgm_pitch()

	# Hero lines appear as a dialogue-style strip at the bottom. The old balloon floated over the
	# player's head, and because the camera follows the player it **always covered the hero** —
	# all three store screenshots went out that way. Built in code, not a scene file, so it also
	# follows the reduced arenas capture and tests use.
	_voice.reset()
	_voice_panel = VOICE_PANEL.new()
	var ui_layer: CanvasLayer = get_node_or_null("Ui") as CanvasLayer
	if ui_layer != null:
		ui_layer.add_child(_voice_panel)
		ui_layer.move_child(_voice_panel, _dialogue.get_index())

	_capture_run_hero()
	# Art comes from the same chosen Hero as the stats. Build eight animations from each of the six
	# heroes' dedicated 48x64 sheets; a bad resource leaves Player's custom Warden.
	_player.apply_hero_visual(_hero_for_run())

	# The forest changes every run. Until now there was not a single seed line, so
	# every run was literally identical.
	_run_seed = randi()
	_rooms_root.modulate = Color.WHITE
	_change_world(false)
	_player.set_bounds(Room.PLAY)
	# Start at map center. Stay far from all three beacons so none light on their own.
	_player.position = Room.MAP * 0.5
	_player.reset_physics_interpolation()

	for beacon in _beacons:
		# Debug buttons find these. Cycle checks need all three beacons lit immediately.
		beacon.add_to_group("beacons")
		beacon.lit_changed.connect(_on_beacon_lit_changed)
		beacon.charge_changed.connect(_on_beacon_charge_changed)
		beacon.charge_completed.connect(_on_beacon_charge_completed)
	_place_beacons()
	_gate.entered.connect(_on_gate_entered)

	# If the first fight waits 20s, the first upgrade is late too. The first three spirits start just
	# inside the screen rim, then spawning moves to the large map's edges.
	_spirit.position = _room.nearest_clear(
		_room.clamp_to_play(_player.position + Vector2(244, -78)), 10.0)
	_spirit.reset_physics_interpolation()
	_register_spirit(_spirit)
	_summon(_room.nearest_clear(
		_room.clamp_to_play(_player.position + Vector2(178, -18)), 10.0),
		"res://resources/wisp.tres", 0.5)
	_summon(_room.nearest_clear(
		_room.clamp_to_play(_player.position + Vector2(218, 72)), 10.0),
		"res://resources/wisp.tres", 0.5)
	_gate.close()
	_result.restart_requested.connect(_on_result_dismissed.bind(ResultAction.RESTART))
	_result.shrine_requested.connect(_on_result_dismissed.bind(ResultAction.SHRINE))
	_result.continue_requested.connect(_on_continue_requested)
	_result.continue_purchase_requested.connect(_on_continue_purchase_requested)
	_result.record_requested.connect(_on_result_record)
	_result.reveal_finished.connect(_on_result_reveal_finished)
	_analytics_consent.decided.connect(_on_analytics_consent_decided)
	_analytics_consent.dismissed.connect(_on_analytics_consent_dismissed)
	_bind_analytics_consent_lifecycle()
	_ladder.closed.connect(_on_ladder_closed)
	_pause.restart_requested.connect(_restart)
	_pause.settings_requested.connect(_open_settings)
	_pause.title_requested.connect(_return_to_title)
	_pause.pause_changed.connect(_hud.set_banner_suppressed)
	_settings.credits_requested.connect(_open_credits)
	_settings.closed.connect(_on_settings_closed)
	_credits.closed.connect(_settings.open)
	_dash_button.pressed.connect(_on_dash_pressed)
	_relic.picked.connect(_on_relic_picked)
	_relic.banner_cleared.connect(_hud.clear_banner)
	_run_choice.chosen.connect(_on_run_choice_made)

	# Build heart cells first, then fill them. Reverse the order and nothing draws — there are no cells.
	_hud.set_max_health(_max_health)
	_hud.set_health(_health)
	_hud.set_beacons(0, _beacons.size())
	_hud.set_survived(_survived)
	_hud.set_moonfire(0.0, false, false)
	_hud.set_evolution(Relic.Family.NONE, 0, 0)
	_refresh_missile_hud()

	Analytics.activate()
	_analytics_begin_run()
	_apply_boons()
	_apply_test_boost()
	_refresh_evolution_hud()
	_tutorial_origin = _player.position
	_begin_tutorial.call_deferred()


## Read the current Vault pick only when opening the run. Later refunds, unlocks, and re-picks
## update meta progress immediately but do not change rules or records of a fight already started.
func _capture_run_hero() -> void:
	# Debug device runs compare all six heroes' combat signatures immediately without touching the
	# purchase ledger or Vault save. Release builds neither read nor delete the request file, so they
	# cannot bypass real purchase entitlement.
	var test_path: String = TEST_HERO_REQUEST.take(OS.is_debug_build())
	var test_hero: Hero = load(test_path) as Hero if not test_path.is_empty() else null
	if test_hero != null:
		_run_hero_path = test_path
		_run_hero = test_hero
		return
	_run_hero_path = Vault.hero_path()
	_run_hero = Vault.hero()
	# If Vault fell back to the default hero from a corrupt save or missing resource, align the ladder
	# path with the resource actually used.
	if _run_hero != null and _run_hero.resource_path in Vault.HEROES:
		_run_hero_path = _run_hero.resource_path


func _hero_for_run() -> Hero:
	if _run_hero == null:
		_capture_run_hero()
	return _run_hero


func _hero_path_for_run() -> String:
	if _run_hero_path.is_empty():
		_capture_run_hero()
	return _run_hero_path


func _analytics_begin_run() -> void:
	var analytics_enabled: bool = Analytics.enabled()
	_analytics_run_eligible = false
	_analytics_run_id = Analytics.new_run_id()
	if not analytics_enabled:
		return
	var boon_tier: int = 0
	for value in Vault.ranks.values():
		boon_tier += maxi(int(value), 0)
	# Collect follow-up events only for runs whose start actually landed in the atomic queue.
	# Keeping a failed start produces orphan events with no run_started — gone from the funnel while
	# still occupying the queue.
	_analytics_run_eligible = Analytics.track("run_started", {
		"hero": _analytics_resource_id(_hero_path_for_run()),
		"boon_tier": mini(boon_tier, 100),
	}, _analytics_run_id)


func _bind_analytics_consent_lifecycle() -> void:
	var callback: Callable = Callable(self, "_on_analytics_settings_changed")
	if not Settings.changed.is_connected(callback):
		Settings.changed.connect(callback)


func _on_analytics_settings_changed() -> void:
	if Settings.analytics_consent == Settings.AnalyticsConsent.GRANTED:
		return
	# Revoke does not stop at clearing the Analytics queue. Permanently close this Arena run too so
	# re-consent cannot revive follow-up events under the old run_id.
	_analytics_run_eligible = false
	_analytics_run_id = ""


## Ask for consent only after the first result's numbers and rank are all revealed.
##
## Consenting early on a build missing the config key makes later updates look like collection
## started without notice. So only release builds that also have real transport config qualify.
func _on_result_reveal_finished() -> void:
	if not _should_prompt_analytics_consent():
		return
	_analytics_consent_prompt_shown = true
	_result.set_overlay_blocked(true)
	_analytics_consent.open()


func _should_prompt_analytics_consent() -> bool:
	if not _over or not _result.visible or _analytics_consent_prompt_shown:
		return false
	if Settings.analytics_consent != Settings.AnalyticsConsent.UNKNOWN:
		return false
	if not Analytics.configured():
		return false
	if OS.is_debug_build():
		if not _debug_allow_analytics_consent_prompt:
			return false
		# Even with the regression-test override on, a real store-capture request and locked framing win.
		if not STORE_CAPTURE_BOOT.read_request().is_empty() \
				or _debug_guardian_capture_active \
				or _debug_hero_direction_capture_active \
				or _debug_missile_capture_active:
			return false
	return true


func _on_analytics_consent_decided(granted: bool) -> void:
	Settings.set_analytics_consent(
		Settings.AnalyticsConsent.GRANTED if granted \
		else Settings.AnalyticsConsent.DENIED)
	_result.set_overlay_blocked(false)
	# Do not backfill the run that just ended. After consent, only mark app activation and record
	# game events from the next run under a new run_id.
	if granted:
		Analytics.activate()


func _on_analytics_consent_dismissed() -> void:
	_result.set_overlay_blocked(false)


func _close_analytics_consent_without_choice() -> void:
	if _analytics_consent.visible:
		_analytics_consent.close_without_choice()


## Test-only door that verifies the release branch offline. Weaker than store capture.
func debug_allow_analytics_consent_prompt_for_test() -> void:
	if OS.is_debug_build():
		_debug_allow_analytics_consent_prompt = true


func _analytics_resource_id(path: String) -> String:
	return path.get_file().get_basename().to_lower()


func _analytics_family_id(family: Relic.Family) -> String:
	match family:
		Relic.Family.STARFALL:
			return "starfall"
		Relic.Family.FULL_MOON:
			return "full_moon"
		Relic.Family.MOON_DANCE:
			return "moon_dance"
		_:
			return "support"


func _analytics_terrain_id() -> String:
	match _encounter_kind():
		RoomKind.Encounter.CROSSFIRE:
			return "field"
		RoomKind.Encounter.CARAVAN:
			return "camp"
		_:
			return "forest"


func _analytics_elapsed_ms() -> int:
	return clampi(roundi(_survived * 1000.0), 0, 7 * 24 * 60 * 60 * 1000)


func _analytics_track(event_name: String, properties: Dictionary = {}) -> void:
	if _analytics_run_eligible:
		Analytics.track(event_name, properties, _analytics_run_id)


func _analytics_track_overcharge_resolution(
		outcome: String, reward: String = "none") -> void:
	_analytics_track("overcharge_resolved", {
		"outcome": outcome,
		"terrain": _analytics_terrain_id(),
		"cycle": _cycle,
		"duration_ms": maxi(
			_analytics_elapsed_ms() - _analytics_overcharge_started_ms, 0),
		"reward": reward,
	})


func _analytics_tutorial_step(step: String) -> void:
	if _analytics_tutorial_steps.get(step, false):
		return
	_analytics_tutorial_steps[step] = true
	if not _analytics_run_eligible:
		return
	_analytics_track("tutorial_step_completed", {
		"step": step,
		"elapsed_ms": _analytics_elapsed_ms(),
	})


func _analytics_track_run_end(reason: String, score_total: int = -1) -> bool:
	if _analytics_run_end_tracked:
		return false
	if not _analytics_run_eligible:
		return false
	var total: int = score_total
	if total < 0:
		var score: Score = Score.new()
		score.cycles = maxi(_cycle - 1, 0)
		score.beacons = _lit_count
		score.survived = _survived
		score.level = _level
		score.kills = _kill_score
		total = score.total()
	if not Analytics.track("run_ended", {
		"reason": reason,
		"cycle": maxi(_cycle - 1, 0),
		"duration_ms": _analytics_elapsed_ms(),
		"score": maxi(total, 0),
		"kills": _kills,
		"beacons": _analytics_total_beacons,
		"guardians": _analytics_guardians,
		"relics": _taken.size(),
		"continues": _analytics_continues,
	}, _analytics_run_id):
		return false
	# Close only after the atomic queue save succeeds. On failure, `_exit_tree()` after restart/title
	# can retry with the same run_id and deterministic queue id.
	_analytics_run_end_tracked = true
	return true


## Apply permanent upgrades stored in the vault at run start.
##
## **Something must survive death or players will not come back.** Until now only a high score
## remained, so a good 30-minute run still opened the next one bare at level 1.
##
## Grace only nudges the starting line forward. Each grace has a tier ceiling so long-time players
## are not invincible from the opening — that would make the game **vanish for that player
## alone.**
## **Base values** from character and grace. The starting line before relics.
##
## Called by **both** `_apply_boons()` and `_recompute()`. Splitting them caused a serious bug —
## `_recompute()` reset stats to `Player.DEFAULT_*` and re-applied only relics. Character multipliers
## and grace vanished on the spot.
##
## So **on the first hit, Keeper became Warden.** A character unlocked for 140 shards snapped back
## to the default the moment one relic dropped. Nothing on screen showed it.
##
## Hearts and opening relics are not here. Those happen **once** when the run opens; doing them
## again in recompute would heal and duplicate relics.
func _base_stats() -> void:
	var hero: Hero = _hero_for_run()
	_player.speed = Player.DEFAULT_SPEED * hero.speed_scale \
		+ Vault.grace(Boon.Grace.START_SPEED)
	_player.dash_cooldown_time = Player.DEFAULT_DASH_COOLDOWN * hero.dash_scale
	_damage_mult *= hero.damage_scale * (1.0 + Vault.grace(Boon.Grace.START_DAMAGE))
	_arrow_mult *= hero.damage_scale * (1.0 + Vault.grace(Boon.Grace.START_DAMAGE))
	_dew_multiplier *= 1.0 + Vault.grace(Boon.Grace.DEW_LUCK)


func _apply_boons() -> void:
	# Character first; grace stacks on top —
	# reverse the order and the multipliers overwrite each other, wiping Keeper's damage bonus.
	var hero: Hero = _hero_for_run()
	_max_health = mini(
		hero.health + int(Vault.grace(Boon.Grace.START_HEALTH)),
		MAX_HEALTH_LIMIT)
	_hud.set_max_health(_max_health)
	_health = _max_health

	_base_stats()
	_settle_rates()

	# Start holding the character's fixed relics. **This splits characters the most** —
	# same map, same spirits, but opening with orbiting orbs versus a spreading ripple is a
	# different game.
	for path in hero.opening:
		_on_relic_picked(_relic.take_named(path), false, "opening")

	# Grace picks are random among survival/move relics. Handing out up to two attack relics
	# lets long-played saves skip early weapon-growth steps.
	for i in int(Vault.grace(Boon.Grace.START_RELIC)):
		_on_relic_picked(_relic.take_random_support(), false, "opening")


## If entered via a test button, build that state. Debug builds only.
##
## **Late game cannot be fixed if it cannot be opened.** Auto input cannot dodge and dies in
## about a minute; a human playing 20 minutes means 20 minutes per number change.
## Pre-grant relics here and the level-40 screen appears in one second.
func _apply_test_boost() -> void:
	var boost: Array = TestLauncher.take_boost(get_tree())
	if boost.size() < 2:
		return

	_cycle = maxi(int(boost[1]), 1)
	_hud.set_cycle(_cycle)
	# The test cycle is applied after the room is built, so terrain must be realigned too.
	# Without this line, the `cycle 3` button still leaves the first cycle's night forest.
	_change_world(false)
	# Beacon candidates must be checked against the new structure list after the room changes.
	_place_beacons()

	# Push survived time too. **Skip this and the test lies** —
	# spawn interval and spirit kinds are all driven by `_survived`, so entering cycle 5 at 0
	# gives early density where enemies walk in one by one.
	# We almost judged that state as late game and decided "DPS is weak."
	_survived = 60.0 * float(_cycle)
	_hud.set_survived(_survived)

	# Feed the same stress build for the level. Random means one run is a light survival kit and
	# the next is max meteor fire — before/after numbers cannot compare.
	var want: int = maxi(int(boost[0]), 1)
	for i in want - 1:
		var path: String = TEST_STRESS_RELICS[i % TEST_STRESS_RELICS.size()]
		_on_relic_picked(_relic.take_named(path), false)
	_level = want
	# Change only the level number and leave the threshold at 3, and the first three kills open the
	# Lv21 panel and freeze the late-game perf dashboard. That value made us mistake a test peak for a
	# game bottleneck. Grow the threshold the same number of times as reaching the target level.
	_to_next = LEVEL_FIRST
	for i in want - 1:
		_to_next = mini(int(ceil(float(_to_next) * LEVEL_GROWTH)), LEVEL_CAP)
	_level_progress = 0
	_hud.set_level(_level)
	_hud.set_level_progress(0.0)
	_missile_power = MissileProgression.MAX_POWER
	_missile_progress = 0
	_first_missile_core_collected = true
	_refresh_missile_hud()

	# Fill enemies too.
	#
	# **Skip this and there is nothing to measure DPS on.** Spirits walk in from the map rim, so a
	# fresh run's screen is empty. Holding forty relics with nothing to hit was misread as
	# "missiles are not firing." Almost judged that way once.
	#
	# Spawning three packs in one frame stacks SpriteFrames builds for 31 spirits and causes a CPU
	# stall normal play never sees. Keep the combat density, but let them enter with breathing room
	# like a real raid so the numbers represent the game.
	_test_raid()
	for i in range(1, 3):
		get_tree().create_timer(0.8 * float(i), false).timeout.connect(_test_raid)


## Queued test raid. Do not spawn new spirits after the result screen or a scene change.
func _test_raid() -> void:
	if _over or _transitioning or _escape_active or not is_inside_tree():
		return
	_raid()



## Next action chosen on the result screen. Run it immediately.
##
## Even for a ladder-worthy score, **do not ask for a name first.** Pressing retry and hitting
## name entry first turns recording into a toll, not a reward. Open recording only from the
## result screen's dedicated button (RESULT_RECORD).
func _on_result_dismissed(action: ResultAction) -> void:
	_pending_result_action = action
	_finish_result_action()


## Result screen's record button. Opens the ladder panel; closing it returns to results.
func _on_result_record() -> void:
	if not _retry_pending_result_persistence():
		_result.reopen_after_failed_continue()
		return
	# **Always hide the result screen.** The ladder panel's dim is 0.82, so the score breakdown and
	# name field stack on one screen behind it. That is how it actually captured.
	_result.visible = false
	_ladder.ask(
		_board_score,
		_board_rank,
		_board_cycles,
		_hero_path_for_run(),
		_board_run_id(),
	)


## Ladder recording accepts the same final score from the same run only once. Even with analytics
## off, `_analytics_begin_run()` still makes a temp run ID first; reinforce the same boundary here
## for callers that never hit that init, like flow tests that never enter the tree.
func _board_run_id() -> String:
	if _analytics_run_id.is_empty():
		_analytics_run_id = Analytics.new_run_id()
	return _analytics_run_id


## Ladder panel closed. If it was opened from the result record button, return to results and
## take the choice again. (Retry/shrine used to route through recording and resume a pending
## action here — now that path is the record button only.)
func _on_ladder_closed() -> void:
	if _pending_result_action != ResultAction.NONE:
		_finish_result_action()
		return
	_result.reopen_after_failed_continue()


## Closing the ladder does not change the earlier "retry" or "shrine" pick.
func _finish_result_action() -> void:
	if not _retry_pending_result_persistence():
		# Leaving a failed button queued for auto-run means picking record next still jumps to the old
		# destination the moment the ladder closes. Only re-offer the choice.
		_pending_result_action = ResultAction.NONE
		_result.reopen_after_failed_continue()
		return
	var action: ResultAction = _pending_result_action
	_pending_result_action = ResultAction.NONE
	match action:
		ResultAction.SHRINE:
			_return_to_title(true)
		_:
			_restart()


## Handle both persistent results of a finished run at the same boundary. If either fails, keep the
## successful side committed and leave only the failed side pending.
func _persist_finished_result(total_score: int, rank: String) -> bool:
	var record_result: int = _submit_run_record(total_score, rank)
	_settle_run_reward(total_score)
	return record_result == Records.SubmitResult.SAVED


func _settle_run_reward(total_score: int) -> bool:
	var result: Dictionary = _vault_settle_run_score(
		total_score, _run_shards_awarded)
	var status: int = int(result.get(
		"status", Vault.RunSettlementStatus.SAVE_FAILED))
	if status == Vault.RunSettlementStatus.APPLIED:
		var awarded: int = int(result.get("awarded", 0))
		if awarded <= 0:
			_mark_run_settlement_pending(total_score)
			return false
		_run_shards_awarded += awarded
	elif status != Vault.RunSettlementStatus.NO_CHANGE:
		_mark_run_settlement_pending(total_score)
		return false
	_run_settlement_pending = false
	_pending_run_settlement_score = 0
	return true


func _mark_run_settlement_pending(total_score: int) -> void:
	_pending_run_settlement_score = maxi(
		_pending_run_settlement_score, total_score) \
		if _run_settlement_pending else total_score
	_run_settlement_pending = true


func _submit_run_record(total_score: int, rank: String) -> int:
	var result: int = _records_submit_result(total_score, rank)
	if result == Records.SubmitResult.SAVE_FAILED:
		if not _record_submission_pending or total_score >= _pending_record_score:
			_pending_record_score = total_score
			_pending_record_rank = rank
		_record_submission_pending = true
		return result
	_record_submission_pending = false
	_pending_record_score = 0
	_pending_record_rank = "D"
	return result


## Shared retry door for result buttons, recording, continue, and shop travel.
## Attempt both saves so one failure cannot block the other side's recovery.
func _retry_pending_result_persistence() -> bool:
	var awarded_before: int = _run_shards_awarded
	var settlement_ok: bool = true
	if _run_settlement_pending:
		settlement_ok = _settle_run_reward(_pending_run_settlement_score)

	var record_ok: bool = true
	var record_saved: bool = false
	if _record_submission_pending:
		var record_result: int = _submit_run_record(
			_pending_record_score, _pending_record_rank)
		record_ok = record_result != Records.SubmitResult.SAVE_FAILED
		record_saved = record_result == Records.SubmitResult.SAVED

	if _result != null and _result.visible \
			and (record_saved or awarded_before != _run_shards_awarded):
		# Do not replay an already-revealed result; only correct the stored values.
		_result.refresh_persistence(record_saved, _run_shards_awarded)
	return settlement_ok and record_ok


## Small boundary where result-persistence regression tests inject save failure and recovery.
func _vault_settle_run_score(total_score: int, already_awarded: int) -> Dictionary:
	return Vault.settle_run_score(total_score, already_awarded)


func _records_submit_result(total_score: int, rank: String) -> int:
	return Records.submit_result(total_score, rank)


## Called by debug tools. Dying mid-check means starting over, so this is needed.
func debug_heal() -> void:
	_set_health(_max_health)


## Multiply damage by ten. **Called by debug-build-only tools.**
func debug_boost_damage() -> void:
	_damage_mult *= 10.0
	_arrow_mult *= 10.0
	_settle_rates()


## Toggle invulnerability and return the new state. **Called by debug-build-only tools.**
func debug_shield() -> bool:
	_shielded = not _shielded
	return _shielded


## Instantly act as if ten moon embers were picked up. Check the new combat loop's VFX and numbers.
func debug_awaken() -> void:
	_moonfire_charge = MOONFIRE_MAX
	_activate_moonfire(false)


## Walk hit → missile-power eject → recover without waiting on the live path.
func debug_take_hit() -> void:
	var capture_requested: bool = _consume_debug_missile_capture_request()
	var missile_power_before: int = _missile_power
	_invulnerable = 0.0
	_on_player_hit(_player.position + Vector2.RIGHT * 24.0)
	if capture_requested:
		# **No further hits after this one.** Capture requires "exactly one ejected core," but after
		# pack-unit spawning the short i-frames ended and a second hit landed, making two cores. iPad's
		# slower round-trip hits this especially often. Hold i-frames longer only for the
		# capture window.
		_invulnerable = 600.0
		# Publish state only after _spawn_missile_core() has deferred the real node attach. The file's
		# presence then proves an orange core is also on screen.
		_publish_debug_missile_capture.call_deferred(missile_power_before)


func _consume_debug_missile_capture_request() -> bool:
	if not OS.is_debug_build() \
			or not FileAccess.file_exists(DEBUG_MISSILE_CAPTURE_REQUEST_PATH):
		return false
	# CoreDevice appDataContainer supports overwrite but has no delete API.
	# Do not consume a host `{}` disarm trace as a real hit request.
	if FileAccess.get_file_as_string(
			DEBUG_MISSILE_CAPTURE_REQUEST_PATH).strip_edges() == "{}":
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(
		DEBUG_MISSILE_CAPTURE_REQUEST_PATH)) == OK


## Shot 03 proves "a core is present" with a real Sprite, not a counter.
## Tests also mutate this snapshot directly to reject hidden, transparent, off-screen, or wrong textures.
func _debug_missile_core_capture_visual_state() -> Dictionary:
	if not OS.is_debug_build() or not is_inside_tree():
		return {}
	var ejected_cores: Array[Node] = []
	for candidate in get_tree().get_nodes_in_group("missile_cores"):
		if is_instance_valid(candidate) \
				and not candidate.is_queued_for_deletion() \
				and bool(candidate.get("ejected")):
			ejected_cores.append(candidate)
	var state: Dictionary = {
		"ejected_core_count": ejected_cores.size(),
		"core_visible_in_tree": false,
		"core_effective_alpha": 0.0,
		"core_opaque": false,
		"core_onscreen": false,
		"core_texture_path": "",
		"core_texture_matches": false,
		"core_visible_draw_rect_positive": false,
		"ready": false,
	}
	if ejected_cores.size() != 1:
		return state
	var core: CanvasItem = ejected_cores[0] as CanvasItem
	var sprite: Sprite2D = ejected_cores[0].get_node_or_null("Sprite") as Sprite2D
	if core == null or sprite == null:
		return state
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var core_visible_in_tree: bool = core.is_visible_in_tree() \
		and sprite.is_visible_in_tree()
	var core_effective_alpha: float = _debug_effective_canvas_alpha(sprite)
	var core_opaque: bool = core_effective_alpha >= 0.99
	var core_onscreen: bool = viewport_rect.has_point(
		core.get_global_transform_with_canvas().origin)
	var core_texture_path: String = str(sprite.texture.resource_path) \
		if sprite.texture != null else ""
	var core_texture_matches: bool = sprite.texture == MISSILE_CORE_TEXTURE \
		and core_texture_path == MISSILE_CORE_TEXTURE_PATH
	var sprite_rect: Rect2 = sprite.get_rect()
	var visible_draw_rect_positive: bool = sprite.texture != null \
		and sprite_rect.has_area() \
		and _debug_canvas_rect(sprite, sprite_rect).intersection(
			viewport_rect).has_area()
	state.merge({
		"core_visible_in_tree": core_visible_in_tree,
		"core_effective_alpha": core_effective_alpha,
		"core_opaque": core_opaque,
		"core_onscreen": core_onscreen,
		"core_texture_path": core_texture_path,
		"core_texture_matches": core_texture_matches,
		"core_visible_draw_rect_positive": visible_draw_rect_positive,
		"ready": core_visible_in_tree and core_opaque and core_onscreen \
			and core_texture_matches and visible_draw_rect_positive,
	}, true)
	return state


func _debug_effective_canvas_alpha(item: CanvasItem) -> float:
	var alpha: float = 1.0
	var current: CanvasItem = item
	var own_item: bool = true
	while current != null:
		alpha *= current.modulate.a
		if own_item:
			alpha *= current.self_modulate.a
		own_item = false
		current = current.get_parent() as CanvasItem
	return alpha


func _debug_canvas_rect(item: CanvasItem, local_rect: Rect2) -> Rect2:
	var canvas_transform: Transform2D = item.get_global_transform_with_canvas()
	var top_left: Vector2 = canvas_transform * local_rect.position
	var top_right: Vector2 = canvas_transform * Vector2(
		local_rect.end.x, local_rect.position.y)
	var bottom_left: Vector2 = canvas_transform * Vector2(
		local_rect.position.x, local_rect.end.y)
	var bottom_right: Vector2 = canvas_transform * local_rect.end
	var minimum := Vector2(
		minf(minf(top_left.x, top_right.x), minf(bottom_left.x, bottom_right.x)),
		minf(minf(top_left.y, top_right.y), minf(bottom_left.y, bottom_right.y)))
	var maximum := Vector2(
		maxf(maxf(top_left.x, top_right.x), maxf(bottom_left.x, bottom_right.x)),
		maxf(maxf(top_left.y, top_right.y), maxf(bottom_left.y, bottom_right.y)))
	return Rect2(minimum, maximum - minimum)


func _publish_debug_missile_capture(missile_power_before: int) -> void:
	if not OS.is_debug_build() \
			or _over \
			or not is_inside_tree() \
			or _missile_power != missile_power_before - 1 \
			or _ejected_cores_outstanding != 1:
		return
	var core_visual_before_pause: Dictionary = \
		_debug_missile_core_capture_visual_state()
	if not bool(core_visual_before_pause.get("ready", false)):
		return
	var terrain_path: String = str(_room.kind.resource_path) \
		if is_instance_valid(_room) and _room.kind != null else ""
	var world_key: String = str(_world_step().get("name", ""))
	var time_step: Dictionary = _time_step()
	var time_key: String = str(time_step.get("name", ""))
	var expected_tone: Color = time_step.get("tone", Color.TRANSPARENT)
	var applied_tone: Color = _rooms_root.modulate
	var time_tone_applied: bool = applied_tone.is_equal_approx(expected_tone)
	# 03 is an ad shot of the night forest at Lv10 · cycle 1. Pin real Arena state too so the same
	# banner and core on another preset or terrain cannot pass.
	if _level != 10 or _cycle != 1 or _zone_index != 0 \
			or terrain_path != "res://resources/rooms/forest.tres" \
			or world_key != "WORLD_FOREST" or _lit_count != 0 \
			or time_key != "TIME_NIGHT" or not time_tone_applied \
			or _transitioning or _escape_active:
		return

	var expected_text: String = tr("MISSILE_DROPPED") % [
		missile_power_before, _missile_power]
	_hud.debug_lock_capture_banner(
		expected_text, Color(1.0, 0.58, 0.42, 1))
	var banner: Dictionary = _hud.debug_capture_banner_snapshot()
	# Publishing the state file first lets the host read JSON before cores are paused.
	# Write core_capture_paused=true only after every real ejected core is paused.
	for core in get_tree().get_nodes_in_group("missile_cores"):
		if is_instance_valid(core) \
				and not core.is_queued_for_deletion() \
				and bool(core.get("ejected")) \
			and core.has_method("set_transition_paused"):
			core.set_transition_paused(true)
	# Even if pause regresses into hiding nodes or changing transforms, do not publish the previous
	# snapshot. Stop every motion source, then re-read the live sprites.
	var core_visual: Dictionary = _debug_missile_core_capture_visual_state()
	if not bool(core_visual.get("ready", false)):
		for core in get_tree().get_nodes_in_group("missile_cores"):
			if is_instance_valid(core) \
					and not core.is_queued_for_deletion() \
					and bool(core.get("ejected")) \
					and core.has_method("set_transition_paused"):
				core.set_transition_paused(false)
		_hud.debug_unlock_capture_banner()
		return
	var published: bool = _write_debug_missile_capture_state({
		"schema": 1,
		"kind": "missile_core_recovery",
		"scene": "arena",
		"over": _over,
		"game_locale": TranslationServer.get_locale(),
		"level": _level,
		"cycle": _cycle,
		"zone_index": _zone_index,
		"terrain_path": terrain_path,
		"world_key": world_key,
		"lit_beacons": _lit_count,
		"transitioning": _transitioning,
		"escape_active": _escape_active,
		"time_key": time_key,
		"time_tone": _debug_color_array(expected_tone),
		"applied_time_tone": _debug_color_array(applied_tone),
		"time_tone_applied": time_tone_applied,
		"banner_key": "MISSILE_DROPPED",
		"expected_banner_text": expected_text,
		"actual_banner_text": str(banner.get("text", "")),
		"banner_visible": bool(banner.get("visible", false)),
		"banner_locked": bool(banner.get("locked", false)),
		"missile_power_before": missile_power_before,
		"missile_power_after": _missile_power,
		"ejected_cores_outstanding": _ejected_cores_outstanding,
		"ejected_core_count": int(core_visual.get("ejected_core_count", 0)),
		"core_visible_in_tree": bool(core_visual.get(
			"core_visible_in_tree", false)),
		"core_effective_alpha": float(core_visual.get(
			"core_effective_alpha", 0.0)),
		"core_opaque": bool(core_visual.get("core_opaque", false)),
		"core_onscreen": bool(core_visual.get("core_onscreen", false)),
		"core_texture_path": str(core_visual.get("core_texture_path", "")),
		"core_texture_matches": bool(core_visual.get(
			"core_texture_matches", false)),
		"core_visible_draw_rect_positive": bool(core_visual.get(
			"core_visible_draw_rect_positive", false)),
		"core_capture_paused": true,
	})
	_debug_missile_capture_active = published
	if not published:
		for core in get_tree().get_nodes_in_group("missile_cores"):
			if is_instance_valid(core) \
					and not core.is_queued_for_deletion() \
					and bool(core.get("ejected")) \
					and core.has_method("set_transition_paused"):
				core.set_transition_paused(false)
		_hud.debug_unlock_capture_banner()


func _write_debug_missile_capture_state(state: Dictionary) -> bool:
	var encoded: String = JSON.stringify(state)
	var output: FileAccess = FileAccess.open(
		DEBUG_MISSILE_CAPTURE_TEMP_PATH, FileAccess.WRITE)
	if output == null or not output.store_string(encoded):
		if output != null:
			output.close()
		return false
	output.flush()
	var write_error: Error = output.get_error()
	output.close()
	if write_error != OK \
			or FileAccess.get_file_as_string(DEBUG_MISSILE_CAPTURE_TEMP_PATH) != encoded:
		return false
	if FileAccess.file_exists(DEBUG_MISSILE_CAPTURE_STATE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(
			DEBUG_MISSILE_CAPTURE_STATE_PATH))
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(DEBUG_MISSILE_CAPTURE_TEMP_PATH),
		ProjectSettings.globalize_path(DEBUG_MISSILE_CAPTURE_STATE_PATH)) == OK


func _invalidate_debug_missile_capture() -> void:
	if not _debug_missile_capture_active:
		return
	_debug_missile_capture_active = false
	for path in [DEBUG_MISSILE_CAPTURE_STATE_PATH, DEBUG_MISSILE_CAPTURE_TEMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if is_instance_valid(_hud):
		_hud.debug_unlock_capture_banner()


## Do not leave proof of a previous live core when the scene changes without ending the run.
func _exit_tree() -> void:
	_invalidate_debug_missile_capture()
	if _overcharge_beacon != null:
		# Close unfinished defense so app exit or scene swap also drops out of the choice denominator.
		_analytics_track_overcharge_resolution("abandoned")
		_overcharge_beacon = null
	if not _analytics_run_end_tracked:
		_analytics_track_run_end(
			_analytics_run_end_reason if not _analytics_run_end_reason.is_empty() else "quit")


## Raise the moon wheel one rank. Compare base → afterglow → meteor shower without waiting.
func debug_upgrade_disc() -> void:
	_on_relic_picked(_relic.take_next_disc())


func debug_upgrade_full_moon() -> void:
	_on_relic_picked(_relic.take_next_family(Relic.Family.FULL_MOON))


func debug_upgrade_moon_dance() -> void:
	_on_relic_picked(_relic.take_next_family(Relic.Family.MOON_DANCE))


## Light only this terrain's beacons. Lighting a hidden next-terrain beacon directly breaks travel state.
func debug_light_next_beacon() -> void:
	if _over or _transitioning or _lit_count >= _beacons.size():
		return
	var beacon: Node2D = _beacons[clampi(_zone_index, 0, _beacons.size() - 1)]
	if not beacon.lit:
		beacon.ignite()


## Walk beacon→gate→next terrain three times on the real state machine to reach the guardian.
func debug_complete_route() -> void:
	if _over or _transitioning:
		return
	while _lit_count < _beacons.size() and not _over:
		debug_light_next_beacon()
		await get_tree().create_timer(0.08, false).timeout
		if _escape_active:
			_on_gate_entered()
			while _transitioning and is_inside_tree():
				await get_tree().process_frame


## For device review, keep the summoned guardian's body and pattern on screen.
##
## Live play's `_summon_guardian()` must always use the farthest point. Only this debug entry
## moves position; terrain guardian resources, HP, and behavior stay untouched.
func debug_stage_guardian() -> void:
	if not OS.is_debug_build() or _guardian == null \
			or not is_instance_valid(_guardian) or not is_instance_valid(_room) \
			or _over:
		return
	var radius: float = float(_guardian.terrain_radius()) \
		if _guardian.has_method("terrain_radius") else 14.0
	var staged: Vector2 = _debug_guardian_capture_target()
	_guardian.position = _room.nearest_clear(staged, radius)
	_guardian.set("velocity", Vector2.ZERO)
	_guardian.reset_physics_interpolation()


func _debug_guardian_capture_target() -> Vector2:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var player_canvas: Vector2 = _player.get_global_transform_with_canvas().origin
	var target_x_fraction: float = GUARDIAN_CAPTURE_TARGET_RIGHT_X \
		if player_canvas.x <= viewport_rect.get_center().x \
		else GUARDIAN_CAPTURE_TARGET_LEFT_X
	var target_canvas: Vector2 = viewport_rect.position + Vector2(
		viewport_rect.size.x * target_x_fraction,
		viewport_rect.size.y * GUARDIAN_CAPTURE_TARGET_Y)
	var target_global: Vector2 = get_viewport().get_canvas_transform().affine_inverse() \
		* target_canvas
	return to_local(target_global)


func _debug_hold_guardian_capture() -> void:
	if not OS.is_debug_build() or not _debug_guardian_capture_active:
		return
	debug_stage_guardian()
	# Do not export ready while prior-frame arrows/meteors linger or a new volley covers the guardian.
	# While active, `_process()` below also creates no new auto attacks.
	_clear_friendly_projectiles()


func _debug_queue_free_group(group: StringName) -> void:
	if not OS.is_debug_build():
		return
	for node in get_tree().get_nodes_in_group(group):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()


func _debug_live_group_count(group: StringName) -> int:
	if not OS.is_debug_build():
		return 0
	var count: int = 0
	for node in get_tree().get_nodes_in_group(group):
		# Nodes stay in the real draw tree even after queue_free is reserved. Do not open clean proof
		# until the next frame makes is_inside_tree() false.
		if is_instance_valid(node) and node.is_inside_tree():
			count += 1
	return count


func _debug_hero_direction_pickup_count() -> int:
	var seen: Dictionary = {}
	for group in HERO_DIRECTION_PICKUP_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node) and node.is_inside_tree():
				seen[node.get_instance_id()] = true
	return seen.size()


## Keep a real gameplay scene with no enemies. Do not disable input, Player physics, or Camera2D.
func _debug_hold_hero_direction_capture() -> void:
	if not OS.is_debug_build() or not _debug_hero_direction_capture_active:
		return
	get_tree().paused = false
	_tutorial_step = 4
	_capture_progress_frozen = true
	_shielded = true
	_invulnerable = 2_000_000_000.0
	_raid_queue.clear()
	_raid_spawn_left = 0.0
	_pending_dews = 0
	_pending_embers = 0
	_ember_positions.clear()
	_ember_elites.clear()
	_cycle_reward_pending = false
	_cycle_reward_queued = false
	_relic_offer_queued = false
	_owed = 0
	_combo = 0
	_combo_left = 0.0
	_combo_tier = 0
	_moonfire_charge = 0.0
	_moonfire_left = 0.0
	_moonfire_on = false
	_moonfire_locked = false
	_combat_hud_queued = false
	_escape_active = false
	_escape_waves_spawned = 0
	_gate.close()
	for beacon in _beacons:
		if beacon.lit or beacon.get_charge() > 0.0:
			beacon.reset()
		beacon.freeze()
	_lit_count = 0
	_hud.set_combo(0, 0)
	_hud.set_beacons(0, _beacons.size())
	_hud.set_moonfire(0.0, false, false)
	_hud.clear_missile_recovery()
	_apply_time_tone(false)

	_debug_queue_free_group(&"spirits")
	_debug_queue_free_group(&"hostile_projectiles")
	_debug_queue_free_group(&"friendly_projectiles")
	for group in HERO_DIRECTION_PICKUP_GROUPS:
		_debug_queue_free_group(group)
	_spirits.clear()
	_guardian = null
	_debug_guardian_capture_active = false
	_hud.set_boss(false)

	if _ring != null and is_instance_valid(_ring):
		_ring.set_physics_process(false)
		if not _ring.is_queued_for_deletion():
			_ring.queue_free()
	elif _ring != null:
		_ring = null
	if _ripple != null and is_instance_valid(_ripple):
		_ripple.set_physics_process(false)
		if not _ripple.is_queued_for_deletion():
			_ripple.queue_free()
	elif _ripple != null:
		_ripple = null
	_player.debug_set_direction_capture_vfx_suppressed(true)

	_hud.debug_unlock_capture_banner()
	_hud.set_banner_suppressed(true)
	_pause.set_overlay_visible(false)
	_result.visible = false
	_relic.visible = false
	_settings.visible = false
	_credits.visible = false
	_ladder.visible = false
	_zone_wipe.visible = false
	_compass.visible = false
	if _flash != null and _flash.is_valid():
		_flash.kill()
	_flash = null
	_hit_flash.modulate.a = 0.0
	_stop_shake()


func _debug_hero_direction_visual_state() -> Dictionary:
	var state: Dictionary = {
		"hero_resource_path": _hero_path_for_run(),
		"hero_resource_loaded": false,
		"hero_sprite_node_present": false,
		"hero_sprite_visible_in_tree": false,
		"hero_sprite_effective_alpha": 0.0,
		"hero_sprite_opaque": false,
		"hero_sprite_playing": false,
		"hero_sprite_animation": "",
		"hero_sprite_animation_direction": "",
		"hero_sprite_expected_animation": "",
		"hero_sprite_animation_matches_facing": false,
		"hero_sprite_frame": -1,
		"hero_sprite_frame_count": 0,
		"hero_sprite_frame_texture_present": false,
		"hero_sprite_frame_texture_path": "",
		"hero_sprite_expected_texture_path": "",
		"hero_sprite_frame_texture_matches_resource": false,
		"hero_sprite_draw_rect": [0.0, 0.0, 0.0, 0.0],
		"hero_sprite_draw_rect_fully_inside_viewport": false,
		"hero_sprite_visual_ready": false,
	}
	if not OS.is_debug_build() or not is_instance_valid(_player):
		return state
	var hero: Hero = _hero_for_run()
	var hero_path: String = _hero_path_for_run()
	var sprite: AnimatedSprite2D = _player.get_node_or_null("Sprite") as AnimatedSprite2D
	if hero == null or sprite == null:
		return state
	_player.force_update_transform()
	sprite.force_update_transform()
	var animation: StringName = sprite.animation
	var animation_name: String = str(animation)
	var walking: bool = bool(_player.get("_walking"))
	var facing_index: int = clampi(int(_player.facing), 0, Player.FACING_NAMES.size() - 1)
	var facing_name: String = str(Player.FACING_NAMES[facing_index])
	var expected_animation: String = ("walk_" if walking else "idle_") + facing_name
	var animation_direction: String = animation_name.get_slice("_", 1) \
		if animation_name.contains("_") else ""
	var frame_count: int = sprite.sprite_frames.get_frame_count(animation) \
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(animation) else 0
	var frame_texture: Texture2D = null
	if sprite.sprite_frames != null and frame_count > 0 \
			and sprite.frame >= 0 and sprite.frame < frame_count:
		frame_texture = sprite.sprite_frames.get_frame_texture(animation, sprite.frame)
	var expected_texture: Texture2D = hero.walk_sheet \
		if animation_name.begins_with("walk_") else hero.idle_sheet \
		if animation_name.begins_with("idle_") else null
	var frame_texture_path: String = _debug_texture_source_path(frame_texture)
	var expected_texture_path: String = _debug_texture_source_path(expected_texture)
	var canvas_rect: Rect2 = _debug_canvas_rect(
		sprite, _debug_animated_sprite_draw_rect(sprite, frame_texture)) \
		if frame_texture != null else Rect2()
	var inside_viewport: bool = canvas_rect.has_area() and _debug_rect_fully_inside(
		canvas_rect, get_viewport().get_visible_rect())
	var effective_alpha: float = _debug_effective_canvas_alpha(sprite)
	var resource_loaded: bool = not hero_path.is_empty() \
		and hero.resource_path == hero_path
	var animation_matches: bool = animation_name == expected_animation \
		and animation_direction == facing_name
	var texture_matches: bool = not expected_texture_path.is_empty() \
		and frame_texture_path == expected_texture_path
	var visual_ready: bool = resource_loaded and sprite.is_visible_in_tree() \
		and effective_alpha >= 0.99 and sprite.is_playing() and frame_count > 0 \
		and frame_texture != null and animation_matches and texture_matches \
		and inside_viewport
	state.merge({
		"hero_resource_path": hero_path,
		"hero_resource_loaded": resource_loaded,
		"hero_sprite_node_present": true,
		"hero_sprite_visible_in_tree": sprite.is_visible_in_tree(),
		"hero_sprite_effective_alpha": effective_alpha,
		"hero_sprite_opaque": effective_alpha >= 0.99,
		"hero_sprite_playing": sprite.is_playing(),
		"hero_sprite_animation": animation_name,
		"hero_sprite_animation_direction": animation_direction,
		"hero_sprite_expected_animation": expected_animation,
		"hero_sprite_animation_matches_facing": animation_matches,
		"hero_sprite_frame": sprite.frame,
		"hero_sprite_frame_count": frame_count,
		"hero_sprite_frame_texture_present": frame_texture != null,
		"hero_sprite_frame_texture_path": frame_texture_path,
		"hero_sprite_expected_texture_path": expected_texture_path,
		"hero_sprite_frame_texture_matches_resource": texture_matches,
		"hero_sprite_draw_rect": _debug_rect_values(canvas_rect),
		"hero_sprite_draw_rect_fully_inside_viewport": inside_viewport,
		"hero_sprite_visual_ready": visual_ready,
	}, true)
	return state


func _debug_friendly_projectile_count() -> int:
	var count: int = 0
	for projectile in get_tree().get_nodes_in_group("friendly_projectiles"):
		# Even on the same frame queue_free() is reserved, the node can still sit in the tree and draw
		# list. Do not open proof until the next frame actually removes it.
		if is_instance_valid(projectile):
			count += 1
	return count


func _debug_guardian_capture_focus_rect(viewport_rect: Rect2) -> Rect2:
	return Rect2(
		viewport_rect.position + viewport_rect.size * GUARDIAN_CAPTURE_FOCUS_POSITION,
		viewport_rect.size * GUARDIAN_CAPTURE_FOCUS_SIZE)


func debug_prepare_store_capture(request: Dictionary) -> void:
	if not OS.is_debug_build():
		return
	var kind: String = str(request.get("kind", ""))
	if kind == "hero_direction":
		var request_signature: String = "%s|%s|%s" % [
			str(request.get("nonce", "")),
			str(request.get("hero_resource_path", "")),
			str(request.get("direction", "")),
		]
		if request_signature != _debug_hero_direction_request_signature:
			_debug_hero_direction_request_signature = request_signature
			_debug_hero_direction_clean_frames = 0
			_debug_hero_direction_last_process_frame = -1
		_debug_hero_direction_capture_active = true
		# Do not fake existing progress to 0. Hold stops the later combat clock, the callback guard rejects
		# only new progress, and ready verifies the real Lv/kills/HP below as
		# they are.
		_capture_progress_frozen = true
		_debug_hold_hero_direction_capture()
	elif kind == "moonlight_barrage":
		# This preset really builds missile power 8 but does not turn on moonfire awakening.
		# So do not invent awakening copy — pin the volley-complete line that appears when the real max
		# core is collected. On slow tablets, do not mistake a mid pop-Tween frame for the
		# review master.
		if _missile_power == MissileProgression.MAX_POWER:
			_hud.debug_lock_capture_banner(tr("MISSILE_COMPLETE") % [
				_missile_power, MissileProgression.MAX_POWER],
				Color(1.0, 0.84, 0.42, 1))
	elif kind == "field_guardian":
		# On slow devices the automator's first place request can arrive before the three-beacon terrain
		# transition finishes. Re-place from the frame the guardian actually exists to remove the race
		# where summon succeeds but the body stays off-screen.
		_debug_guardian_capture_active = true
		_debug_hold_guardian_capture()
		if _guardian != null and is_instance_valid(_guardian) \
				and _guardian.get("kind") is SpiritKind:
			var guardian_kind: SpiritKind = _guardian.kind as SpiritKind
			_hud.debug_lock_capture_banner(tr("GUARDIAN_INTRO") % [
				tr(guardian_kind.display_name), tr(guardian_kind.guardian_rule)],
				guardian_kind.boss_accent)


## Shot 04's boss needs more than a `_guardian` reference — the currently drawn
## AnimatedSprite2D frame must exist too. Read the live node's alpha and transformed draw rect so
## hidden, tiny-scale, or off-screen states cannot pass on JSON alone.
func _debug_guardian_capture_visual_state() -> Dictionary:
	var state: Dictionary = {
		"guardian_visual_node_present": false,
		"guardian_visual_node_class": "",
		"guardian_root_visible_in_tree": false,
		"guardian_sprite_visible_in_tree": false,
		"guardian_root_effective_alpha": 0.0,
		"guardian_sprite_effective_alpha": 0.0,
		"guardian_root_opaque": false,
		"guardian_sprite_opaque": false,
		"guardian_current_animation": "",
		"guardian_current_frame": -1,
		"guardian_frame_texture_present": false,
		"guardian_frame_texture_path": "",
		"guardian_frame_texture_matches_field": false,
		"guardian_draw_rect_positive": false,
		"guardian_draw_rect_intersects_viewport": false,
		"guardian_draw_rect": [0.0, 0.0, 0.0, 0.0],
		"guardian_focus_rect": [0.0, 0.0, 0.0, 0.0],
		"guardian_draw_rect_fully_inside_viewport": false,
		"guardian_draw_rect_inside_focus": false,
		"guardian_draw_center_inside_focus": false,
		"guardian_player_canvas_distance": 0.0,
		"guardian_separated_from_player": false,
		"guardian_central_composition": false,
		"guardian_visual_ready": false,
	}
	if not OS.is_debug_build() or _guardian == null \
			or not is_instance_valid(_guardian) or not _guardian.is_inside_tree():
		return state
	var root: CanvasItem = _guardian as CanvasItem
	var sprite: AnimatedSprite2D = _guardian.get_node_or_null(
		"Sprite") as AnimatedSprite2D
	if root == null or sprite == null:
		return state
	# debug_stage_guardian() and negative tests can change position/scale in the same frame.
	# If the CanvasItem cache returns old values until the next frame, screen and judgment diverge.
	root.force_update_transform()
	sprite.force_update_transform()
	var root_visible: bool = root.is_visible_in_tree()
	var sprite_visible: bool = sprite.is_visible_in_tree()
	var root_alpha: float = _debug_effective_canvas_alpha(root)
	var sprite_alpha: float = _debug_effective_canvas_alpha(sprite)
	var animation: StringName = sprite.animation
	var current_frame: int = sprite.frame
	var frame_texture: Texture2D = null
	if sprite.sprite_frames != null \
			and sprite.sprite_frames.has_animation(animation) \
			and current_frame >= 0 \
			and current_frame < sprite.sprite_frames.get_frame_count(animation):
		frame_texture = sprite.sprite_frames.get_frame_texture(
			animation, current_frame)
	var frame_texture_path: String = _debug_texture_source_path(frame_texture)
	var frame_texture_matches_field: bool = frame_texture_path \
		in FIELD_GUARDIAN_CAPTURE_TEXTURES
	var local_draw_rect: Rect2 = _debug_animated_sprite_draw_rect(
		sprite, frame_texture)
	var canvas_draw_rect: Rect2 = _debug_canvas_rect(sprite, local_draw_rect)
	var draw_rect_positive: bool = frame_texture != null \
		and local_draw_rect.has_area() and canvas_draw_rect.has_area() \
		and canvas_draw_rect.size.x >= 1.0 and canvas_draw_rect.size.y >= 1.0
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var visible_draw_rect: Rect2 = canvas_draw_rect.intersection(
		viewport_rect) if draw_rect_positive else Rect2()
	var visible_fraction: float = visible_draw_rect.get_area() \
		/ canvas_draw_rect.get_area() if draw_rect_positive else 0.0
	var draw_rect_intersects_viewport: bool = draw_rect_positive \
		and visible_draw_rect.size.x >= GUARDIAN_CAPTURE_MIN_VISIBLE_EDGE \
		and visible_draw_rect.size.y >= GUARDIAN_CAPTURE_MIN_VISIBLE_EDGE \
		and visible_fraction >= GUARDIAN_CAPTURE_MIN_VISIBLE_FRACTION
	var focus_rect: Rect2 = _debug_guardian_capture_focus_rect(viewport_rect)
	var draw_rect_fully_inside_viewport: bool = draw_rect_positive \
		and _debug_rect_fully_inside(canvas_draw_rect, viewport_rect)
	var draw_rect_inside_focus: bool = draw_rect_positive \
		and _debug_rect_fully_inside(canvas_draw_rect, focus_rect)
	var draw_center_inside_focus: bool = draw_rect_positive \
		and focus_rect.has_point(canvas_draw_rect.get_center())
	var player_canvas_position: Vector2 = _player.get_global_transform_with_canvas().origin
	var player_distance: float = canvas_draw_rect.get_center().distance_to(
		player_canvas_position) if draw_rect_positive else 0.0
	var separated_from_player: bool = player_distance \
		>= GUARDIAN_CAPTURE_MIN_PLAYER_SEPARATION
	var central_composition: bool = draw_rect_fully_inside_viewport \
		and draw_rect_inside_focus and draw_center_inside_focus \
		and separated_from_player
	var visual_ready: bool = root_visible and sprite_visible \
		and root_alpha >= 0.99 and sprite_alpha >= 0.99 \
		and frame_texture != null and frame_texture_matches_field \
		and draw_rect_positive and draw_rect_intersects_viewport \
		and central_composition
	state.merge({
		"guardian_visual_node_present": true,
		"guardian_visual_node_class": sprite.get_class(),
		"guardian_root_visible_in_tree": root_visible,
		"guardian_sprite_visible_in_tree": sprite_visible,
		"guardian_root_effective_alpha": root_alpha,
		"guardian_sprite_effective_alpha": sprite_alpha,
		"guardian_root_opaque": root_alpha >= 0.99,
		"guardian_sprite_opaque": sprite_alpha >= 0.99,
		"guardian_current_animation": str(animation),
		"guardian_current_frame": current_frame,
		"guardian_frame_texture_present": frame_texture != null,
		"guardian_frame_texture_path": frame_texture_path,
		"guardian_frame_texture_matches_field": frame_texture_matches_field,
		"guardian_draw_rect_positive": draw_rect_positive,
		"guardian_draw_rect_intersects_viewport": draw_rect_intersects_viewport,
		"guardian_draw_rect": _debug_rect_values(canvas_draw_rect),
		"guardian_focus_rect": _debug_rect_values(focus_rect),
		"guardian_draw_rect_fully_inside_viewport": \
			draw_rect_fully_inside_viewport,
		"guardian_draw_rect_inside_focus": draw_rect_inside_focus,
		"guardian_draw_center_inside_focus": draw_center_inside_focus,
		"guardian_player_canvas_distance": player_distance,
		"guardian_separated_from_player": separated_from_player,
		"guardian_central_composition": central_composition,
		"guardian_visual_ready": visual_ready,
	}, true)
	return state


func _debug_guardian_kind_source_path() -> String:
	if not OS.is_debug_build() or _guardian == null \
			or not is_instance_valid(_guardian):
		return ""
	return str(_guardian.get_meta(GUARDIAN_KIND_SOURCE_PATH_META, ""))


func _debug_texture_source_path(texture: Texture2D) -> String:
	var source: Texture2D = texture
	while source is AtlasTexture:
		source = (source as AtlasTexture).atlas
		if source == null:
			return ""
	return source.resource_path if source != null else ""


func _debug_animated_sprite_draw_rect(
		sprite: AnimatedSprite2D, texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2()
	var texture_size: Vector2 = texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Rect2()
	var top_left: Vector2 = sprite.offset
	if sprite.centered:
		top_left -= texture_size * 0.5
	return Rect2(top_left, texture_size)


## Shot 01's enemy pack is counted from the current AnimatedSprite2D frame's real canvas rect,
## not the Spirit root origin. Tests mutate the same function for each failure boundary so capture
## state and fixture judgment cannot split.
func debug_enemy_sprite_capture_state(
		spirit: Node2D, viewport_rect: Rect2) -> Dictionary:
	var state: Dictionary = {
		"enemy_sprite_visible_in_tree": false,
		"enemy_sprite_effective_alpha": 0.0,
		"enemy_sprite_opaque": false,
		"enemy_sprite_frame_texture_ready": false,
		"enemy_sprite_draw_rect_positive": false,
		"enemy_sprite_visible_width": 0.0,
		"enemy_sprite_visible_height": 0.0,
		"enemy_sprite_visible_area": 0.0,
		"enemy_sprite_meaningful_intersection": false,
		"ready": false,
	}
	if not OS.is_debug_build() or spirit == null \
			or not is_instance_valid(spirit) or not spirit.is_inside_tree():
		return state
	var sprite: AnimatedSprite2D = spirit.get_node_or_null(
		"Sprite") as AnimatedSprite2D
	if sprite == null:
		return state
	spirit.force_update_transform()
	sprite.force_update_transform()
	var sprite_visible: bool = sprite.is_visible_in_tree()
	var effective_alpha: float = _debug_effective_canvas_alpha(sprite)
	var animation: StringName = sprite.animation
	var current_frame: int = sprite.frame
	var frame_texture: Texture2D = null
	if sprite.sprite_frames != null \
			and sprite.sprite_frames.has_animation(animation) \
			and current_frame >= 0 \
			and current_frame < sprite.sprite_frames.get_frame_count(animation):
		frame_texture = sprite.sprite_frames.get_frame_texture(
			animation, current_frame)
	var frame_texture_ready: bool = frame_texture != null \
		and frame_texture.get_width() > 0 and frame_texture.get_height() > 0
	var local_draw_rect: Rect2 = _debug_animated_sprite_draw_rect(
		sprite, frame_texture)
	var canvas_draw_rect: Rect2 = _debug_canvas_rect(sprite, local_draw_rect)
	var draw_rect_positive: bool = frame_texture_ready \
		and local_draw_rect.has_area() and canvas_draw_rect.has_area()
	var visible_draw_rect: Rect2 = canvas_draw_rect.intersection(viewport_rect) \
		if draw_rect_positive else Rect2()
	var meaningful_intersection: bool = visible_draw_rect.has_area() \
		and visible_draw_rect.size.x >= ENEMY_CAPTURE_MIN_VISIBLE_EDGE \
		and visible_draw_rect.size.y >= ENEMY_CAPTURE_MIN_VISIBLE_EDGE \
		and visible_draw_rect.get_area() >= ENEMY_CAPTURE_MIN_VISIBLE_AREA
	var ready: bool = sprite_visible and effective_alpha >= 0.99 \
		and frame_texture_ready and draw_rect_positive and meaningful_intersection
	state.merge({
		"enemy_sprite_visible_in_tree": sprite_visible,
		"enemy_sprite_effective_alpha": effective_alpha,
		"enemy_sprite_opaque": effective_alpha >= 0.99,
		"enemy_sprite_frame_texture_ready": frame_texture_ready,
		"enemy_sprite_draw_rect_positive": draw_rect_positive,
		"enemy_sprite_visible_width": visible_draw_rect.size.x,
		"enemy_sprite_visible_height": visible_draw_rect.size.y,
		"enemy_sprite_visible_area": visible_draw_rect.get_area(),
		"enemy_sprite_meaningful_intersection": meaningful_intersection,
		"ready": ready,
	}, true)
	return state


func debug_visible_enemy_sprite_count(
		spirits: Array[Node2D], viewport_rect: Rect2) -> int:
	if not OS.is_debug_build():
		return 0
	var visible_count: int = 0
	for spirit in spirits:
		if not is_instance_valid(spirit) or not spirit.is_inside_tree() \
				or not spirit.has_method("is_attackable") \
				or not bool(spirit.is_attackable()):
			continue
		var visual: Dictionary = debug_enemy_sprite_capture_state(
			spirit, viewport_rect)
		if bool(visual.get("ready", false)):
			visible_count += 1
	return visible_count


func _debug_safe_ui_state() -> Dictionary:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var safe_rect: Rect2 = Screen.viewport_safe_rect(get_viewport())
	var left_panel: Control = _hud.get_node_or_null("LeftPanel") as Control
	var right_panel: Control = _hud.get_node_or_null("RightPanel") as Control
	var boss: Control = _hud.get_node_or_null("Boss") as Control
	var banner: Control = _hud.get_node_or_null("Banner") as Control
	var pause_button: Control = _pause.get_node_or_null("Button") as Control
	var required: Array[Control] = [
		left_panel, right_panel, pause_button, _dash_button, _stick,
	]
	var required_inside: bool = true
	for control in required:
		required_inside = required_inside and control != null \
			and _debug_rect_fully_inside(control.get_global_rect(), safe_rect)
	var boss_inside: bool = boss != null and (
		not boss.is_visible_in_tree() \
		or _debug_rect_fully_inside(boss.get_global_rect(), safe_rect))
	var banner_inside: bool = banner != null and (
		not banner.is_visible_in_tree() \
		or _debug_rect_fully_inside(banner.get_global_rect(), safe_rect))
	var safe_inside_viewport: bool = _debug_rect_fully_inside(
		safe_rect, viewport_rect)
	return {
		"viewport_rect": _debug_rect_values(viewport_rect),
		"safe_rect": _debug_rect_values(safe_rect),
		"safe_area_inside_viewport": safe_inside_viewport,
		"hud_left_rect": _debug_control_rect_values(left_panel),
		"hud_left_inside_safe_area": left_panel != null \
			and _debug_rect_fully_inside(left_panel.get_global_rect(), safe_rect),
		"hud_right_rect": _debug_control_rect_values(right_panel),
		"hud_right_inside_safe_area": right_panel != null \
			and _debug_rect_fully_inside(right_panel.get_global_rect(), safe_rect),
		"pause_button_rect": _debug_control_rect_values(pause_button),
		"pause_button_inside_safe_area": pause_button != null \
			and _debug_rect_fully_inside(pause_button.get_global_rect(), safe_rect),
		"dash_rect": _debug_control_rect_values(_dash_button),
		"dash_inside_safe_area": _debug_rect_fully_inside(
			_dash_button.get_global_rect(), safe_rect),
		"move_stick_rect": _debug_control_rect_values(_stick),
		"move_stick_inside_safe_area": _debug_rect_fully_inside(
			_stick.get_global_rect(), safe_rect),
		"boss_rect": _debug_control_rect_values(boss),
		"boss_inside_safe_area": boss_inside,
		"banner_rect": _debug_control_rect_values(banner),
		"banner_inside_safe_area": banner_inside,
		"safe_ui_ready": safe_inside_viewport and required_inside \
			and boss_inside and banner_inside,
	}


func debug_store_capture_state(request: Dictionary) -> Dictionary:
	if not OS.is_debug_build():
		return {}
	var kind: String = str(request.get("kind", ""))
	if kind == "hero_direction" and _debug_hero_direction_capture_active:
		_debug_hold_hero_direction_capture()
	if kind == "field_guardian" and _debug_guardian_capture_active:
		# The probe does not call prepare again after the first ready. State observation itself must keep
		# the real guardian framing and a projectile-free screen so post-screencap matches.
		_debug_hold_guardian_capture()
	var safe_ui_state: Dictionary = _debug_safe_ui_state()
	var arena_ready: bool = is_inside_tree() and get_tree().current_scene == self \
		and not _over and is_instance_valid(_player) and is_instance_valid(_hud) \
		and bool(safe_ui_state.get("safe_ui_ready", false))
	if kind == "arena_ready":
		var ready_state: Dictionary = {
			"scene": "arena",
			"over": _over,
			"ready": arena_ready,
		}
		ready_state.merge(safe_ui_state, true)
		return ready_state
	if kind == "hero_direction":
		var requested_nonce: String = str(request.get("nonce", ""))
		var requested_hero_path: String = str(request.get("hero_resource_path", ""))
		var requested_direction: String = str(request.get("direction", ""))
		var request_signature: String = "%s|%s|%s" % [
			requested_nonce, requested_hero_path, requested_direction]
		var requested_nonce_valid: bool = STORE_CAPTURE_PROBE.valid_nonce(
			requested_nonce)
		var request_signature_matches: bool = requested_nonce_valid \
			and request_signature == _debug_hero_direction_request_signature
		var enemy_count: int = _debug_live_group_count(&"spirits")
		var guardian_count: int = 0
		for spirit in get_tree().get_nodes_in_group(&"spirits"):
			if is_instance_valid(spirit) and spirit.is_inside_tree() \
					and (spirit == _guardian \
						or spirit.has_meta(GUARDIAN_KIND_SOURCE_PATH_META)):
				guardian_count += 1
		var hostile_projectile_count: int = _debug_live_group_count(
			&"hostile_projectiles")
		var friendly_projectile_count: int = _debug_live_group_count(
			&"friendly_projectiles")
		var pickup_count: int = _debug_hero_direction_pickup_count()
		var afterimage_count: int = _debug_live_group_count(&"player_afterimages")
		var arena_aux_vfx_count: int = 0
		for effect in [_ring, _ripple]:
			if effect != null and is_instance_valid(effect) and effect.is_inside_tree():
				arena_aux_vfx_count += 1
		var banner: Dictionary = _hud.debug_capture_banner_snapshot()
		var banner_control: CanvasItem = _hud.get_node_or_null("Banner") as CanvasItem
		var banner_visible_in_tree: bool = banner_control != null \
			and banner_control.is_visible_in_tree()
		var banner_effective_alpha: float = _debug_effective_canvas_alpha(
			banner_control) if banner_control != null else 0.0
		var pause_overlay: CanvasItem = _pause.get_node_or_null("Overlay") as CanvasItem
		var combo_control: CanvasItem = _hud.get_node_or_null("Combo") as CanvasItem
		var combo_hidden: bool = combo_control == null \
			or not combo_control.is_visible_in_tree()
		var missile_recovery_control: CanvasItem = _hud.get_node_or_null(
			"LeftPanel/Stack/MissileRecovery") as CanvasItem
		var missile_recovery_hidden: bool = missile_recovery_control == null \
			or not missile_recovery_control.is_visible_in_tree()
		var lit_beacon_count: int = 0
		var beacons_frozen_count: int = 0
		var beacon_monitoring_count: int = 0
		var beacon_max_charge: float = 0.0
		for beacon in _beacons:
			if beacon.lit:
				lit_beacon_count += 1
			if not beacon.is_processing():
				beacons_frozen_count += 1
			beacon_max_charge = maxf(beacon_max_charge, float(beacon.get_charge()))
			var reach: Area2D = beacon.get_node_or_null("Reach") as Area2D
			if reach != null and reach.monitoring:
				beacon_monitoring_count += 1
		var modal_hidden: bool = not _result.is_visible_in_tree() \
			and not _relic.is_visible_in_tree() \
			and not _run_choice.is_visible_in_tree() \
			and (pause_overlay == null or not pause_overlay.is_visible_in_tree()) \
			and not _settings.is_visible_in_tree() \
			and not _credits.is_visible_in_tree() \
			and not _ladder.is_visible_in_tree() \
			and not _zone_wipe.is_visible_in_tree()
		var player_vfx_hidden: bool = bool(
			_player.debug_direction_capture_vfx_hidden())
		var player_physics_active: bool = _player.is_physics_processing()
		var camera_current: bool = _camera != null and is_instance_valid(_camera) \
			and _camera.enabled and get_viewport().get_camera_2d() == _camera
		var visual: Dictionary = _debug_hero_direction_visual_state()
		var hero_matches_request: bool = not requested_hero_path.is_empty() \
			and str(visual.get("hero_resource_path", "")) == requested_hero_path
		var direction_matches_request: bool = requested_direction == "any" \
			or (requested_direction in ["down", "up", "left", "right"] \
				and str(visual.get("hero_sprite_animation_direction", "")) \
					== requested_direction)
		# Still 24 cells also reject a walk frame of the same direction. Only walk/dash videos use
		# direction=any so real idle/walk transitions are all allowed.
		var animation_matches_request: bool = requested_direction == "any" \
			or (direction_matches_request \
				and str(visual.get("hero_sprite_animation", "")) \
					== "idle_" + requested_direction)
		var clean: bool = arena_ready and _debug_hero_direction_capture_active \
			and not get_tree().paused and not _over and not _transitioning \
			and enemy_count == 0 and guardian_count == 0 \
			and hostile_projectile_count == 0 and friendly_projectile_count == 0 \
			and pickup_count == 0 and afterimage_count == 0 \
			and arena_aux_vfx_count == 0 and _raid_queue.is_empty() \
			and _pending_dews == 0 and _pending_embers == 0 \
			and _ember_positions.is_empty() and _ember_elites.is_empty() \
			and _tutorial_step >= 4 and not banner_visible_in_tree \
			and combo_hidden and missile_recovery_hidden and modal_hidden \
			and player_vfx_hidden and player_physics_active \
			and camera_current and _capture_progress_frozen \
			and _level == 1 and _kills == 0 and _kill_score == 0 \
			and _health == _max_health and _health > 0 \
			and _cycle == 1 and _zone_index == 0 and _lit_count == 0 \
			and lit_beacon_count == 0 and beacon_max_charge <= 0.0 \
			and beacons_frozen_count == _beacons.size() \
			and beacon_monitoring_count == 0 and not _escape_active \
			and request_signature_matches \
			and hero_matches_request and direction_matches_request \
			and animation_matches_request \
			and bool(visual.get("hero_sprite_visual_ready", false))
		var process_frame: int = Engine.get_process_frames()
		if not clean:
			_debug_hero_direction_clean_frames = 0
		elif process_frame != _debug_hero_direction_last_process_frame:
			_debug_hero_direction_clean_frames += 1
		_debug_hero_direction_last_process_frame = process_frame
		var state: Dictionary = {
			"scene": "arena",
			"over": _over,
			"capture_active": _debug_hero_direction_capture_active,
			"tree_paused": get_tree().paused,
			"transitioning": _transitioning,
			"level": _level,
			"kills": _kills,
			"kill_score": _kill_score,
			"health": _health,
			"max_health": _max_health,
			"health_full": _health == _max_health and _health > 0,
			"shielded": _shielded,
			"cycle": _cycle,
			"zone_index": _zone_index,
			"lit_beacons": _lit_count,
			"actual_lit_beacon_count": lit_beacon_count,
			"beacon_max_charge": beacon_max_charge,
			"beacons_frozen_count": beacons_frozen_count,
			"beacon_monitoring_count": beacon_monitoring_count,
			"escape_active": _escape_active,
			"enemy_count": enemy_count,
			"guardian_count": guardian_count,
			"hostile_projectile_count": hostile_projectile_count,
			"friendly_projectile_count": friendly_projectile_count,
			"projectile_count": hostile_projectile_count \
				+ friendly_projectile_count,
			"pickup_count": pickup_count,
			"player_afterimage_count": afterimage_count,
			"arena_aux_vfx_count": arena_aux_vfx_count,
			"raid_queue_count": _raid_queue.size(),
			"pending_dew_count": _pending_dews,
			"pending_ember_count": _pending_embers,
			"banner_visible": banner_visible_in_tree,
			"banner_effective_alpha": banner_effective_alpha,
			"banner_locked": bool(banner.get("locked", true)),
			"combo_visible": not combo_hidden,
			"missile_recovery_visible": not missile_recovery_hidden,
			"tutorial_suppressed": _tutorial_step >= 4,
			"result_modal_hidden": not _result.is_visible_in_tree(),
			"relic_modal_hidden": not _relic.is_visible_in_tree(),
			"pause_modal_hidden": pause_overlay == null \
				or not pause_overlay.is_visible_in_tree(),
			"all_modals_hidden": modal_hidden,
			"player_capture_vfx_hidden": player_vfx_hidden,
			"player_physics_active": player_physics_active,
			"camera_current": camera_current,
			"combat_progress_frozen": _capture_progress_frozen,
			"requested_hero_resource_path": requested_hero_path,
			"requested_nonce_valid": requested_nonce_valid,
			"hero_resource_matches_request": hero_matches_request,
			"requested_direction": requested_direction,
			"hero_direction_matches_request": direction_matches_request,
			"hero_animation_matches_request": animation_matches_request,
			"request_signature_matches_capture": request_signature_matches,
			"clean_frame_streak": _debug_hero_direction_clean_frames,
		}
		state.merge(safe_ui_state, true)
		state.merge(visual, true)
		state["ready"] = clean and _debug_hero_direction_clean_frames >= 2
		return state
	if kind == "moonlight_barrage":
		var viewport_rect: Rect2 = get_viewport().get_visible_rect()
		var visible_enemy_sprite_count: int = \
			debug_visible_enemy_sprite_count(_spirits, viewport_rect)
		var live_missile_lanes: int = 0
		var visible_missile_lanes: int = 0
		var missile_visual_probe_count: int = 0
		var missile_visible_in_tree: bool = true
		var missile_effective_alpha: float = 1.0
		var missile_opaque: bool = true
		var missile_draw_after_launch: bool = true
		var missile_head_geometry_ready: bool = true
		var missile_trail_geometry_ready: bool = true
		for projectile in get_tree().get_nodes_in_group("friendly_projectiles"):
			if not is_instance_valid(projectile) \
					or not projectile.has_method("debug_store_capture_lanes"):
				continue
			var lane_state: Dictionary = projectile.debug_store_capture_lanes()
			var projectile_live_lanes: int = int(lane_state.get("live_lanes", 0))
			live_missile_lanes += projectile_live_lanes
			visible_missile_lanes += int(lane_state.get("visible_lanes", 0))
			if projectile_live_lanes <= 0:
				continue
			missile_visual_probe_count += 1
			missile_visible_in_tree = missile_visible_in_tree \
				and bool(lane_state.get("missile_visible_in_tree", false))
			missile_effective_alpha = minf(
				missile_effective_alpha,
				float(lane_state.get("effective_alpha", 0.0)))
			missile_opaque = missile_opaque \
				and bool(lane_state.get("missile_opaque", false))
			missile_draw_after_launch = missile_draw_after_launch \
				and bool(lane_state.get("draw_after_launch", false))
			missile_head_geometry_ready = missile_head_geometry_ready \
				and bool(lane_state.get("head_geometry_ready", false))
			missile_trail_geometry_ready = missile_trail_geometry_ready \
				and bool(lane_state.get("trail_geometry_ready", false))
		if missile_visual_probe_count == 0:
			missile_visible_in_tree = false
			missile_effective_alpha = 0.0
			missile_opaque = false
			missile_draw_after_launch = false
			missile_head_geometry_ready = false
			missile_trail_geometry_ready = false
		var terrain_path: String = str(_room.kind.resource_path) \
			if is_instance_valid(_room) and _room.kind != null else ""
		var world_key: String = str(_world_step().get("name", ""))
		var time_step: Dictionary = _time_step()
		var time_key: String = str(time_step.get("name", ""))
		var expected_tone: Color = time_step.get("tone", Color.TRANSPARENT)
		var applied_tone: Color = _rooms_root.modulate
		var expected_barrage_banner: String = tr("MISSILE_COMPLETE") % [
			_missile_power, MissileProgression.MAX_POWER]
		var barrage_banner: Dictionary = _hud.debug_capture_banner_snapshot()
		var barrage_state: Dictionary = {
			"scene": "arena",
			"over": _over,
			"level": _level,
			"cycle": _cycle,
			"zone_index": _zone_index,
			"terrain_path": terrain_path,
			"world_key": world_key,
			"lit_beacons": _lit_count,
			"transitioning": _transitioning,
			"escape_active": _escape_active,
			"time_key": time_key,
			"time_tone": _debug_color_array(expected_tone),
			"applied_time_tone": _debug_color_array(applied_tone),
			"time_tone_applied": applied_tone.is_equal_approx(expected_tone),
			"missile_power": _missile_power,
			"missile_max": MissileProgression.MAX_POWER,
			"missile_volley": _missile_volley(),
			"homing_active": _starfall_evolved(),
			"moonfire_active": _moonfire_on,
			"banner_key": "MISSILE_COMPLETE",
			"expected_banner_text": expected_barrage_banner,
			"actual_banner_text": str(barrage_banner.get("text", "")),
			"banner_visible": bool(barrage_banner.get("visible", false)),
			"banner_locked": bool(barrage_banner.get("locked", false)),
			"missile_visual_probe_count": missile_visual_probe_count,
			"missile_visible_in_tree": missile_visible_in_tree,
			"missile_effective_alpha": missile_effective_alpha,
			"missile_opaque": missile_opaque,
			"missile_draw_after_launch": missile_draw_after_launch,
			"missile_head_geometry_ready": missile_head_geometry_ready,
			"missile_trail_geometry_ready": missile_trail_geometry_ready,
			"visible_enemy_sprite_count": visible_enemy_sprite_count,
			"enemy_formation_visible": visible_enemy_sprite_count >= 3,
			"max_volley_live": live_missile_lanes >= 8,
			"barrage_visible": visible_missile_lanes >= 3,
		}
		barrage_state.merge(safe_ui_state, true)
		barrage_state["ready"] = arena_ready and not _transitioning \
			and _guardian == null and _level == 20 and _cycle == 3 \
			and _zone_index == 0 \
			and terrain_path == "res://resources/rooms/camp.tres" \
			and world_key == "WORLD_CAMP" and _lit_count == 0 \
			and not _escape_active and time_key == "TIME_NIGHT" \
			and bool(barrage_state["time_tone_applied"]) \
			and _missile_power == MissileProgression.MAX_POWER \
			and _missile_volley() == 8 and _starfall_evolved() \
			and not _moonfire_on \
			and str(barrage_state["actual_banner_text"]) \
				== expected_barrage_banner \
			and bool(barrage_state["banner_visible"]) \
			and bool(barrage_state["banner_locked"]) \
			and missile_visual_probe_count > 0 \
			and missile_visible_in_tree and missile_opaque \
			and missile_draw_after_launch and missile_head_geometry_ready \
			and missile_trail_geometry_ready \
			and visible_enemy_sprite_count >= 3 \
			and bool(barrage_state["enemy_formation_visible"]) \
			and bool(barrage_state["max_volley_live"]) \
			and bool(barrage_state["barrage_visible"])
		return barrage_state
	if kind != "field_guardian":
		return {}
	var guardian_alive: bool = _guardian != null and is_instance_valid(_guardian) \
		and _guardian.is_inside_tree() and not _guardian.is_queued_for_deletion()
	if guardian_alive and _guardian.has_method("is_attackable"):
		guardian_alive = bool(_guardian.is_attackable())
	var guardian_visual: Dictionary = _debug_guardian_capture_visual_state()
	var friendly_projectile_count: int = _debug_friendly_projectile_count()
	var guardian_visible: bool = guardian_alive \
		and bool(guardian_visual.get("guardian_root_visible_in_tree", false)) \
		and bool(guardian_visual.get("guardian_sprite_visible_in_tree", false))
	var guardian_on_screen: bool = guardian_visible and bool(guardian_visual.get(
		"guardian_draw_rect_intersects_viewport", false))
	var guardian_name: String = ""
	var guardian_kind_path: String = ""
	if guardian_alive and _guardian.get("kind") != null:
		guardian_name = tr(str(_guardian.kind.display_name)).strip_edges()
		guardian_kind_path = _debug_guardian_kind_source_path()
	var terrain_path: String = ""
	var terrain_encounter: int = -1
	if is_instance_valid(_room) and _room.kind != null:
		terrain_path = str(_room.kind.resource_path)
		terrain_encounter = int(_room.kind.encounter)
	var hud_boss_visible: bool = _hud.has_method("debug_boss_visible") \
		and bool(_hud.debug_boss_visible())
	var world_key: String = str(_world_step().get("name", ""))
	var time_step: Dictionary = _time_step()
	var time_key: String = str(time_step.get("name", ""))
	var expected_tone: Color = time_step.get("tone", Color.TRANSPARENT)
	var applied_tone: Color = _rooms_root.modulate
	var guardian_banner: Dictionary = _hud.debug_capture_banner_snapshot()
	var guardian_expected_banner: String = ""
	if guardian_alive and _guardian.get("kind") is SpiritKind:
		var guardian_kind: SpiritKind = _guardian.kind as SpiritKind
		guardian_expected_banner = tr("GUARDIAN_INTRO") % [
			tr(guardian_kind.display_name), tr(guardian_kind.guardian_rule)]
	var state: Dictionary = {
		"scene": "arena",
		"over": _over,
		"level": _level,
		"cycle": _cycle,
		"zone_index": _zone_index,
		"terrain_path": terrain_path,
		"terrain_encounter": terrain_encounter,
		"world_key": world_key,
		"time_key": time_key,
		"time_tone": _debug_color_array(expected_tone),
		"applied_time_tone": _debug_color_array(applied_tone),
		"time_tone_applied": applied_tone.is_equal_approx(expected_tone),
		"lit_beacons": _lit_count,
		"total_beacons": _beacons.size(),
		"transitioning": _transitioning,
		"escape_active": _escape_active,
		"guardian_alive": guardian_alive,
		"guardian_visible": guardian_visible,
		"guardian_on_screen": guardian_on_screen,
		"guardian_name": guardian_name,
		"guardian_kind_path": guardian_kind_path,
		"guardian_capture_active": _debug_guardian_capture_active,
		"friendly_projectile_count": friendly_projectile_count,
		"hud_boss_visible": hud_boss_visible,
		"banner_key": "GUARDIAN_INTRO",
		"expected_banner_text": guardian_expected_banner,
		"actual_banner_text": str(guardian_banner.get("text", "")),
		"banner_visible": bool(guardian_banner.get("visible", false)),
		"banner_locked": bool(guardian_banner.get("locked", false)),
	}
	state.merge(safe_ui_state, true)
	state.merge(guardian_visual, true)
	state["ready"] = arena_ready and _lit_count == _beacons.size() \
		and _beacons.size() == 3 and not _transitioning and not _escape_active \
		and _level == 20 and _cycle == 3 and _zone_index == 2 \
		and terrain_path == "res://resources/rooms/field.tres" \
		and world_key == "WORLD_FIELD" and time_key == "TIME_DAY" \
		and bool(state["time_tone_applied"]) \
		and terrain_encounter == RoomKind.Encounter.CROSSFIRE \
		and guardian_kind_path in FIELD_GUARDIAN_CAPTURE_KINDS \
		and guardian_alive and guardian_visible and guardian_on_screen \
		and _debug_guardian_capture_active and friendly_projectile_count == 0 \
		and bool(state["guardian_central_composition"]) \
		and bool(state["guardian_visual_ready"]) \
		and not guardian_name.is_empty() and hud_boss_visible \
		and not guardian_expected_banner.is_empty() \
		and str(state["actual_banner_text"]) == guardian_expected_banner \
		and bool(state["banner_visible"]) and bool(state["banner_locked"])
	return state


## Pin the Lv20 scene only from the coordinate-free device-capture boot.
## Release strips ArenaTools so there is no caller, and direct calls are ignored unless debug.
## Pin HUD numbers during store capture so they cannot change on their own.
##
## Freezing only level still let **kills land between the two capture state observations** after
## pack-unit spawning, so the left HUD panel's glyph width jittered by 3px
## (`Missile 0/8 · core 1/2` → `core 1/3`). Capture needs matching before/after state, so all five
## locales failed. Progress shown as numbers on screen must be frozen **together**
## here.
func debug_freeze_capture_progress() -> void:
	if not OS.is_debug_build():
		return
	_level_progress = 0
	_to_next = 2_000_000_000
	_hud.set_level_progress(0.0)
	# Missile-core progress. Raise the next-core requirement out of reach so further kills cannot
	# let `_missile_progress` change on-screen copy.
	_missile_progress = 0
	_capture_progress_frozen = true
	_refresh_missile_hud()


func _debug_color_array(color: Color) -> Array[float]:
	return [color.r, color.g, color.b, color.a]


func _debug_rect_fully_inside(inner: Rect2, outer: Rect2) -> bool:
	if inner.size.x <= 0.0 or inner.size.y <= 0.0 or not outer.has_area():
		return false
	return inner.position.x >= outer.position.x - 0.5 \
		and inner.position.y >= outer.position.y - 0.5 \
		and inner.end.x <= outer.end.x + 0.5 \
		and inner.end.y <= outer.end.y + 0.5


func _debug_rect_values(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _debug_control_rect_values(control: Control) -> Array[float]:
	return _debug_rect_values(control.get_global_rect()) \
		if control != null else [0.0, 0.0, 0.0, 0.0]


## End a run. Win or lose, everything gathers here.
##
## If spirits keep chasing after the end, the game is still running behind the panel.
func _finish(won: bool) -> void:
	if _over:
		return
	# Discard proof and the pinned banner before the result panel queue_frees cores without a signal.
	# Otherwise JSON can stay live while no core is on screen.
	_invalidate_debug_missile_capture()
	_over = true
	if _overcharge_beacon != null:
		# Defeat during overcharge is the most dangerous choice outcome. Dropping that event inflates
		# success rate, so record the terminal result before clearing beacon state.
		_analytics_track_overcharge_resolution("defeat")
	_pending_beacon_choice = null
	_overcharge_beacon = null
	_overcharge_progress = 0.0
	_overcharge_second_wave_sent = false
	_cycle_decision_queued = false
	if _run_choice.visible:
		_run_choice.close_without_choice()
	_player.set_charge_overcharge(false)
	_player.set_charge(0.0)
	# From Lesson 13 spirits appear and vanish. Do not touch ones already freed.
	_prune_spirits()
	for s in _spirits:
		s.set_target(null)
		# Damage queued on the guardian keeps draining each physics tick regardless of target.
		# If the boss dies behind the result screen, the signal that would close the cycle after continue
		# is gone — stop spirit physics itself and restore it exactly on continue.
		s.set_physics_process(false)
	_player.stop_for_result()
	if _voice_panel != null and is_instance_valid(_voice_panel):
		_voice_panel.clear()
	_stop_shake()
	set_process(false)                           # Stop reading the stick
	# Not reading is not enough. The stick is a full-screen control, so even unread it still eats
	# touches. The result panel cannot take taps.
	_stick.set_active(false)
	_pause.set_available(false)
	# Beacons run on their own clocks. Die shoved against one and it keeps charging behind the panel.
	for beacon in _beacons:
		beacon.freeze()
	_hud.set_boss(false)
	_prepare_missile_cores_for_result()
	# Loot moves on its own physics tick. Turning off only the arena's `_process()` still lets it chase
	# the player behind the result panel and even play collect SFX.
	for group in [
			&"moon_embers", &"power_orbs", &"missile_cores",
			&"moon_dews", &"hostile_projectiles"]:
		for pickup in get_tree().get_nodes_in_group(group):
			if is_instance_valid(pickup):
				pickup.queue_free()
	_clear_hostile_projectiles.call_deferred()
	# If arrows, meteors, rings, and ripples keep moving behind the result panel, only the picture
	# pretends to be paused. Score is blocked by `_over`, but collision and VFX still cost CPU.
	_clear_friendly_projectiles()
	_clear_friendly_projectiles.call_deferred()
	if _ring != null and is_instance_valid(_ring):
		_ring.set_physics_process(false)
		_ring.queue_free()
	_ring = null
	if _ripple != null and is_instance_valid(_ripple):
		_ripple.set_physics_process(false)
		_ripple.queue_free()
	_ripple = null

	var score: Score = Score.new()
	score.cycles = maxi(_cycle - 1, 0)
	score.beacons = _lit_count
	score.survived = _survived
	score.level = _level
	score.kills = _kill_score
	# Both new records and shards confirm a real save. A briefly failed side retries when a result
	# button is pressed, and until then the run cannot be left.
	var is_best: bool = _persist_finished_result(score.total(), score.rank())
	# The result line's "this run" is the cumulative shards actually received in this run, not the
	# last settlement delta. Pre-continue grants still show as this run's reward.
	score.shards = _run_shards_awarded
	if won:
		_analytics_run_end_reason = "cashout"
		_analytics_track_run_end("cashout", score.total())
	else:
		# Continue keeps the same run_id. Store only the reason so the terminal event fires when the run
		# is actually left.
		_analytics_run_end_reason = "defeat"

	# Peek whether the score belongs on the ladder. If so, the result screen shows the record button.
	_board_score = score.total()
	_board_rank = score.rank()
	_board_cycles = score.cycles
	_result.show_result(won, score, is_best, Ladder.makes_board(_board_score))


func _on_continue_requested() -> void:
	if continue_run():
		return
	# Balance gone or save failed. Restore the result screen as-is so the player can choose again.
	# Coins were not deducted.
	_result.reopen_after_failed_continue()


## No coins. End the current run and send them to the title, where the real-money shop lives.
##
## Not opening the shop inside the arena is intentional — stacking a pay wall on the death screen
## reads as "buy now" pressure and looks bad in review too.
## Clean up the run and let them buy continue coins on the title for the next defeat. Result buttons
## and review copy also state this boundary so we never promise to revive the just-ended run after purchase.
func _on_continue_purchase_requested() -> void:
	if not _retry_pending_result_persistence():
		_result.reopen_after_failed_continue()
		return
	_result.visible = false
	# **Shop, not shrine.** The shrine raises grace with shards; continue coins sell only in the
	# real-money shop. An early build sent players to the shrine and we got
	# "I cannot see coins."
	_mark_title_store_open()
	_pending_result_action = ResultAction.RESTART
	_leaving_for_title = true
	await _release_audio()
	if is_inside_tree():
		get_tree().change_scene_to_file(TITLE_SCENE)


func _mark_title_store_open() -> void:
	get_tree().root.set_meta(OPEN_STORE_META, true)


## I-frames right after continue. Spirits are still standing on the death spot, so standing up
## into another hit just wastes the coin.
const CONTINUE_GRACE: float = 3.0
## Quiet until the next spawn/raid after continue. Gives a breath.
const CONTINUE_CALM: float = 4.0
## Normal spirits inside this radius around the coin spend step aside with no score or loot.
## About the 4/3 camera's vertical radius — clears the screen without wiping distant progress.
const CONTINUE_CLEAR_RADIUS: float = 132.0


## Continue the run in place, arcade-style. Spends one coin.
##
## Undo exactly what `_finish()` turned off. **Score, level, relics, and missile power stay** —
## continue buys a life, not progress, and that is what separates its value from
## "from scratch."
##
## With no balance, change nothing and return false. Coin is spent before revive, so keep that
## order and a mid-revive failure cannot burn a coin alone (a failed save undoes the
## debit itself).
func continue_run() -> bool:
	if not _over:
		return false
	if not _retry_pending_result_persistence():
		return false
	if not Vault.spend_continue_coin():
		return false

	_over = false
	_analytics_run_end_reason = ""
	_analytics_continues += 1
	_analytics_track("continue_used", {
		"cycle": maxi(_cycle - 1, 0),
		"elapsed_ms": _analytics_elapsed_ms(),
	})
	_pending_beacon_choice = null
	_overcharge_beacon = null
	_overcharge_progress = 0.0
	_overcharge_second_wave_sent = false
	_pending_result_action = ResultAction.NONE
	_result.visible = false

	# Restore the life and danger cleared on death.
	_set_health(_max_health)
	_invulnerable = maxf(_invulnerable, CONTINUE_GRACE)
	_player.resume_after_continue(CONTINUE_CLEAR_RADIUS)
	_player.set_moonfire(_moonfire_on, _moonfire_locked)
	_player.set_move_input(Vector2.ZERO)
	_clear_continue_danger()

	# Restore input and UI.
	set_process(true)
	_stick.set_active(true)
	_pause.set_available(true)
	_player.set_charge_overcharge(false)

	# Beacons run on their own clocks. Restart what `_finish()` stopped.
	for beacon in _beacons:
		beacon.thaw()

	# Side weapons were freed as nodes by `_finish()`. Rebuild them from relics held now.
	_rebuild_aux_weapons()
	# Regular cores cleared for the result screen were restored as progress. Only after continue
	# succeeds, place them again on the new field so the earned upgrade chance is not lost.
	_try_drop_missile_core(_player.global_position)
	_refresh_missile_hud()

	# Clear one beat so standing up is not immediate burial in a pack.
	_spawn_timer = maxf(_spawn_timer, CONTINUE_CALM)
	_raid_left = maxf(_raid_left, CONTINUE_CALM)
	_hud.announce(tr("CONTINUE_RESUMED"), Color(1.0, 0.86, 0.5, 1))
	return true


## Clear the screen once right after continue. Normal spirits step aside rather than die, so no
## free score or loot; the guardian stays because it is the run's spine. Cut already-flying enemy
## shots and queued raids immediately so the same barrage does not resume when the 3s i-frames end.
func _clear_continue_danger() -> void:
	_raid_queue.clear()
	_clear_hostile_projectiles()
	_clear_hostile_projectiles.call_deferred()
	_prune_spirits()
	var clear_radius_squared: float = CONTINUE_CLEAR_RADIUS * CONTINUE_CLEAR_RADIUS
	for index in range(_spirits.size() - 1, -1, -1):
		var spirit: Node2D = _spirits[index]
		if not is_instance_valid(spirit):
			_spirits.remove_at(index)
			continue
		spirit.set_physics_process(true)
		if spirit == _guardian:
			spirit.set_target(_player)
			continue
		if spirit.global_position.distance_squared_to(_player.global_position) \
				<= clear_radius_squared:
			spirit.retreat()
			_spirits.remove_at(index)
			continue
		spirit.set_target(_player)


## Rebuild rings and ripples `_finish()` freed, matching relics held now.
func _rebuild_aux_weapons() -> void:
	for relic in _taken:
		if relic == null:
			continue
		match relic.effect:
			Relic.Effect.MOON_RING:
				_grant_ring()
			Relic.Effect.MOON_RIPPLE:
				_grant_ripple()
	_refresh_aux_weapons()


## Hide the pause screen when opening settings. Stacked, the one behind shows through and looks messy.
func _open_settings() -> void:
	_pause.set_overlay_visible(false)
	_settings.open()


func _on_settings_closed() -> void:
	_pause.set_overlay_visible(true)


## Same when opening credits.
func _open_credits() -> void:
	_settings.visible = false
	_credits.open()


func _restart() -> void:
	_analytics_track_run_end(
		_analytics_run_end_reason if not _analytics_run_end_reason.is_empty() else "restart")
	await _release_audio()
	if not is_inside_tree():
		return
	get_tree().reload_current_scene()


## Mute audio before swapping the scene.
##
## Otherwise `AudioFlush.wait()` lands on the transition frame and the screen freezes.
## Same issue the title hit in Lesson 3. Each of the three beacons also has its own SFX, so
## restarting with all lit stacks that wait four times.
func _release_audio() -> void:
	_bgm.release()
	_event_sfx.release()
	_pickup_sfx.release()
	for beacon in _beacons:
		beacon.release_audio()
	await get_tree().process_frame


## Android back. Walk back one step at a time.
##
## Playing → pause → title. The app does not quit in one press.
## Pass through the pause screen once so an in-progress run is not wiped by accident.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if _transitioning:
		return
	if _leaving_for_title:
		return
	if _analytics_consent.visible:
		# Leave the result as-is and close consent without a choice. UNKNOWN stays UNKNOWN.
		_close_analytics_consent_without_choice()
	elif _ladder.visible:
		# Result record entry is also one modal above. Ignoring it because "we are on results" leaves
		# Android hardware Back unable to close it and traps the touch Close.
		_ladder.close()
	elif _credits.visible:
		_credits.close()
	elif _settings.visible:
		if not _settings.close_nested_overlay():
			_settings.close()
	elif _over:
		return                                   # Do nothing on the result screen
	elif _run_choice.visible:
		return                                   # Do not discard a required choice with back
	elif _relic.visible:
		return                                   # Do not discard a required choice with back
	elif _dialogue.is_open():
		return                                   # Do not discard run progress with Back during a story beat
	elif get_tree().paused:
		get_tree().paused = false
		_return_to_title()
	else:
		_pause.request_pause()


func _return_to_title(open_shrine: bool = false) -> void:
	_leaving_for_title = true
	_analytics_track_run_end(
		_analytics_run_end_reason if not _analytics_run_end_reason.is_empty() else "title")
	await _release_audio()
	if is_inside_tree():
		if open_shrine:
			get_tree().root.set_meta(OPEN_SHRINE_META, true)
		get_tree().change_scene_to_file(TITLE_SCENE)


## Read the stick and pass it to the player.
##
## The player does not read the stick itself. Lesson 8's enemies have no stick, and
## Lesson 12's dash should also leave the input side alone.
func _process(delta: float) -> void:
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		_debug_hold_hero_direction_capture()
		# Keep real stick→Player physics and dash cooldown. Camera2D is a Player child, so it
		# follows this movement as-is. Only the combat clock and spawners pause.
		_player.set_move_input(_stick.get_value())
		_dash_button.set_ratio(_player.get_dash_ratio())
		return
	_tick_missile_recovery_hud()
	if _debug_guardian_capture_active:
		_debug_hold_guardian_capture()
	if _transitioning:
		# While the screen is briefly covered, pause the combat clock too. Taking a hit or losing
		# awakening time during a load makes terrain travel feel like a penalty.
		_player.set_move_input(Vector2.ZERO)
		_tick_shake(delta)
		return

	_dew_drop_cooldown = maxf(_dew_drop_cooldown - delta, 0.0)
	_player.set_move_input(_stick.get_value())
	_tick_tutorial()
	_tick_shake(delta)
	_tick_overcharge(delta)

	_dash_button.set_ratio(_player.get_dash_ratio())
	_point_compass(delta)

	# Guardian HP bar. Only while alive.
	var boss_alive: bool = _guardian != null and is_instance_valid(_guardian)
	_hud.set_boss(
		boss_alive,
		_guardian.get_health_ratio() if boss_alive else 0.0,
		tr(_guardian.kind.display_name) if boss_alive else "",
		_guardian.kind.boss_accent if boss_alive else Color.WHITE)

	# Moon blade. No button. If a spirit is nearby it fires on its own.
	# Scans the list every frame, but with at most six spirits the cost is cheap.
	# Swing again for any backlog.
	#
	# A plain `if` caps at **once per frame**, so after a fast hand stacked eight swings and the
	# interval fell under 1/60s the relic literally did nothing.
	# Drive up to four in one frame — more than that is not visually distinct.
	if not _debug_guardian_capture_active:
		var swings: int = 0
		while _player.can_attack() and swings < 4:
			var target: Node2D = _nearest_spirit()
			if target == null:
				break
			_swing_at(target)
			swings += 1

		_fire_arrows(delta)
	_cool_down(delta)
	_tick_moonfire(delta)
	_tick_raid_queue(delta)
	_invulnerable = maxf(_invulnerable - delta, 0.0)

	# A guardian fight is a promised one-on-one. Merely delaying the timer by 12s lets trash return
	# in a long fight, so freeze the clock itself while the guardian lives.
	if not boss_alive and not _escape_active and _overcharge_beacon == null:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = _spawn_interval_now()
			_spawn_spirit()

	# During escape, a short chase pack comes from behind the player instead of a normal formation.
	if not boss_alive and _overcharge_beacon == null:
		if _escape_active:
			_tick_escape(delta)
		else:
			_raid_left -= delta
			if _raid_left <= 0.0:
				_raid_left = _raid_interval_now()
				_raid()

	_survived += delta
	_hud.set_survived(_survived)
	_try_open_cycle_reward()                     # Reopen a reward that overlapped pause after resume
	_try_open_cycle_decision()
	_offer_relic()                               # If owed relics are waiting, offer them when the time comes
	_flush_ember_drops()


## Terrain settings for the current cycle.
func _world_step() -> Dictionary:
	# The starting terrain of each cycle also rotates one step. Starting every loop in the same order
	# makes the whole route feel like one memorized still even while visiting three maps.
	return WORLD_STEPS[((_cycle - 1) + _zone_index) % WORLD_STEPS.size()]


## Same terrain, higher cycle — a different guardian appears.
## Crossing a cycle advances the story one step.
##
## Open only while a line for this cycle index exists. After the prepared eight lines are used,
## pass quietly — better than repeating the same words later on.
##
## Never open during capture. The panel covers half the screen and would change the store image
## entirely.
## Queue the cycle story. 0 means none.
##
## Crossing a cycle also opens the loot panel. Opening dialogue at the same time buries it under
## the panel because `Dialogue` sits before `Relic` in the scene tree — **invisible underneath.**
## On device the story never showed for that reason. Open it after the reward pick.
var _pending_story_cycle: int = 0


func _show_cycle_story() -> void:
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		return
	# Do not open during store capture even when a cycle crosses. Progress can be frozen and the
	# guardian can still die; a half-screen panel then changes that shot entirely.
	# All four locale sets would need recapture, so block it here.
	if _capture_progress_frozen:
		return
	if _dialogue == null or not is_instance_valid(_dialogue):
		return
	if _story_lines(_cycle).is_empty():
		# The story ends at cycle 8. After that short asides take its place.
		#
		# This call used to live inside `_finish_cycle()`, but a few lines down
		# `_say("guardian_down")` overwrote the balloon in the same frame — **consumed and
		# never seen.** Balloons have no queue — the last call wins.
		_say("cycle")
		return
	_pending_story_cycle = _cycle


## Open the queued story after the loot panel closes.
func _flush_cycle_story() -> void:
	if _pending_story_cycle <= 0 or _over:
		return
	if _relic.visible or _result.visible or _run_choice.visible \
			or _cycle_decision_queued or _pending_beacon_choice != null \
			or _overcharge_beacon != null:
		return
	var lines: Array[String] = _story_lines(_pending_story_cycle)
	_pending_story_cycle = 0
	if lines.is_empty():
		return
	_dialogue.play(_hero_for_run(), lines)


## Two story lines for one cycle.
##
## `_A` reacts to what just happened; `_B` is what to do next. One line cannot hold both
## "what happened" and "so what now," so neither sticks.
## Missing lines are skipped quietly, so a cycle with only one line still works.
func _story_lines(cycle: int) -> Array[String]:
	var lines: Array[String] = []
	for suffix in ["A", "B"]:
		var key: String = "STORY_CYCLE_%d_%s" % [cycle, suffix]
		var line: String = tr(key)
		if line != key:
			lines.append(line)
	return lines


## Hero speaks one line. If none remain, pass quietly.
##
## Does not pause play — the balloon only appears over the player's head and fades.
## Stay silent during capture or after the run ends. Leftover on-screen text shakes the store
## screenshot fingerprint.
func _say(moment: String) -> void:
	if _over or _transitioning:
		return
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		return
	if _voice_panel == null or not is_instance_valid(_voice_panel):
		return
	var line: String = _voice.take(moment)
	if line.is_empty():
		return
	_voice_panel.say(_hero_for_run(), line)


## BGM playback rate for the current cycle.
func _arena_bgm_pitch() -> float:
	var extra: float = BGM_PITCH_PER_CYCLE * float(maxi(_cycle - 1, 0))
	return minf(BGM_PITCH_BASE + extra, BGM_PITCH_MAX)


func _guardian_resource_path() -> String:
	var step: Dictionary = _world_step()
	var roster: Variant = step.get("guardians", [])
	if roster is Array and not (roster as Array).is_empty():
		var paths: Array = roster as Array
		var index: int = clampi(_cycle - 1, 0, paths.size() - 1)
		return str(paths[index])
	return str(step["guardian"])


## Time of day matching how many beacons are lit.
func _time_step() -> Dictionary:
	return TIME_STEPS[clampi(_lit_count, 0, TIME_STEPS.size() - 1)]


## Bake one room.
##
## The seed mixes run, cycle, and terrain. The same cycle of the same run keeps the same layout,
## but the next cycle changes prop placement as well as terrain so it feels like a new place.
func _make_room() -> Room:
	var step: Dictionary = _world_step()
	var room_path: String = str(step["room"])
	var room: Room = ROOM_SCENE.instantiate() as Room
	_rooms_root.add_child(room)
	room.build(load(room_path) as RoomKind,
		hash([_run_seed, _cycle, _zone_index, room_path]))
	return room


## Swap in the terrain for the current cycle.
##
## After a guardian fight trash has cleared and the loot panel is about to cover the screen.
## Swapping immediately in that gap avoids drawing two rooms stacked for long, keeping mobile cost steady.
func _change_world(animated: bool = true, relocate_pickups: bool = true) -> void:
	var old: Room = _room
	_room = _make_room()
	if old != null and is_instance_valid(old):
		old.queue_free()
	_player.set_terrain_room(_room)
	_player.position = _room.nearest_clear(_player.position, 4.0)
	_player.reset_physics_interpolation()
	for spirit in _spirits:
		if is_instance_valid(spirit):
			spirit.set_terrain_room(_room)
			var radius: float = float(spirit.terrain_radius()) \
				if spirit.has_method("terrain_radius") else 10.0
			spirit.position = _room.nearest_clear(spirit.position, radius)
			spirit.reset_physics_interpolation()
	if relocate_pickups:
		_move_transition_pickups(Vector2.ZERO)

	_apply_time_tone(animated)


## Open the far gate after the first two beacons. A chase pack sticks from behind while you run for it.
func _open_escape(extended_moonfire: bool = false) -> void:
	if (OS.is_debug_build() and _debug_hero_direction_capture_active) \
			or _escape_active or _transitioning or _lit_count >= _beacons.size():
		return

	var middle: Vector2 = Room.MAP * 0.5
	var candidates: Array[Dictionary] = [
		{
			"at": Vector2(Room.PLAY.end.x - GATE_EDGE_INSET, middle.y),
			"direction": Vector2.RIGHT,
		},
		{
			"at": Vector2(Room.PLAY.position.x + GATE_EDGE_INSET, middle.y),
			"direction": Vector2.LEFT,
		},
		{
			"at": Vector2(middle.x, Room.PLAY.position.y + GATE_EDGE_INSET),
			"direction": Vector2.UP,
		},
		{
			"at": Vector2(middle.x, Room.PLAY.end.y - GATE_EDGE_INSET),
			"direction": Vector2.DOWN,
		},
	]
	var picked: Dictionary = candidates[0]
	var farthest: float = -1.0
	for candidate in candidates:
		var distance: float = _player.position.distance_squared_to(candidate["at"])
		if distance > farthest:
			farthest = distance
			picked = candidate

	_gate_direction = picked["direction"]
	_gate.position = picked["at"]
	_gate.reset_physics_interpolation()
	_gate.close()
	_gate.open()
	_escape_active = true
	_escape_wave_left = 0.8
	_escape_waves_spawned = 0
	# Close any queued normal raid before the gate opens so it does not overlap the escape formation.
	_raid_queue.clear()
	var message: String = tr("BEACON_KINDLED_EXTENDED") % _lit_count \
		if extended_moonfire else tr("BEACON_KINDLED") % _lit_count
	_hud.announce(message, Color(0.46, 0.94, 1.0, 1))


func _tick_escape(delta: float) -> void:
	if _escape_waves_spawned >= ESCAPE_WAVE_MAX:
		return
	_escape_wave_left -= delta
	if _escape_wave_left > 0.0:
		return
	_escape_wave_left += ESCAPE_WAVE_INTERVAL
	_escape_waves_spawned += 1
	_spawn_escape_wave()


## Place a small chase pack behind the running player, opposite the gate.
func _spawn_escape_wave() -> void:
	_prune_spirits()
	var available: int = spirit_cap() - _spirits.size() - _raid_queue.size()
	var count: int = mini(ESCAPE_WAVE_COUNT, maxi(available, 0))
	if count <= 0:
		return
	var toward_gate: Vector2 = (_gate.position - _player.position).normalized()
	if toward_gate.length_squared() < 0.01:
		toward_gate = _gate_direction
	var side: Vector2 = Vector2(-toward_gate.y, toward_gate.x)
	var behind: Vector2 = _player.position - toward_gate * 190.0
	for i in count:
		var lane: float = float(i) - float(count - 1) * 0.5
		var at: Vector2 = _room.clamp_to_play(behind + side * lane * 38.0)
		_summon(at, "", 0.78, false)


## Cross the moon gate into the real next terrain.
func _on_gate_entered() -> void:
	if (OS.is_debug_build() and _debug_hero_direction_capture_active) \
			or not _escape_active or _transitioning or _over:
		return
	_analytics_track("gate_crossed", {
		"cycle": _cycle,
		"terrain": _analytics_terrain_id(),
		"elapsed_ms": _analytics_elapsed_ms(),
	})
	_transitioning = true
	_zone_serial += 1
	_escape_active = false
	_gate.close()
	_stick.set_active(false)
	_pause.set_available(false)
	_player.set_move_input(Vector2.ZERO)
	_player.velocity = Vector2.ZERO
	_invulnerable = maxf(_invulnerable, 2.0)

	# Auto rings, ripples, and projectiles keep running while the wipe rises. Clear target lists and
	# queued shots first so kills and level-ups do not happen behind the covered screen.
	_raid_queue.clear()
	_clear_hostile_projectiles()
	_clear_hostile_projectiles.call_deferred()
	_clear_friendly_projectiles()
	_clear_friendly_projectiles.call_deferred()
	for spirit in _spirits:
		if is_instance_valid(spirit):
			spirit.retreat()
	_spirits.clear()
	_bank_transition_embers()
	_set_transition_orbs_paused(true)

	_zone_wipe_label.text = tr("ZONE_TRAVEL")
	_zone_wipe.modulate.a = 0.0
	_zone_wipe.visible = true
	var cover: Tween = create_tween()
	cover.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	cover.tween_property(_zone_wipe, "modulate:a", 1.0, ZONE_FADE_SECONDS)
	await cover.finished
	if _over or not is_inside_tree():
		return

	var old_player: Vector2 = _player.position
	_zone_index = clampi(_lit_count, 0, WORLD_STEPS.size() - 1)
	# Pickups move below by entrance-relative coords, then resolve against the new terrain collision.
	_change_world(false, false)
	_player.position = _room.nearest_clear(_zone_entry_position(), 4.0)
	_player.velocity = Vector2.ZERO
	_player.reset_physics_interpolation()
	var camera: Camera2D = _player.get_node("Cam") as Camera2D
	if camera != null:
		camera.reset_smoothing()
	_move_transition_pickups(_player.position - old_player)
	_place_current_beacon()
	_refresh_beacon_visibility()
	_zone_wipe_label.text = tr("ZONE_ENTER") % tr(str(_world_step()["name"]))

	# Give a short beat to read the terrain name, then reopen the field.
	await get_tree().create_timer(0.24, false).timeout
	if not is_inside_tree():
		return
	var reveal: Tween = create_tween()
	reveal.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	reveal.tween_property(_zone_wipe, "modulate:a", 0.0, ZONE_FADE_SECONDS)
	await reveal.finished
	if not is_inside_tree():
		return
	_zone_wipe.visible = false
	_stick.set_active(true)
	_pause.set_available(true)
	_transitioning = false
	_set_transition_orbs_paused(false)
	_spawn_timer = minf(_spawn_timer, 1.2)
	_raid_left = maxf(_raid_left, 8.0)
	_spawn_arrival_pursuers()
	var serial: int = _zone_serial
	get_tree().create_timer(1.1, false).timeout.connect(
		_announce_world_rule_if_current.bind(serial))


func _zone_entry_position() -> Vector2:
	var middle: Vector2 = Room.MAP * 0.5
	if _gate_direction.x > 0.5:
		return Vector2(Room.PLAY.position.x + 76.0, middle.y)
	if _gate_direction.x < -0.5:
		return Vector2(Room.PLAY.end.x - 76.0, middle.y)
	if _gate_direction.y > 0.5:
		return Vector2(middle.x, Room.PLAY.position.y + 76.0)
	return Vector2(middle.x, Room.PLAY.end.y - 76.0)


## Only two spirits follow to the new terrain entrance. Clearing all of them breaks tension at the gate.
func _spawn_arrival_pursuers() -> void:
	var side: Vector2 = Vector2(-_gate_direction.y, _gate_direction.x)
	for i in 2:
		var lane: float = -0.5 + float(i)
		var at: Vector2 = _room.clamp_to_play(
			_player.position - _gate_direction * 58.0 + side * lane * 44.0)
		_summon(at, "", 0.68, false)


## Do not leave moon embers on the off-screen previous terrain. Settle them into the gauge on travel.
func _bank_transition_embers() -> void:
	for i in _ember_elites.size():
		_gain_moonfire(ELITE_EMBER_CHARGE if _ember_elites[i] else EMBER_CHARGE)
	_ember_positions.clear()
	_ember_elites.clear()
	_pending_embers = 0
	for ember in get_tree().get_nodes_in_group("moon_embers"):
		if not is_instance_valid(ember):
			continue
		if ember.has_method("drain_for_transition"):
			_gain_moonfire(float(ember.drain_for_transition()))


## Carry dropped weapon cores into the next room; clear heal dew when crossing the gate.
## Letting dew follow turns travel into a mobile warehouse of the previous terrain's heals.
func _move_transition_pickups(offset: Vector2) -> void:
	_move_transition_pickup_group(
		&"power_orbs", offset, POWER_ORB_TERRAIN_RADIUS)
	_move_transition_pickup_group(
		&"missile_cores", offset, MISSILE_CORE_TERRAIN_RADIUS)
	for dew in get_tree().get_nodes_in_group("moon_dews"):
		if is_instance_valid(dew):
			dew.queue_free()


func _move_transition_pickup_group(
		group: StringName,
		offset: Vector2,
		radius: float,
	) -> void:
	for pickup in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(pickup):
			continue
		if pickup.has_method("shift_for_transition"):
			pickup.shift_for_transition(offset, Room.PLAY)
		else:
			pickup.position = _room.clamp_to_play(pickup.position + offset)
		pickup.position = _room.nearest_clear(pickup.position, radius)
		if pickup.has_method("set_terrain_room"):
			pickup.set_terrain_room(_room)
		pickup.reset_physics_interpolation()


func _set_transition_orbs_paused(paused: bool) -> void:
	for group in [&"power_orbs", &"missile_cores"]:
		for orb in get_tree().get_nodes_in_group(group):
			if is_instance_valid(orb):
				if orb.has_method("set_transition_paused"):
					orb.set_transition_paused(paused)
				else:
					orb.set_process(not paused)


func _announce_world_rule_if_current(serial: int) -> void:
	if serial == _zone_serial and not _transitioning:
		_announce_world_rule()


## Show beacon progress as night → blue dawn → sunrise → day.
func _apply_time_tone(animated: bool = true) -> void:
	var time: Dictionary = _time_step()
	var tone: Color = time["tone"]

	if _brighten != null and _brighten.is_valid():
		_brighten.kill()
	if animated:
		_brighten = create_tween()
		_brighten.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_brighten.tween_property(_rooms_root, "modulate", tone, BRIGHTEN_SECONDS)
	else:
		_rooms_root.modulate = tone

	var world: Dictionary = _world_step()
	_hud.set_world(str(world["name"]), str(time["name"]))












## Screen fit.
##
## The arena root is a `Node2D`, so shifting itself also moves the forest and all three beacons.
## The title root is a `Control`, so forest and beacons must shift separately. Same math lives once
## in `Screen` for both to reuse.
## The camera follows the player.
##
## The arena used to center itself on screen. One stage-sized screen made that fine.
## The map is now 1900×1180 and **does not fit on screen.**
## `Player/Cam` follows and stops at the map edge.
func _recenter() -> void:
	position = Vector2.ZERO
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var safe_rect: Rect2 = Screen.viewport_safe_rect(get_viewport())
	for anchored: Control in [_stick, _dash_button, _hud]:
		Screen.apply_safe_area(anchored, safe_rect, viewport_rect)
	for modal: Control in [
		_result, _analytics_consent, _pause, _settings, _credits, _ladder,
		_relic, _run_choice,
	]:
		Screen.apply_safe_content(modal, safe_rect, viewport_rect)


## Register one spirit with the arena. Same for scene-placed and later-spawned ones.
func _register_spirit(spirit: Node2D) -> void:
	# Homing missiles use this to reacquire when they lose a target. The arena's `_spirits`
	# array could be passed in, but a projectile that knows the arena entangles the two.
	spirit.add_to_group("spirits")
	spirit.set_target(_player)
	spirit.set_terrain_room(_room)
	spirit.set_projectile_hit_handler(_on_player_hit)
	spirit.touched_player.connect(_on_player_hit)
	spirit.perished.connect(_on_spirit_perished)
	_spirits.append(spirit)


func _clear_hostile_projectiles() -> void:
	for projectile in get_tree().get_nodes_in_group("hostile_projectiles"):
		if is_instance_valid(projectile):
			projectile.set_physics_process(false)
			projectile.queue_free()


func _clear_friendly_projectiles() -> void:
	for projectile in get_tree().get_nodes_in_group("friendly_projectiles"):
		if is_instance_valid(projectile):
			projectile.set_physics_process(false)
			projectile.queue_free()


## Nearest spirit in range. null if none.
##
## **Finding enemies is the arena's job, not the player's.** The enemy list already lives here, and
## this is the third place Lesson 6's "the player does not even read the stick" rule applies.
func _nearest_spirit() -> Node2D:
	return _nearest_in(_player.attack_range)


## Swing the moon blade and cut every spirit inside the fan.
##
## One swing **hits everything it reaches.** Hitting only the nearest leaves no way out when
## three spirits stick overlapping.
func _swing_at(target: Node2D) -> void:
	var direction: Vector2 = (target.global_position - _player.global_position).normalized()
	if direction.length() < 0.01:
		direction = Vector2.DOWN

	var full_moon: bool = false
	var full_moon_evolved: bool = Relic.family_evolved(
		_taken, Relic.Family.FULL_MOON)
	var full_moon_resonant: bool = Relic.family_resonant(
		_taken, Relic.Family.FULL_MOON)
	if full_moon_evolved or full_moon_resonant:
		if full_moon_evolved:
			_full_moon_swings += 1
		full_moon = _full_moon_primed \
			or (full_moon_evolved and _full_moon_swings % 3 == 0)
		_full_moon_primed = false
	_player.attack(direction, full_moon)

	var reach: float = _player.attack_range * (1.15 if full_moon else 1.0)
	var half_arc: float = PI if full_moon else deg_to_rad(_player.attack_arc) * 0.5
	var damage: int = _scaled(_player.attack_damage, 1.10) \
		if full_moon else _player.attack_damage
	for spirit in _spirits:
		if not is_instance_valid(spirit) or not spirit.is_attackable():
			continue
		var to_spirit: Vector2 = spirit.global_position - _player.global_position
		if to_spirit.length() > reach:
			continue
		# Outside the fan is also outside the drawn slash. Visible range and hit range stay the same.
		if absf(direction.angle_to(to_spirit)) > half_arc:
			continue
		spirit.take_damage(damage, _player.global_position)


## Raid. Appear all at once around the player.
##
## **A steady stream alone makes endless mode dull.** Spirits walking in one-by-one at a fixed gap
## feel the same at 10 minutes or 30. A good survivor alternates quiet and chaos —
## that drop from a breath to surrounded on all sides is the dynamism.
##
## Surrounding is the point. A one-sided rush is escaped by walking the other way; a ring means
## you **have to break out.** That is also when dash earns its keep.
func _raid() -> void:
	if _over or _transitioning or _escape_active \
			or (_guardian != null and is_instance_valid(_guardian)):
		return
	var many: int = RAID_BASE + 2 * (_cycle - 1)
	if _encounter_kind() == RoomKind.Encounter.CROSSFIRE:
		many += 2                              # Open field formations are a bit wider
	many = mini(many, spirit_cap() - _spirits.size() - _raid_queue.size())
	if many <= 2:
		return                                   # Already full. More would not show

	_shake(3.0)

	# RoomKind.Encounter: 0=forest encircle, 1=field crossfire, 2=camp escort.
	# Terrain is not only a recolor — raids ask for different movement.
	var encounter: int = _encounter_kind()
	# A line when the pack closes in. The banner says what is coming; this says why —
	# a balloon, so the screen does not pause.
	_say("swarm")
	match encounter:
		1:
			_hud.announce(tr("RAID_CROSSFIRE"), Color(0.72, 0.88, 1.0, 1))
			_queue_crossfire(many)
		2:
			_hud.announce(tr("RAID_CARAVAN"), Color(1.0, 0.7, 0.38, 1))
			_queue_caravan(many)
		_:
			_hud.announce(tr("RAID_AMBUSH"), Color(0.7, 1.0, 0.72, 1))
			_queue_ambush(many)

	# A short quiet after the raid passes. **Contrast needs silence after it.**
	_spawn_timer = maxf(_spawn_timer, RAID_LULL)


## Forest — encircle with ~54° left open toward a beacon. Flee down the gap or break toward the ember.
func _queue_ambush(many: int) -> void:
	var gap_direction: Vector2 = _nearest_unlit_beacon_direction()
	var gap: float = deg_to_rad(54.0)
	var start: float = gap_direction.angle() + gap * 0.5
	var arc: float = TAU - gap
	for i in many:
		# Place evenly on the remaining arc outside the open fan, with a little jitter.
		var angle: float = start + arc * (float(i) + 0.5) / float(many) \
			+ randf_range(-0.08, 0.08)
		var reach: float = randf_range(RAID_RING, RAID_RING + 40.0)
		_queue_raid_spirit(_safe_raid_point(Vector2.RIGHT.rotated(angle), reach))


## Field — two side lines and two casters behind. Push one side first to make a safe half.
func _queue_crossfire(many: int) -> void:
	var horizontal_room: float = minf(
		_player.position.x - Room.PLAY.position.x,
		Room.PLAY.end.x - _player.position.x)
	var vertical_room: float = minf(
		_player.position.y - Room.PLAY.position.y,
		Room.PLAY.end.y - _player.position.y)
	var axis: Vector2 = Vector2.RIGHT if horizontal_room >= vertical_room else Vector2.DOWN
	var across: Vector2 = Vector2(-axis.y, axis.x)
	var first_side: int = many / 2
	for side_index in 2:
		var side: float = -1.0 if side_index == 0 else 1.0
		var count: int = first_side if side_index == 0 else many - first_side
		for i in count:
			var lane: float = float(i) - float(count - 1) * 0.5
			var direction: Vector2 = (axis * side * 220.0 + across * lane * 32.0).normalized()
			var reach: float = 245.0 if i == 0 else randf_range(205.0, 235.0)
			var forced: String = "res://resources/caster.tres" if i == 0 else ""
			_queue_raid_spirit(_safe_raid_point(direction, reach), forced)


## Camp — elite ember carrier and wedge escort. Ambush the carrier for a large ember.
func _queue_caravan(many: int) -> void:
	var origin: Vector2 = _farthest_spawn()
	var inward: Vector2 = (_player.position - origin).normalized()
	var outward: Vector2 = -inward
	var across: Vector2 = Vector2(-inward.y, inward.x)
	var carrier: Vector2 = _safe_raid_point(outward, RAID_RING + 24.0)
	_queue_raid_spirit(carrier, "res://resources/ember.tres", true)

	for i in many - 1:
		var row: int = i / 3 + 1
		var lane: int = i % 3 - 1
		var offset: Vector2 = outward * float(row) * 24.0 + across * float(lane) * 34.0
		var at: Vector2 = _room.clamp_to_play(carrier + offset)
		_queue_raid_spirit(at)


## Nearest unlit beacon. The forest ambush exit points at the next objective.
func _nearest_unlit_beacon_direction() -> Vector2:
	var best: Node2D = null
	var best_distance: float = INF
	for beacon in _beacons:
		if not beacon.visible or beacon.lit:
			continue
		var distance: float = beacon.position.distance_squared_to(_player.position)
		if distance < best_distance:
			best = beacon
			best_distance = distance
	if best == null:
		return Vector2.RIGHT.rotated(randf() * TAU)
	return (best.position - _player.position).normalized()


## Keep a minimum distance so spirits clamped at the map edge do not pile under the player's feet.
func _safe_raid_point(direction: Vector2, reach: float) -> Vector2:
	var at: Vector2 = _room.clamp_to_play(_player.position + direction.normalized() * reach)
	if at.distance_to(_player.position) >= 150.0:
		return _room.nearest_clear(at, 10.0)
	var toward_center: Vector2 = (Room.MAP * 0.5 - _player.position).normalized()
	if toward_center.length() < 0.01:
		toward_center = -direction.normalized()
	return _room.nearest_clear(
		_room.clamp_to_play(
			_player.position + toward_center * maxf(reach, 180.0)),
		10.0)


func _queue_raid_spirit(
		at: Vector2,
		forced_kind: String = "",
		force_elite: bool = false,
		toughness_scale: float = 1.0) -> void:
	_raid_queue.append({
		"at": at,
		"kind": forced_kind,
		"elite": force_elite,
		"toughness": toughness_scale,
		"cycle": _cycle,
		"zone": _zone_serial,
	})


## Attach queued raids in short steps. Drop leftovers if terrain changed or a boss fight started.
func _tick_raid_queue(delta: float) -> void:
	if _raid_queue.is_empty():
		return
	if _guardian != null or _over:
		_raid_queue.clear()
		return
	_raid_spawn_left -= delta
	if _raid_spawn_left > 0.0:
		return
	_raid_spawn_left = RAID_SPAWN_STEP

	# Two per tick. Clearer formation than one every 0.08s, with a lower spawn peak.
	for i in 2:
		if _raid_queue.is_empty():
			break
		var queued: Dictionary = _raid_queue.pop_front()
		if int(queued["cycle"]) != _cycle or int(queued.get("zone", -1)) != _zone_serial \
				or _spirits.size() >= spirit_cap():
			continue
		_summon(
			queued["at"],
			str(queued["kind"]),
			float(queued["toughness"]),
			bool(queued["elite"]))


## A relic was picked. Apply it on the spot.
##
## **The effect must read immediately, but one card must not finish the build.** Show the post-pick
## preview and HUD rank, while combat power rises gradually across several cards.
func _on_relic_picked(
		relic: Relic, feedback: bool = true, analytics_source: String = "") -> void:
	if relic == null:
		return                                   # Nothing left to draw
	var cycle_reward: bool = _cycle_reward_pending
	var family: Relic.Family = Relic.family_of_relic(relic)
	var before: Dictionary = Relic.family_state(_taken, family) \
		if family != Relic.Family.NONE else {}
	var grant_count: int = maxi(int(relic.get_meta("grant_count", 1)), 1)
	var final_stack: int = int(relic.get_meta("stack", grant_count))
	var path: String = str(relic.get_meta("path", ""))
	var analytics_cycle: int = _completed_cycle if cycle_reward else _cycle
	if path.is_empty():
		path = relic.resource_path

	# Guardian loot is one rank today, but normal cards share this grant path so multi-stack offers
	# are supported. Array length and the card's rank number must always match.
	for i in grant_count:
		var item: Relic = relic if i == grant_count - 1 else relic.duplicate()
		item.set_meta("path", path)
		item.set_meta("stack", final_stack - grant_count + i + 1)
		item.set_meta("grant_count", 1)
		_taken.append(item)
		_feed(item)
	_settle_rates()
	_refresh_aux_weapons()
	var after: Dictionary = Relic.family_state(_taken, family) \
		if family != Relic.Family.NONE else {}
	_refresh_evolution_hud(family)
	var source: String = analytics_source if not analytics_source.is_empty() \
		else ("guardian" if cycle_reward else "level")
	_analytics_track("relic_chosen", {
		"relic": _analytics_resource_id(path),
		"family": _analytics_family_id(family),
		"source": source,
		"stack": clampi(final_stack, 1, 999),
		"cycle": analytics_cycle,
		"elapsed_ms": _analytics_elapsed_ms(),
	})
	# Opening gear counts toward resonance state, but does not count as the player personally picking
	# a relic card for tutorial completion.
	if source != "opening":
		_analytics_tutorial_step("relic")
	if family != Relic.Family.NONE \
			and not bool(before.get("evolved", false)) \
			and bool(after.get("evolved", false)):
		_analytics_track("evolution_unlocked", {
			"family": _analytics_family_id(family),
			"cycle": analytics_cycle,
			"elapsed_ms": _analytics_elapsed_ms(),
		})

	if feedback:
		# The chosen path's shape shows on the first frame the card closes. Do not make them wait for a
		# third attack or the next cycle just to see a number change.
		match family:
			Relic.Family.STARFALL:
				_arrow_timer = 0.0
				_player.play_starfall_preview(_missile_volley())
			Relic.Family.FULL_MOON:
				_player.play_full_moon_preview()
			Relic.Family.MOON_DANCE:
				_player.play_moon_dance()
		# Use the prepared pop presentation on the real pick path. A full redraw would reduce the moment
		# a card becomes combat power to one small glyph.
		if grant_count == 1:
			_hud.add_relic(relic)
		else:
			_hud.set_relics(_taken)
		_announce_relic_gain(relic, before, after, cycle_reward)
		_event_sfx.pitch_scale = 1.0 + 0.025 * float(mini(final_stack, 6))
		_event_sfx.play()
	else:
		_hud.set_relics(_taken)

	if cycle_reward:
		_cycle_reward_pending = false
		_cycle_decision_queued = true
		if not feedback:
			_hud.announce(
				tr("CYCLE_CLEARED") % _completed_cycle,
				Color(1, 0.88, 0.55, 1))

	# If more are owed, keep paused and pick next. Leaving here would resume combat; the player clears
	# the backlog in one pause instead.
	if _owed > 0:
		# A direct `open.call_deferred()` can stack two modals if the pause menu opened first in the same
		# frame. Pass the shared pause check on the next idle, but mark the gap already elapsed so chained
		# picks do not wait another 5.5s.
		_last_offer = _survived - OFFER_GAP
		_queue_relic_offer()
		return

	# After guardian rewards are cleared, choose whether to cash this run's gains or stake the next
	# cycle. A normal relic pick just continues any queued story.
	if _cycle_decision_queued:
		_try_open_cycle_decision.call_deferred()
	else:
		_flush_cycle_story.call_deferred()


## Whether this is one of the four moon-wheel growth effects.
func _is_disc_relic(relic: Relic) -> bool:
	return Relic.family_of_relic(relic) == Relic.Family.STARFALL


func _announce_relic_gain(
		relic: Relic,
		before: Dictionary,
		after: Dictionary,
		cycle_reward: bool) -> void:
	var family: Relic.Family = Relic.family_of_relic(relic)
	var display_name: String = tr(relic.display_name)
	var stack: int = int(relic.get_meta("stack", 1))
	if family == Relic.Family.NONE:
		var gained: String = tr("CYCLE_REWARD_DOUBLE") % [
			display_name, stack, _completed_cycle] \
			if cycle_reward else tr("RELIC_GAINED") % [display_name, stack]
		_hud.announce(gained, relic.accent)
		return

	var family_name: String = tr(Relic.family_name_key(family))
	var was_evolved: bool = bool(before.get("evolved", false))
	var is_evolved: bool = bool(after.get("evolved", false))
	var was_resonant: bool = bool(before.get("resonant", false))
	var is_resonant: bool = bool(after.get("resonant", false))
	var message: String
	if not was_evolved and is_evolved:
		message = tr("CYCLE_REWARD_EVOLUTION") % [family_name, _completed_cycle] \
			if cycle_reward else tr("EVOLUTION_UNLOCKED") % family_name
		if family == Relic.Family.STARFALL:
			_arrow_timer = 0.0
	elif is_evolved:
		message = tr("CYCLE_REWARD_DOUBLE") % [
			family_name, int(after["total"]), _completed_cycle] \
			if cycle_reward else tr("EVOLUTION_UPGRADED") % [
				family_name, int(after["total"])]
	elif not was_resonant and is_resonant:
		message = tr("CYCLE_REWARD_RESONANCE") % [family_name, _completed_cycle] \
			if cycle_reward else tr("RESONANCE_UNLOCKED") % family_name
	else:
		message = tr("CYCLE_REWARD_PROGRESS") % [
				family_name, int(after["progress"]), int(after["evolve_at"]),
				_completed_cycle] \
			if cycle_reward else tr("EVOLUTION_PROGRESS_BANNER") % [
				family_name, int(after["progress"]), int(after["evolve_at"])]
	_hud.announce(message, Relic.family_accent(family))


func _refresh_evolution_hud(preferred: Relic.Family = Relic.Family.NONE) -> void:
	if preferred != Relic.Family.NONE \
			and Relic.family_total(_taken, preferred) > 0:
		_focus_family = preferred
	elif _focus_family == Relic.Family.NONE \
			or Relic.family_total(_taken, _focus_family) <= 0:
		_focus_family = _strongest_family()

	if _focus_family == Relic.Family.NONE:
		_hud.set_evolution(Relic.Family.NONE, 0, 0)
		return
	var state: Dictionary = Relic.family_state(_taken, _focus_family)
	_hud.set_evolution(
		_focus_family,
		int(state["progress"]),
		int(state["tier"]),
		int(state["evolve_at"]))


func _strongest_family() -> Relic.Family:
	var best: Relic.Family = Relic.Family.NONE
	var best_distinct: int = 0
	var best_total: int = 0
	for family in [
		Relic.Family.STARFALL,
		Relic.Family.FULL_MOON,
		Relic.Family.MOON_DANCE,
	]:
		var distinct: int = Relic.family_distinct(_taken, family)
		var total: int = Relic.family_total(_taken, family)
		if distinct > best_distinct or (distinct == best_distinct and total > best_total):
			best = family
			best_distinct = distinct
			best_total = total
	return best


func _announce_world_rule() -> void:
	if _over:
		return
	match _encounter_kind():
		RoomKind.Encounter.CROSSFIRE:
			_hud.announce(tr("RAID_CROSSFIRE"), Color(0.72, 0.88, 1.0, 1))
		RoomKind.Encounter.CARAVAN:
			_hud.announce(tr("RAID_CARAVAN"), Color(1.0, 0.7, 0.38, 1))
		_:
			_hud.announce(tr("RAID_AMBUSH"), Color(0.7, 1.0, 0.72, 1))


## Actually apply one relic. Shared by `_on_relic_picked` and recompute.
func _feed(relic: Relic, restore_health: bool = true) -> void:
	match relic.effect:
		Relic.Effect.ATTACK_RANGE:
			var want: float = _player.attack_range * relic.amount
			_player.attack_range = minf(want, 96.0)
			if want > 96.0:
				# Instead of slashing past the screen edge, turn leftover length into power.
				_damage_mult *= 1.0 + (want - 96.0) / 192.0
		Relic.Effect.ATTACK_SPEED:
			_relic_haste *= relic.amount
			_apply_haste()
		Relic.Effect.ATTACK_DAMAGE:
			_damage_mult *= relic.amount
			_player.attack_damage = _scaled(Player.DEFAULT_ATTACK_DAMAGE, _damage_mult)
		Relic.Effect.ATTACK_ARC:
			# Stops at 360°. Beyond that double-counts the same space and means nothing.
			#
			# Capping at 300° **killed the card at 3 stacks.** The blurb still said
			# "+50%" while nothing actually happened. At 360°, turn leftover into reach so the
			# card stays alive to the end.
			var want: float = _player.attack_arc * relic.amount
			_player.attack_arc = minf(want, 360.0)
			if want > 360.0:
				# Overflow past 360° turns into **damage.**
				#
				# First it went into reach, and the blade sprite grew until a **long gray bar** was drawn
				# on screen. Not a crescent — a plank.
				# Damage is an invisible axis, so it does not break the art.
				_damage_mult *= 1.0 + (want - 360.0) / 540.0
				_player.attack_damage = _scaled(Player.DEFAULT_ATTACK_DAMAGE, _damage_mult)
		Relic.Effect.MOVE_SPEED:
			_player.speed += relic.amount
		Relic.Effect.MAX_HEALTH:
			var before: int = _max_health
			_max_health = mini(
				_max_health + int(relic.amount), MAX_HEALTH_LIMIT)
			_hud.set_max_health(_max_health)
			if restore_health:
				_set_health(_health + _max_health - before)
		Relic.Effect.DASH_COOLDOWN:
			var want: float = _player.dash_cooldown_time * relic.amount
			_player.dash_cooldown_time = maxf(want, 0.45)
			if want < 0.45:
				# Below 0.45s the control becomes dash-mashing. Overflow haste becomes damage.
				_damage_mult *= 0.45 / maxf(want, 0.05)
		Relic.Effect.INVULNERABLE:
			_invulnerable_time += relic.amount
		Relic.Effect.DEW_CHANCE:
			_dew_multiplier *= relic.amount
		Relic.Effect.BEACON_HEAL:
			_beacon_heal += int(relic.amount)
		Relic.Effect.ARROW_COUNT:
			_arrow_count += int(relic.amount)
		Relic.Effect.ARROW_PIERCE:
			_arrow_pierce += int(relic.amount)
		Relic.Effect.ARROW_SPEED:
			_arrow_haste *= relic.amount
		Relic.Effect.ARROW_DAMAGE:
			_arrow_mult *= relic.amount
		Relic.Effect.MOON_RING:
			_grant_ring()
		Relic.Effect.MOON_RIPPLE:
			_grant_ripple()


## Turn a multiplier into integer damage.
##
## Truncating with `int()` makes two ×1.35 stacks go 1 → 1 → 1 and wipe both stacks entirely.
## Round and guarantee at least 1.
func _scaled(base: int, mult: float) -> int:
	return maxi(int(round(float(base) * mult)), 1)


## Damage multiplier moonfire awakening adds to every weapon.
func _moonfire_damage() -> float:
	return MOONFIRE_DAMAGE if _moonfire_on else 1.0


## Recompute stats from held relics from scratch.
##
## **Do not subtract in reverse.** Undoing one relic at a time means divide for multiply and
## subtract for add, but a clamped value (`attack_arc` at 300°) cannot be undone.
## One wrong division and stats stay quietly wrong for the rest of the run.
##
## Reset to defaults and re-apply what remains — that class of mistake becomes impossible.
## Even forty relics finish in under a millisecond — only called on hit.
func _recompute() -> void:
	var keep_health: int = _health
	var hero: Hero = _hero_for_run()
	_player.attack_range = Player.DEFAULT_ATTACK_RANGE
	_player.attack_arc = Player.DEFAULT_ATTACK_ARC
	_player.attack_damage = Player.DEFAULT_ATTACK_DAMAGE
	_player.speed = Player.DEFAULT_SPEED
	_player.dash_cooldown_time = Player.DEFAULT_DASH_COOLDOWN
	_relic_haste = 1.0
	_invulnerable_time = HIT_INVULNERABLE
	_dew_multiplier = 1.0
	_beacon_heal = 0
	_arrow_haste = 1.0
	_arrow_count = 1
	_arrow_pierce = 1
	_arrow_damage = ARROW_BASE_HIT
	_damage_mult = 1.0
	_arrow_mult = 1.0
	_arrow_haste = 1.0
	_max_health = mini(
		hero.health + int(Vault.grace(Boon.Grace.START_HEALTH)),
		MAX_HEALTH_LIMIT)

	# **Re-lay character and grace first.** Without this line every hit snaps the character back
	# to defaults. See `_base_stats()` above.
	_base_stats()

	# Mounted weapons are nodes. Free and rebuild them.
	if _ring != null and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null
	if _ripple != null and is_instance_valid(_ripple):
		_ripple.queue_free()
	_ripple = null

	for relic in _taken:
		# Re-applying a max-HP relic with healing would reward losing another relic by filling HP.
		# Recompute only the max; keep current HP.
		_feed(relic, false)
	_health = mini(keep_health, _max_health)
	_hud.set_max_health(_max_health)
	_hud.set_health(_health)
	_settle_rates()
	_refresh_aux_weapons()
	_refresh_evolution_hud()
	if not Relic.family_resonant(_taken, Relic.Family.FULL_MOON):
		_full_moon_primed = false
	if not Relic.family_resonant(_taken, Relic.Family.STARFALL):
		_starfall_primed = false


## After the first two kills, drop a moonlight core every 3–6 kill-value as ranks rise.
##
## Elites count as 3 and guardians as 10, but the field keeps only one regular core at a time.
## If the next quota is already full when a missed core is picked up or expires, drop the next one
## immediately at the last kill spot so the HUD does not sit full waiting for another kill.
func _gain_missile_progress(
		at: Vector2, was_elite: bool, was_guardian: bool) -> void:
	_missile_last_kill_at = at
	# During store capture, further kills must not change on-screen numbers.
	# See `debug_freeze_capture_progress()`.
	if _capture_progress_frozen:
		return
	# An ejected core is power not yet recovered. Wiping overcharge rewards or later kill progress
	# just because that core occupies the floor would erase the whole growth share when it expires.
	# Treat as complete only when live power and already-earned regular cores are both at max.
	var committed: int = _missile_power + _regular_cores_outstanding
	if committed >= MissileProgression.MAX_POWER:
		_missile_progress = 0
		_refresh_missile_hud()
		return
	_missile_progress += MissileProgression.kill_value(was_elite, was_guardian)
	_try_drop_missile_core(at)
	_refresh_missile_hud()


func _try_drop_missile_core(at: Vector2) -> void:
	if _regular_cores_outstanding > 0:
		return
	var needed: int = MissileProgression.threshold(_missile_threshold_power())
	if _missile_progress < needed:
		return
	var represented: int = _missile_power \
		+ _regular_cores_outstanding + _ejected_cores_outstanding
	if represented >= MissileProgression.MAX_POWER:
		return
	# One call changes one share. Remaining backlog is rejudged when a new core is collected or
	# expires, keeping a single regular core without recursive spawns.
	_missile_progress -= needed
	_regular_cores_outstanding += 1
	_regular_core_progress_escrow = needed
	_spawn_missile_core(at, false)
	if not _missile_core_help_shown:
		_missile_core_help_shown = true
		_hud.announce(
			tr("MISSILE_CORE_HELP"), Color(0.58, 0.88, 1.0, 1))


func _spawn_missile_core(at: Vector2, ejected: bool) -> void:
	var core: Area2D = MISSILE_CORE_SCENE.instantiate() as Area2D
	core.ejected = ejected
	core.target = _player
	core.bounds = Room.PLAY
	core.terrain_room = _room
	core.position = _room.nearest_clear(at, 12.0)
	core.collected.connect(_on_missile_core_collected)
	core.expired.connect(_on_missile_core_expired)
	_attach_missile_core.call_deferred(core)


## Clear logical state together before the result panel removes floor cores.
##
## Regular cores are growth already earned by kills, so restore their required progress and place
## them again after continue. Hit-ejected cores lost their recover chance — leave power lowered and
## only clear the counter. Otherwise outstanding stays with no sprite and permanently blocks the next core.
func _prepare_missile_cores_for_result() -> void:
	if _regular_cores_outstanding > 0:
		_missile_progress += _regular_core_progress_escrow
	_regular_cores_outstanding = 0
	_regular_core_progress_escrow = 0
	_ejected_cores_outstanding = 0
	_refresh_missile_hud()


## Hit signals arrive while scanning physics queries, so defer Area2D attach to the next idle.
func _attach_missile_core(core: Area2D) -> void:
	if _over or (OS.is_debug_build() and _debug_hero_direction_capture_active):
		core.queue_free()
		return
	add_child(core)
	if _transitioning and core.has_method("set_transition_paused"):
		core.set_transition_paused(true)


## On hit, eject one visible missile-power rank — not a relic.
func _eject_missile_power() -> void:
	if _missile_power <= 0:
		return
	var before: int = _missile_power
	_missile_power -= 1
	_ejected_cores_outstanding += 1
	_refresh_missile_hud()
	_hud.announce(tr("MISSILE_DROPPED") % [before, _missile_power],
		Color(1.0, 0.58, 0.42, 1))
	_spawn_missile_core(_player.global_position, true)


## Mount one orbiting orb. If one already exists, attach another.
##
## Parent under the player so it **follows.** Syncing position every frame lags one frame and
## looks like it is being dragged behind.
func _grant_ring() -> void:
	if _ring == null or not is_instance_valid(_ring):
		_ring = MoonRing.new()
		_ring.damage = AUX_BASE_HIT
		_ring.set_candidates(_spirits)
		_ring.position = Player.BODY_CENTER
		_player.add_child(_ring)
	else:
		_ring.count += 1


## Mount a spreading ripple. If one exists, make it wider and more frequent.
func _grant_ripple() -> void:
	if _ripple == null or not is_instance_valid(_ripple):
		_ripple = RIPPLE_SCENE.instantiate() as MoonRipple
		_ripple.set_candidates(_spirits)
		_ripple.position = Player.BODY_CENTER
		_player.add_child(_ripple)
		return
	_ripple.rank += 1


## The two node-mounted weapons also follow awakening start/end immediately.
func _refresh_aux_weapons() -> void:
	var dance: bool = Relic.family_evolved(_taken, Relic.Family.MOON_DANCE)
	# Raise more than the damage number — stack slash afterimages one layer at a time.
	_player.slash_rank = Relic.family_total(_taken, Relic.Family.FULL_MOON)
	# Apply hero damage, low-HP frailty, and awakening to every weapon by the same rule.
	# If only ranged and side weapons dodge the crisis penalty, a safe build is always the answer.
	var common: float = _damage_mult * _frailty() * _moonfire_damage()
	if _ring != null and is_instance_valid(_ring):
		_ring.evolved = dance
		var overflow: int = _ring.overflow_count()
		_ring.damage = _scaled(AUX_BASE_HIT,
			pow(1.24, float(_ring.count - 1))
			* (1.0 + 0.16 * float(overflow))
			* (1.22 if dance else 1.0)
			* common)
	if _ripple != null and is_instance_valid(_ripple):
		_ripple.evolved = dance
		_ripple.damage = _scaled(AUX_BASE_HIT,
			pow(1.26, float(_ripple.rank - 1))
			* (1.22 if dance else 1.0)
			* common)


func _on_missile_core_collected(was_ejected: bool) -> void:
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		return
	if was_ejected:
		_invalidate_debug_missile_capture()
		_ejected_cores_outstanding = maxi(_ejected_cores_outstanding - 1, 0)
	else:
		_regular_cores_outstanding = maxi(_regular_cores_outstanding - 1, 0)
		_regular_core_progress_escrow = 0
		_first_missile_core_collected = true
		_onboard("TUTORIAL_CORE")
		_analytics_tutorial_step("core")
	if _over:
		return

	if was_ejected:
		# An ejected core returns as 70% of the next-rank progress, not the power itself.
		# Returning a full rank meant picking the core back up restored everything in a second after a hit,
		# so taking damage had no weight. The lost rank must be fought for again.
		var represented: int = _missile_power \
			+ _regular_cores_outstanding + _ejected_cores_outstanding
		if represented < MissileProgression.MAX_POWER:
			var recovered: int = MissileProgression.eject_recovery_progress(
				_missile_power)
			_missile_progress += recovered
			_try_drop_missile_core(_missile_last_kill_at)
			_hud.announce(tr("MISSILE_RESTORED") % recovered,
				Color(0.62, 0.92, 1.0, 1))
		_refresh_missile_hud()
		_pickup_sfx.pitch_scale = 1.0 + 0.04 * float(_missile_power)
		_pickup_sfx.play()
		return

	_missile_power = mini(_missile_power + 1, MissileProgression.MAX_POWER)
	if _missile_power >= MissileProgression.MAX_POWER:
		_missile_progress = 0
	_try_drop_missile_core(_missile_last_kill_at)
	_refresh_missile_hud()
	_arrow_timer = 0.0
	_player.play_starfall_preview(_missile_volley())
	if _missile_power >= MissileProgression.MAX_POWER:
		_hud.announce(tr("MISSILE_COMPLETE") % [
			_missile_power, MissileProgression.MAX_POWER],
			Color(1.0, 0.84, 0.42, 1))
	elif _missile_power == MissileProgression.HOMING_AT:
		_hud.announce(tr("MISSILE_HOMING") % [
			_missile_power, MissileProgression.MAX_POWER],
			Color(0.72, 0.7, 1.0, 1))
	else:
		_hud.announce(tr("MISSILE_POWER_UP") % [
			_missile_power, MissileProgression.MAX_POWER],
			Color(0.58, 0.88, 1.0, 1))
	_pickup_sfx.pitch_scale = 1.0 + 0.04 * float(_missile_power)
	_pickup_sfx.play()


func _on_missile_core_expired(was_ejected: bool) -> void:
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		return
	if was_ejected:
		_invalidate_debug_missile_capture()
		_ejected_cores_outstanding = maxi(_ejected_cores_outstanding - 1, 0)
	else:
		_regular_cores_outstanding = maxi(_regular_cores_outstanding - 1, 0)
		_regular_core_progress_escrow = 0
	if _over:
		return
	_try_drop_missile_core(_missile_last_kill_at)
	_refresh_missile_hud()
	if was_ejected:
		_hud.announce(tr("MISSILE_LOST") % _missile_power,
			Color(1.0, 0.48, 0.4, 1))


## A spirit scattered. Score and kill count are tallied here.
##
## A spirit only reports its own death.
func _on_spirit_perished(kind: SpiritKind, at: Vector2, was_elite: bool) -> void:
	# Meteors already in flight can still kill after the run ends. If that kill levels up,
	# **a relic card opens over the result/ladder panel** and even pauses the tree.
	if _over or (OS.is_debug_build() and _debug_hero_direction_capture_active):
		return
	_kills += 1
	_kill_score += kind.score_value
	_queue_combat_hud()
	_drop_moon_ember(at, was_elite)
	_maybe_drop_dew(at, was_elite)
	# Even when a guardian kill overlaps a level threshold, a normal card must not open first.
	# `_on_relic_picked()` continues owed picks after the guardian loot is chosen.
	var was_guardian: bool = _guardian != null \
		and is_instance_valid(_guardian) and kind == _guardian.kind
	if was_guardian:
		_analytics_guardians += 1
		var guardian_path: String = str(_guardian.get_meta(
			GUARDIAN_KIND_SOURCE_PATH_META, "res://resources/guardian.tres"))
		_analytics_track("guardian_defeated", {
			"guardian": _analytics_resource_id(guardian_path),
			"terrain": _analytics_terrain_id(),
			"cycle": _cycle,
			"duration_ms": maxi(
				_analytics_elapsed_ms() - _analytics_guardian_started_ms, 0),
			"elapsed_ms": _analytics_elapsed_ms(),
		})
	_gain_missile_progress(at, was_elite, was_guardian)
	_gain_progress(not was_guardian)
	_heat_up()
	# Pricier heroes get a heavier kill recoil. **Presentation only** —
	# damage, fire rate, and pierce stay sidegrade-equal; only the weight in the hand
	# follows the tier.
	_shake(0.9 + 0.5 * float(_combo_tier) + 0.16 * float(_hero_vfx_tier()))


## Leave a moon ember at the kill spot.
##
## Level progress still rises immediately as before. Embers are not XP stolen from that progress;
## they are separate loot for a short power burst, so missing them does not block growth.
func _drop_moon_ember(at: Vector2, was_elite: bool) -> void:
	var charge: float = ELITE_EMBER_CHARGE if was_elite else EMBER_CHARGE
	if get_tree().get_node_count_in_group("moon_embers") + _pending_embers >= EMBER_LIMIT:
		_gain_moonfire(charge)
		return

	_pending_embers += 1
	_ember_positions.append(at)
	_ember_elites.append(was_elite)


## Build chain-kill loot across several render frames. Count, charge, and position stay the same;
## only spawn timing slips by a few frames at most.
func _flush_ember_drops() -> void:
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		_ember_positions.clear()
		_ember_elites.clear()
		_pending_embers = 0
		return
	if _ember_positions.is_empty():
		return
	if _over:
		_ember_positions.clear()
		_ember_elites.clear()
		_pending_embers = 0
		return
	var many: int = mini(_ember_positions.size(), 4)
	for i in many:
		var at: Vector2 = _ember_positions.pop_front()
		var was_elite: bool = _ember_elites.pop_front()
		var ember: Node2D = EMBER_SCENE.instantiate() as Node2D
		_pending_embers = maxi(_pending_embers - 1, 0)
		ember.charge = ELITE_EMBER_CHARGE if was_elite else EMBER_CHARGE
		ember.elite = was_elite
		ember.target = _player
		ember.position = at
		ember.collected.connect(_on_ember_collected)
		add_child(ember)


func _on_ember_collected(charge: float, _at: Vector2) -> void:
	if _over or (OS.is_debug_build() and _debug_hero_direction_capture_active):
		return
	var shown_charge: int = 10 if _moonfire_on \
		else mini(roundi(_moonfire_charge + charge), 10)
	_gain_moonfire(charge)
	if not _ember_help_shown:
		_ember_help_shown = true
		_hud.announce(tr("EMBER_HELP") % shown_charge,
			Color(0.48, 0.86, 1.0, 1))
	_pickup_sfx.pitch_scale = 1.16 if charge > EMBER_CHARGE else 0.96 \
		+ 0.025 * float(int(_moonfire_charge) % 5)
	_pickup_sfx.play()


## Fire a moon arrow. It aims the nearest spirit on its own.
##
## Second weapon on its own clock from slash. Slash needs contact; the arrow reaches far —
## **overlapping ranges create "where should I stand."**
func _fire_arrows(delta: float) -> void:
	_arrow_timer -= delta
	if _arrow_timer > 0.0:
		return

	var target: Node2D = _nearest_in(ARROW_RANGE)
	if target == null:
		return                                   # Save the shot if nobody is in range

	_arrow_timer = _arrow_cooldown

	if _starfall_evolved() or _starfall_primed:
		_starfall_primed = false
		_fire_missiles(target)
		return

	# New guardians hold no weapon — both hands cradle a beacon seed. Shots must start from that
	# seed, not body origin or feet, so cast and fire read as one motion.
	var origin: Vector2 = _player.moonlight_origin()
	var base: Vector2 = (target.global_position - origin).normalized()

	# The first shot always goes to the target's exact center.
	#
	# Two early shots split ±27° and **both missed.** At max range they were 109px apart while the
	# combined hit radius is only 11px, so the first multi-shot upgrade was a downgrade.
	# Pin the center shot and fan extras left/right in turn. An even volley's leftover shot flips
	# sides each fire so it does not bias one way.
	const ARROW_HALF_FAN: float = 27.0
	var invest: int = _arrow_invest()
	var volley: int = _missile_volley()
	var total_damage: int = MissileProgression.damage_budget(
		_arrow_damage, _missile_power, maxi(_arrow_count - 1, 0))
	var lane_damages: PackedInt32Array = MissileProgression.straight_lane_damages(
		total_damage, volley)
	_player.play_moonlight_cast(base, volley)
	var extra: int = maxi(volley - 1, 0)
	var rings: int = maxi(int(ceil(float(extra) * 0.5)), 1)
	var first_side: float = _arrow_fan_side
	_arrow_fan_side *= -1.0
	for i in volley:
		var angle: float = 0.0
		if i > 0:
			var lane: int = i
			var ring: int = (lane + 1) / 2
			var side: float = first_side if lane % 2 == 1 else -first_side
			angle = deg_to_rad(ARROW_HALF_FAN) * float(ring) / float(rings) * side
		var arrow: Node2D = ARROW_SCENE.instantiate()
		arrow.pierce = _arrow_pierce
		arrow.damage = lane_damages[i]
		arrow.upgrade_rank = _missile_power + invest
		arrow.awakened = _moonfire_on
		_configure_hero_projectile(arrow, i, volley)
		arrow.set_candidates(_spirits, get_instance_id())
		add_child(arrow)
		arrow.global_position = origin
		arrow.launch(base.rotated(angle))
		arrow.reset_physics_interpolation()


## How much is invested in the meteor-shower card. Drives volley look and card evolution.
func _arrow_invest() -> int:
	return Relic.family_total(_taken, Relic.Family.STARFALL)


func _missile_volley() -> int:
	return MissileProgression.volley_for_power(_missile_power)


func _missile_threshold_power() -> int:
	if not _first_missile_core_collected and _missile_power <= 0:
		return 0
	# A rank briefly lost to a hit can be recovered, so do not lower the next-kill requirement either.
	return clampi(
		_missile_power + _ejected_cores_outstanding,
		0,
		MissileProgression.MAX_POWER - 1)


func _refresh_missile_hud() -> void:
	var needed: int = MissileProgression.threshold(_missile_threshold_power())
	_hud.set_missile_power(
		_missile_power,
		MissileProgression.MAX_POWER,
		mini(_missile_progress, needed),
		needed,
		_regular_cores_outstanding + _ejected_cores_outstanding > 0)


## If several ranks ejected at once, point at the core that will vanish first.
func _tick_missile_recovery_hud() -> void:
	var urgent: Node2D = null
	var seconds_left: float = INF
	for candidate in get_tree().get_nodes_in_group("missile_cores"):
		if not is_instance_valid(candidate) or not bool(candidate.get("ejected")) \
				or not candidate.has_method("remaining_seconds"):
			continue
		var remaining: float = float(candidate.call("remaining_seconds"))
		if remaining < seconds_left:
			seconds_left = remaining
			urgent = candidate as Node2D
	if urgent == null:
		_hud.clear_missile_recovery()
		return
	_hud.set_missile_recovery(
		seconds_left,
		urgent.global_position - _player.global_position,
		true)


func _starfall_evolved() -> bool:
	# A build that finished all four meteor effects keeps homing regardless of awakening —
	# the peak reward for a late build that recovered six cards of investment.
	if Relic.family_evolved(_taken, Relic.Family.STARFALL):
		return true
	# Always-on homing needed neither aim nor positioning and drew "too broken" feedback.
	# Normally fire a straight fan that widens with power (like a shmup trail), and only during
	# moonfire awakening does full-volley homing unlock briefly — the short reward feel of an
	# invuln pickup. Shot count and damage curves stay the same in both modes.
	return _moonfire_on and MissileProgression.is_homing(_missile_power)


## Fire one meteor volley.
##
## Unlike arrows, **targets are split.** Eight shots on one body waste the rest and leave one
## stacked blast on screen. Round-robin nearest-first makes missiles scatter, then each
## curves in.
func _fire_missiles(first: Node2D) -> void:
	var invest: int = _arrow_invest()
	var volley: int = _missile_volley()
	var origin: Vector2 = _player.moonlight_origin()
	var lane_damages: PackedInt32Array = MissileProgression.guided_lane_damages(
		_arrow_damage, _missile_power, maxi(_arrow_count - 1, 0))
	var marks: Array[Node2D] = _nearest_many(ARROW_RANGE * 1.3, volley)
	if marks.is_empty():
		marks.append(first)

	var cast_direction: Vector2 = (first.global_position - origin).normalized()
	_player.play_moonlight_cast(cast_direction, volley)
	_shake(0.6 + 0.14 * float(_hero_vfx_tier()))
	var missile: Node2D = MISSILE_SCENE.instantiate()
	missile.damage = lane_damages[0]
	missile.pierce = _arrow_pierce
	missile.upgrade_rank = _missile_power + invest
	missile.awakened = _moonfire_on
	_configure_hero_projectile(missile)
	# Every live volley shares one computation of spirit positions for this physics tick.
	missile.set_candidates(_spirits, get_instance_id())
	add_child(missile)
	missile.global_position = origin
	missile.launch_volley(marks, volley, lane_damages)
	missile.reset_physics_interpolation()


## A hero's combat grammar reaches only projectile path, color, and hit VFX. Damage, pierce, and
## volley count were already set by the growth curve above — do not multiply again by profile or
## price tier. That boundary stops a paid hero from hitting harder at the same core rank.
func _configure_hero_projectile(
		projectile: Node,
		lane_index: int = 0,
		lane_total: int = 1,
	) -> void:
	if projectile == null or not projectile.has_method("configure_profile"):
		return
	var hero: Hero = _hero_for_run()
	projectile.call(
		"configure_profile",
		hero.attack_profile,
		hero.projectile_primary,
		hero.projectile_secondary,
		hero.vfx_tier,
		lane_index,
		lane_total)


## Up to `want` spirits in range, nearest first.
func _nearest_many(reach: float, want: int) -> Array[Node2D]:
	var found: Array[Node2D] = []
	var reach_sq: float = reach * reach
	for spirit in _spirits:
		if not is_instance_valid(spirit) or not spirit.is_attackable():
			continue
		if _player.global_position.distance_squared_to(spirit.global_position) <= reach_sq:
			found.append(spirit)
	found.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return _player.global_position.distance_squared_to(a.global_position) \
			< _player.global_position.distance_squared_to(b.global_position))
	if found.size() > want:
		found.resize(want)
	return found


## Nearest spirit inside this distance.
func _nearest_in(reach: float) -> Node2D:
	var best: Node2D = null
	var best_distance_sq: float = reach * reach
	for spirit in _spirits:
		if not is_instance_valid(spirit) or not spirit.is_attackable():
			continue
		var distance_sq: float = spirit.global_position.distance_squared_to(
			_player.global_position)
		if distance_sq <= best_distance_sq:
			best = spirit
			best_distance_sq = distance_sq
	return best


## Shake the screen briefly.
##
## **A hit must leave something on screen or it has no feel.** Spirits only vanishing is no different
## from a number going up. Harder shakes as heat rises make a pack push loud.
##
## Camera `offset` shakes only the world canvas and leaves a separate `CanvasLayer` HUD alone.
## Moving only the room node shakes the picture while structure coords used by player/spirits stay
## put, creating a few-pixel invisible wall — shake the whole world with the same screen transform.
## This run's hero presentation tier (0–5). Same order as price.
##
## **Screen shake and flash only.** If this value leaks into damage, fire rate, pierce, or other
## numbers, the sidegrade contract breaks and it becomes pay-to-win.
func _hero_vfx_tier() -> int:
	var hero: Hero = _hero_for_run()
	return 0 if hero == null else clampi(hero.vfx_tier, 0, 5)


func _shake(strength: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	_shake_power = maxf(_shake_power, minf(strength, 4.0))
	_shake_left = maxf(_shake_left, 0.165)


func _tick_shake(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		_shake_power = 0.0
		_shake_left = 0.0
		return
	if _shake_left <= 0.0:
		if _camera.offset != Vector2.ZERO:
			_camera.offset = Vector2.ZERO
		return
	_shake_left = maxf(_shake_left - delta, 0.0)
	_shake_step_left -= delta
	if _shake_step_left <= 0.0:
		_shake_step_left += 0.035
		_camera.offset = Vector2(
			randf_range(-_shake_power, _shake_power),
			randf_range(-_shake_power, _shake_power))
	if _shake_left <= 0.0:
		_stop_shake()


func _stop_shake() -> void:
	_shake_power = 0.0
	_shake_left = 0.0
	_shake_step_left = 0.0
	if _camera != null and is_instance_valid(_camera):
		_camera.offset = Vector2.ZERO


## Floor the fire interval and turn overflow into damage.
##
## **Without a floor the game stalls.** When only `_arrow_cooldown *= 0.7` existed,
## eight stacks of `Quick Draw` made the interval 0.066s — 181 shots per second.
## Missile lifetime is 2.8s, so **507 lived at once.** All run `Area2D`
## `_physics_process` and `_draw()`. Measured 60fps → **2fps**.
##
## Just clamping repeats the 300° fan-cap mistake — the card dies.
## Turn overflow ratio into damage so growth continues while node count is capped.
## Growth is **damage per second**, not shots per second, so the feel continues too.
const ARROW_CD_FLOOR: float = 0.34
const MELEE_CD_FLOOR: float = 0.11


func _settle_rates() -> void:
	var moonfire_rate: float = MOONFIRE_HASTE if _moonfire_on else 1.0
	var raw: float = ARROW_COOLDOWN * _arrow_haste * moonfire_rate
	var over: float = 1.0
	if raw < ARROW_CD_FLOOR:
		over = ARROW_CD_FLOOR / raw
		raw = ARROW_CD_FLOOR
	_arrow_cooldown = raw
	_arrow_damage = _scaled(ARROW_BASE_HIT,
		_arrow_mult * over * _moonfire_damage() * _frailty())
	_apply_haste()
	_refresh_aux_weapons()


## As health drops, the hand gets heavier.
##
## **Always at full power and HP is only a number.** Five hearts or one feeling the same means
## getting hit does not hurt, and if it does not hurt there is no reason to dodge.
##
## A hit already drops one missile rank, so a 65% low-HP penalty on top becomes an unrecoverable
## death spiral. Leave 85% at one heart — crisis is felt, but enough power remains to reclaim the
## ejected core.
const FRAIL_FLOOR: float = 0.85


## Power multiplier from current HP. Multiplies attack interval.
func _frailty() -> float:
	# Scale by "fraction of hearts lost," not "hearts left."
	#
	# Raw `ratio` never reaches the floor at one heart.
	# Rescale so one heart equals the floor.
	var full: float = float(maxi(_max_health, 1))
	var ratio: float = (float(_health) - 1.0) / maxf(full - 1.0, 1.0)
	return lerpf(FRAIL_FLOOR, 1.0, clampf(ratio, 0.0, 1.0))


## The more you push a pack, the faster the hand gets.
##
## This is how **"don't kite — dive in"** is taught in the fingers, not in words.
## Heat up and slash faster; slash faster and heat up more. Break the streak once and
## you start over — greed meets risk.
func _heat_up() -> void:
	_combo += 1
	_combo_left = COMBO_WINDOW
	var tier: int = mini(_combo / COMBO_STEP, COMBO_MAX_TIER)
	if tier != _combo_tier:
		_combo_tier = tier
		_apply_haste()
	_queue_combat_hud()


## Heat cools down.
func _cool_down(delta: float) -> void:
	if _combo <= 0:
		return
	_combo_left -= delta
	if _combo_left > 0.0:
		return
	_combo = 0
	_combo_tier = 0
	_apply_haste()
	_queue_combat_hud()


## Reflect only the last value on an idle frame so one tick's AoE kills do not rewrite the same
## Label/gauge many times. Score, level, and attack-speed math already finished above.
func _queue_combat_hud() -> void:
	if _combat_hud_queued:
		return
	_combat_hud_queued = true
	_flush_combat_hud.call_deferred()


func _flush_combat_hud() -> void:
	_combat_hud_queued = false
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		_hud.set_kills(0)
		_hud.set_combo(0, 0)
		_hud.set_level_progress(0.0)
		return
	if _over or not is_inside_tree():
		return
	_hud.set_kills(_kills)
	_hud.set_combo(_combo, _combo_tier)
	_hud.set_level_progress(float(_level_progress) / float(maxi(_to_next, 1)))


## Put a moon ember into the gauge.
##
## During awakening do not secretly fill the next gauge. Instead extend time a little per ember.
## A good streak keeps the flame longer, but it is never locked on forever.
func _gain_moonfire(amount: float) -> void:
	if amount <= 0.0:
		return
	# During store capture, freeze moonfire numbers too. They set the left HUD panel's width, so a
	# before/after change fails all five locales.
	if _capture_progress_frozen:
		return
	if _moonfire_on:
		if not _moonfire_locked:
			_moonfire_left = minf(_moonfire_left + 0.16 * amount, MOONFIRE_SECONDS * 1.35)
			_hud.set_moonfire(_moonfire_left / MOONFIRE_SECONDS, true, false)
		return

	_moonfire_charge = minf(_moonfire_charge + amount, MOONFIRE_MAX)
	_hud.set_moonfire(_moonfire_charge / MOONFIRE_MAX, false, false)
	if _moonfire_charge >= MOONFIRE_MAX:
		_activate_moonfire(false)


## Heat every weapon. When the third beacon calls, lock until the guardian falls.
func _activate_moonfire(locked: bool, announce: bool = true) -> void:
	var was_on: bool = _moonfire_on
	if not was_on:
		_say("moonfire")
	_moonfire_on = true
	_moonfire_locked = _moonfire_locked or locked
	_moonfire_charge = 0.0
	_moonfire_left = MOONFIRE_SECONDS
	_player.set_moonfire(true, _moonfire_locked)
	_settle_rates()
	_refresh_aux_weapons()
	_hud.set_moonfire(1.0, true, _moonfire_locked)
	if announce:
		_hud.announce(tr("MOONFIRE_AWAKENED"), Color(0.72, 0.9, 1, 1))
	if not was_on:
		_event_sfx.pitch_scale = 1.18
		_event_sfx.play()
		_shake(2.2)


## Tick down awakening time only in normal combat with no guardian.
func _tick_moonfire(delta: float) -> void:
	if not _moonfire_on or _moonfire_locked:
		return
	_moonfire_left = maxf(_moonfire_left - delta, 0.0)
	_hud.set_moonfire(_moonfire_left / MOONFIRE_SECONDS, true, false)
	if _moonfire_left > 0.0:
		return
	_end_moonfire()


func _end_moonfire() -> void:
	_moonfire_on = false
	_moonfire_locked = false
	_moonfire_left = 0.0
	_player.set_moonfire(false)
	_settle_rates()
	_refresh_aux_weapons()
	_hud.set_moonfire(_moonfire_charge / MOONFIRE_MAX, false, false)


## Apply the attack interval for the current rank.
##
## Relics may already have multiplied `attack_cooldown_time`, so **do not overwrite.**
## Keep the relic share in `_relic_haste` and multiply together here.
func _apply_haste() -> void:
	var heat: float = 1.0 - COMBO_HASTE * float(_combo_tier)
	var moonfire_rate: float = MOONFIRE_HASTE if _moonfire_on else 1.0
	# Lower power lengthens the interval. Divide because `_frailty()` is ≤ 1.
	var raw: float = Player.DEFAULT_ATTACK_COOLDOWN * _relic_haste * heat \
		* moonfire_rate / _frailty()

	# Melee gets a floor too. Same reason as `_settle_rates()` above — when the interval falls under a
	# physics tick the relic does nothing, and four swings a frame only stack VFX.
	var over: float = 1.0
	if raw < MELEE_CD_FLOOR:
		over = MELEE_CD_FLOOR / raw
		raw = MELEE_CD_FLOOR
	_player.attack_cooldown_time = raw
	_player.attack_damage = _scaled(Player.DEFAULT_ATTACK_DAMAGE,
		_damage_mult * over * _moonfire_damage())


## Kills raise level, and each level picks one relic.
##
## **This is the heart of endless growth.** Relics-only-after-three-beacons meant three picks and
## done. Hang them on kills and there is no end — the longer you last, the stronger you stay.
func _gain_progress(offer_now: bool = true) -> void:
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		return
	_level_progress += 1
	if _level_progress < _to_next:
		_queue_combat_hud()
		return

	_level_progress = 0
	_level += 1
	_to_next = mini(int(ceil(float(_to_next) * LEVEL_GROWTH)), LEVEL_CAP)
	_hud.set_level(_level)
	_queue_combat_hud()
	_owed += 1
	if offer_now:
		_queue_relic_offer()


## Offer owed relics. **If too frequent, batch them into one pause.**
##
## Faster growth created a new problem — at heat, ten kills a second meant **the level-up panel
## opened every second and kept pausing the game.** Picking a card became interruption,
## not reward.
##
## Levels still rise fast; only the panel is batched. Owed picks chain, so nothing is lost, and
## combat gets stretches that keep flowing.
const OFFER_GAP: float = 5.5


func _queue_relic_offer() -> void:
	if _relic_offer_queued:
		return
	_relic_offer_queued = true
	_open_queued_relic_offer.call_deferred()


func _open_queued_relic_offer() -> void:
	_relic_offer_queued = false
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		return
	_offer_relic()


func _offer_relic() -> void:
	if _over or _owed <= 0 or _relic.visible \
			or _cycle_reward_queued or _cycle_reward_pending \
			or _run_choice.visible \
			or _pending_beacon_choice != null or _overcharge_beacon != null \
			or _escape_active or _transitioning \
			or get_tree().paused \
			or (_guardian != null and is_instance_valid(_guardian)):
		return
	# When a guardian kill overlaps level-up, settle only after all owed normal relics are taken.
	# Waiting the usual gap lets the new cycle's combat run first; blocking the decision wait forever
	# deadlocks relic and settlement on each other — so this path alone continues immediately.
	if not _cycle_decision_queued and _survived - _last_offer < OFFER_GAP:
		return
	_last_offer = _survived
	_owed -= 1
	_relic.open()


func _try_open_cycle_reward() -> void:
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		_cycle_reward_queued = false
		_cycle_reward_pending = false
		return
	if not _cycle_reward_queued or _over \
			or _relic.visible or _run_choice.visible \
			or _pending_beacon_choice != null or _overcharge_beacon != null \
			or get_tree().paused:
		return
	_cycle_reward_queued = false
	_cycle_reward_pending = true
	_relic.open_guardian(tr("GUARDIAN_REWARD"), _cycle_reward_grant_count)


## One-run settlement choice opened only after guardian rewards. Open on an idle boundary after
## normal level-up cards and dialogue are all closed so modals do not stack.
func _try_open_cycle_decision() -> void:
	if not _cycle_decision_queued or _over or _transitioning \
			or _relic.visible or _result.visible or _run_choice.visible \
			or _pending_beacon_choice != null or _overcharge_beacon != null \
			or _owed > 0 or get_tree().paused:
		return
	_player.set_move_input(Vector2.ZERO)
	_stick.set_active(false)
	_pause.set_available(false)
	_run_choice.open_cycle(_completed_cycle)


## Guardian down. Close the cycle and open the next.
##
## **The reward should be big, but do not wipe all damage.** For hunting three beacons and dropping
## the boss, grant one attack-path rank and one heart while keeping the previous cycle's wounds.
func _finish_cycle() -> void:
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		return
	_completed_cycle = _cycle
	_completed_cycle_overcharges = clampi(_overcharge_successes, 0, _beacons.size())
	_cycle_reward_grant_count = 2 if _overcharge_successes >= _beacons.size() else 1
	_overcharge_successes = 0
	_cycle += 1
	_zone_serial += 1
	_zone_index = 0
	_escape_active = false
	_transitioning = false
	_gate.close()
	_zone_wipe.visible = false
	# The loot panel pauses the game immediately, so waiting for the next `_process()` leaves the boss
	# HP bar behind the panel. Clear it first at the guardian signal.
	_hud.set_boss(false)
	# Close the duel’s threats where the duel ended so a leftover prior-guardian shot cannot knock off
	# a relic just received after the reward pick.
	_clear_hostile_projectiles()
	_clear_friendly_projectiles()
	# Shots whose `add_child` was reserved in the same physics tick are not in the group yet. Clear
	# once more after those reserved adds so even one shot crossing into the new cycle is closed.
	_clear_hostile_projectiles.call_deferred()
	_clear_friendly_projectiles.call_deferred()

	# Full heal would reset every cycle's damage and favor endless stalling.
	_set_health(_health + CYCLE_HEAL)

	# Unlock awakening locked during the guardian fight and return to explore music.
	_moonfire_charge = 0.0
	_end_moonfire()
	_bgm.stop()
	_bgm.stream = ARENA_THEME
	_bgm.pitch_scale = _arena_bgm_pitch()
	_bgm.play()
	# Guardian cleared. One line before the next peak.
	_say("guardian_down")
	_show_cycle_story()

	# Beacons go dark again. Spots also move — looping the same places gets dull.
	for beacon in _beacons:
		beacon.reset()
	_lit_count = 0
	_hud.set_beacons(0, _beacons.size())
	_hud.set_cycle(_cycle)

	# Skip the normal level-up's 5.5s queue. Boss loot must show immediately with a dedicated title
	# and a locked three-path attack pick to read as a cycle reward.
	#
	# **Open the loot panel first.** Order: panel sets `get_tree().paused` and covers the screen,
	# then build the new terrain. Reverse it and one frame of scattering 380 props runs on a bare
	# screen — a hitch that feels like "cleared, then froze, then started." Terrain travel already
	# builds under a wipe (`ZONE_FADE_SECONDS`); only cycle transition was missing that.
	_cycle_reward_queued = true
	_try_open_cycle_reward.call_deferred()

	# Build the new terrain outside a physics collision callback, then place beacons from that
	# structure list. Reverse the order and an empty coord in the old room can be mid-menhir in the new.
	_change_cycle_world.call_deferred()

	# Trash returns.
	_spawn_timer = 2.0


func _change_cycle_world() -> void:
	if _over or not is_inside_tree() \
			or (OS.is_debug_build() and _debug_hero_direction_capture_active):
		return
	_change_world(false)
	_place_beacons()


## Decide whether to drop moon dew.
##
## Three branches.
##
## 1. **At full HP, convert only a rolled drop into score.** Scoring every kill would turn heal
##    chance into a full-HP bonus.
##    Uncollectable pickups littering the floor make the chance meaningless and the screen messy.
## 2. **At one heart the chance rises.** A breath right before death.
##    Do not announce it on screen — that reads as "they're going easy" and kills tension.
## 3. Otherwise the base chance.
func _maybe_drop_dew(at: Vector2, was_elite: bool = false) -> void:
	var outstanding: int = \
		get_tree().get_node_count_in_group("moon_dews") + _pending_dews
	# Elite guaranteed rescue is only once, near death, when no dew is on the field.
	var mercy: bool = was_elite and _health == 1 and outstanding == 0
	# Capping only live count lets the next dew spawn the instant one is picked, so late-game heal
	# rate scales with kill speed. Normal drops share one field clock and close at five per minute.
	if not mercy and _dew_drop_cooldown > 0.0:
		return
	var chance: float = (DEW_CHANCE_LOW if _health <= 1 else DEW_CHANCE) * _dew_multiplier
	if not mercy and randf() > chance:
		return
	if _health >= _max_health:
		# Full-HP score conversion also consumed one "rolled normal dew." Leaving the clock open here
		# would let another normal dew roll in the same tick right after taking damage.
		_dew_drop_cooldown = DEW_DROP_COOLDOWN
		_kill_score += DEW_FULL_HEALTH_SCORE
		return
	if outstanding >= DEW_LIMIT:
		return

	_dew_drop_cooldown = DEW_DROP_COOLDOWN
	var dew: Area2D = DEW_SCENE.instantiate()
	dew.position = at
	dew.set("target", _player)
	dew.set_meta(&"zone_serial", _zone_serial)
	dew.collected.connect(_on_dew_collected)
	# A spirit scattering is mid physics — a missile hits via `body_entered` and
	# `_perish` runs inside that. Attaching an `Area2D` there dies with
	# `Can't change this state while flushing queries`.
	_pending_dews += 1
	_attach_dew.call_deferred(dew)


func _attach_dew(dew: Area2D) -> void:
	_pending_dews = maxi(_pending_dews - 1, 0)
	if _over or (OS.is_debug_build() and _debug_hero_direction_capture_active) \
			or int(dew.get_meta(&"zone_serial", -1)) != _zone_serial:
		dew.queue_free()
		return
	add_child(dew)


## Dew was collected.
func _on_dew_collected(amount: int, _at: Vector2) -> void:
	if _over or (OS.is_debug_build() and _debug_hero_direction_capture_active):
		return
	_set_health(_health + amount)


## The only place that sets health.
##
## **Each heal path used to write separately and one was missed.** `_frailty()` hooks attack
## interval, but dew or beacon heals never called `_apply_haste()`, so even after returning to full
## HP there was a stretch fought at minimum power. The comment said "one dew heart brings the feel
## back" while the code never did.
##
## Future heal sources that only pass through here cannot miss it again.
func _set_health(value: int) -> void:
	var before: int = _health
	_health = clampi(value, 0, _max_health)
	_hud.set_health(_health)
	_settle_rates()
	# Speak only on the **moment of falling** to the last heart. Repeating while fighting in that
	# state turns the line into an alarm, not dialogue.
	if _health == 1 and before > 1:
		_say("low_health")


## Keep only living spirits. From Lesson 13 they appear and vanish.
func _prune_spirits() -> void:
	# Do not put a typed lambda in `filter()`.
	#
	# Writing `func(s: Node2D)` **failed the cast the moment a freed object was passed**, so
	# every call printed two error lines.
	#
	#     Cannot convert argument 1 from Object to Object.
	#     Trying to assign an array of type "Array" to a variable of type "Array[Node2D]"
	#
	# Worse: **the assignment fails and the dead reference stays.**
	# Dead spirits then occupy the `MAX_SPIRITS` roster and new ones never spawn.
	#
	# Through Lesson 13 spirits mostly only vanished via `retreat()`, so it rarely hit. Once they
	# could be cut, every death blew up. Caught in device logcat — `game:check` cannot see this.
	# Keep the same Array instance. Rings, ripples, and just-fired projectiles share this list;
	# swapping in a new array means later-born spirits are never seen again.
	for i in range(_spirits.size() - 1, -1, -1):
		if not is_instance_valid(_spirits[i]):
			_spirits.remove_at(i)


## Spawn interval at the current moment.
##
## Shortens as the run goes. Early gives learning time; late pushes hard.
## Straight drop from 6.0s to 2.2s over 90 seconds.
func _spawn_interval_now() -> float:
	# Tightens from 2.4s to 1.0s over 80 seconds, then keeps edging a little faster.
	var progress: float = clampf(_survived / 80.0, 0.0, 1.0)
	var base: float = lerpf(SPAWN_INTERVAL_START, SPAWN_INTERVAL_END, progress)
	var interval: float = maxf(base - _survived / 400.0, 0.34)
	if _encounter_kind() == RoomKind.Encounter.CROSSFIRE:
		interval *= 0.88                        # Field keeps fast lines rotating
	return maxf(interval, 0.34)


## How many to release together in one burst.
##
## **Shortening only the interval is just "one spirit a bit more often."** Survivor chase feel
## comes from a clump arriving at once. Start sending pairs, then three at 90s, four at 3 minutes.
## Each cycle adds one more.
func _spawn_burst() -> int:
	var burst: int = 2
	if _survived >= 90.0:
		burst += 1
	if _survived >= 180.0:
		burst += 1
	return burst + (1 if _cycle >= 3 else 0)


func _raid_interval_now() -> float:
	match _encounter_kind():
		RoomKind.Encounter.CROSSFIRE:
			return RAID_EVERY * 0.86
		RoomKind.Encounter.CARAVAN:
			return RAID_EVERY * 1.08            # One escort is high value, so rest a little
		_:
			return RAID_EVERY


func _encounter_kind() -> int:
	if _room == null or _room.kind == null:
		return RoomKind.Encounter.ENCIRCLE
	return int(_room.kind.encounter)


## Send one more out of the dark.
##
## Which kind appears is set by **how many beacons are lit.** Meaner as the run advances.
func _spawn_spirit() -> void:
	_prune_spirits()
	var room: int = spirit_cap() - _spirits.size() - _raid_queue.size()
	if room <= 0:
		return

	# A pack spawning on one point looks like one oversized spirit. Scatter them around the same
	# entry so they push in as a fan.
	var at: Vector2 = _farthest_spawn()
	var many: int = mini(_spawn_burst(), room)
	for i in many:
		var spread: Vector2 = Vector2.ZERO if i == 0 else \
			Vector2.RIGHT.rotated(randf() * TAU) * randf_range(26.0, 68.0)
		_summon(at + spread)


## Summon one spirit at that spot. Shared by normal spawns and raids.
func _summon(
		at: Vector2,
		forced_kind: String = "",
		toughness_scale: float = 1.0,
		force_elite: bool = false) -> Node2D:
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		return null
	var kind_path: String = forced_kind if not forced_kind.is_empty() else _pick_kind()
	var spirit: Node2D = SPIRIT_SCENE.instantiate()
	spirit.kind = load(kind_path) as SpiritKind
	spirit.toughness = toughness() * maxf(toughness_scale, 0.1)
	spirit.elite = force_elite or randf() < elite_chance()

	spirit.position = _room.nearest_clear(_room.clamp_to_play(at), 10.0)
	add_child(spirit)
	_register_spirit(spirit)
	spirit.materialize()
	return spirit


## How tough this cycle's spirits are.
##
## **The spine of endless play.** Cycles 1–3 grow 35% each to keep the old tempo; from cycle 4
## they grow 58% so late game is not a stroll. Guardians multiply this once more by
## `SpiritKind.guardian_toughness_scale()`.
func toughness() -> float:
	if _cycle <= 3:
		return pow(1.35, float(_cycle - 1))
	return pow(1.35, 2.0) * pow(1.58, float(_cycle - 3))


## Guardian HP. Starts from the same multiplier as trash; from cycle 4 the boss alone gets an
## extra bump. Accelerating trash the same way leaves flashy spirits that will not die and
## "I'm not getting stronger" returns.
func guardian_toughness() -> float:
	return toughness() * SpiritKind.guardian_toughness_scale(_cycle)


## Chance an elite is mixed in.
##
## None in the first cycle. A ×3-tough enemy with no relics yet kills before learning starts.
## From the second cycle, 8% steps up to a 30% cap —
## tightened from 6%/25% after feedback that cycles 3–4 felt like a stroll.
func elite_chance() -> float:
	if _cycle < 2:
		return 0.0
	var chance: float = 0.08 * float(_cycle - 1)
	if _encounter_kind() == RoomKind.Encounter.CARAVAN:
		chance += 0.06                           # Camp surfaces high-value targets more often
	return minf(chance, 0.3)


## How many spirits may be on screen at once. Grows each cycle.
##
## Fixed at 24 and even cycle 5 looks as sparse as the first.
## Five weapons with nothing to hit wastes those weapons.
func spirit_cap() -> int:
	# **Lowered after measuring on mobile.** Sixty spirits + twelve meteors was 1fps on the emulator.
	# Forty already packs an 808×360 screen; past that they only overlap and cannot be counted —
	# cost rises, what you see stays the same.
	return mini(MAX_SPIRITS + 5 * (_cycle - 1), 40)


## Place one of this terrain's beacons far out; fully rest the other terrain's two.
##
## Three in one room means even with three terrain resources you only see one screen until the first boss.
## Now one beacon is one zone, and the next beacon appears only after crossing the gate.
func _place_beacons() -> void:
	_place_current_beacon()
	_refresh_beacon_visibility()


func _place_current_beacon() -> void:
	var index: int = clampi(_zone_index, 0, _beacons.size() - 1)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([_run_seed, _cycle, _zone_index, str(_world_step()["room"])])
	var best: Vector2 = Room.MAP * 0.5
	var best_distance: float = -1.0
	# Pick the candidate farthest from the entrance. A beacon underfoot right after a terrain change
	# removes any reason to run the new place.
	for attempt in 24:
		var at: Vector2 = Vector2(
			rng.randf_range(Room.PLAY.position.x + 150, Room.PLAY.end.x - 150),
			rng.randf_range(Room.PLAY.position.y + 150, Room.PLAY.end.y - 150))
		if not _room.is_clear(at, 42.0, 10.0):
			continue
		var distance: float = at.distance_squared_to(_player.position)
		if distance > best_distance:
			best_distance = distance
			best = at
	_beacons[index].position = _room.nearest_clear(best, 42.0, 10.0)
	_beacons[index].reset_physics_interpolation()


func _refresh_beacon_visibility() -> void:
	var active: int = clampi(_zone_index, 0, _beacons.size() - 1)
	for i in _beacons.size():
		_beacons[i].set_active(i == active)


## Point at where to go now.
##
## **The target is "what to do now."** Pointing only at unlit beacons made the arrow vanish the
## moment all three lit — exactly when the guardian was off-screen — and raised
## "where do I go after lighting all three?"
##
## Order is the goal. Guardian if one exists; otherwise the nearest unlit beacon.
func _point_compass(delta: float) -> void:
	var safe_rect: Rect2 = Screen.viewport_safe_rect(get_viewport())

	if _overcharge_beacon != null and is_instance_valid(_overcharge_beacon):
		_compass.point_to(
			BeaconCompass.Mark.BEACON, _overcharge_beacon.position,
			_player.position, safe_rect, 0.0, delta)
		return

	if _guardian != null and is_instance_valid(_guardian):
		# A large boss judged off-screen by origin alone keeps the arrow up while standing in front of
		# you — pass the drawn radius too so "hide when the body is visible" holds.
		var guardian_extent: float = float(_guardian.visual_radius()) \
			if _guardian.has_method("visual_radius") else 24.0
		_compass.point_to(
			BeaconCompass.Mark.GUARDIAN, _guardian.position,
			_player.position, safe_rect, guardian_extent, delta)
		return
	if _escape_active:
		_compass.point_to(
			BeaconCompass.Mark.EXIT, _gate.position, _player.position,
			safe_rect, 0.0, delta)
		return

	var best: Node2D = null
	var best_distance: float = INF
	for beacon in _beacons:
		if not beacon.visible or beacon.lit:
			continue
		var distance: float = beacon.position.distance_to(_player.position)
		if distance < best_distance:
			best = beacon
			best_distance = distance

	if best == null:
		_compass.point_to(
			BeaconCompass.Mark.NONE, Vector2.ZERO, _player.position, safe_rect)
		return
	_compass.point_to(
		BeaconCompass.Mark.BEACON, best.position, _player.position,
		safe_rect, 0.0, delta)


## Pick one of the kinds currently unlocked.
##
## Recently unlocked ones appear more often. Lasting 20 minutes and still seeing only wandering
## spirits makes growth feel pointless.
func _pick_kind() -> String:
	var open: Array = []
	for entry in SPIRIT_UNLOCKS:
		if _survived >= float(entry[0]):
			open.append(str(entry[1]))
	if open.is_empty():
		return str(SPIRIT_UNLOCKS[0][1])

	# Normal composition follows terrain too. If only raids differ, most of the 32s between them is
	# the same map again.
	var preferred: Array = []
	match _encounter_kind():
		RoomKind.Encounter.CROSSFIRE:
			for path in open:
				if path in [
					"res://resources/drifter.tres",
					"res://resources/stalker.tres",
					"res://resources/swarm.tres",
					"res://resources/caster.tres",
				]:
					preferred.append(path)
		RoomKind.Encounter.CARAVAN:
			for path in open:
				if path in [
					"res://resources/weaver.tres",
					"res://resources/ember.tres",
					"res://resources/caster.tres",
				]:
					preferred.append(path)
	if not preferred.is_empty() and randf() < 0.64:
		return str(preferred[randi_range(0, preferred.size() - 1)])

	# Weight toward the back (later unlocks). The last three take half.
	if open.size() > 3 and randf() < 0.5:
		return str(open[randi_range(open.size() - 3, open.size() - 1)])
	return str(open[randi_range(0, open.size() - 1)])


## Farthest point from the player. Popping up in their face feels unfair.
func _farthest_spawn() -> Vector2:
	var best: Vector2 = _room.nearest_clear(SPAWN_POINTS[0], 10.0)
	for point in SPAWN_POINTS:
		var candidate: Vector2 = _room.nearest_clear(point, 10.0)
		if candidate.distance_to(_player.position) > best.distance_to(_player.position):
			best = candidate
	return best


## Appears the moment the last beacon lights.
func _summon_guardian() -> void:
	if _guardian != null \
			or (OS.is_debug_build() and _debug_hero_direction_capture_active):
		return

	# Clear prior raid queues and already-flying caster shots so the stage is a real one-on-one.
	_raid_queue.clear()
	_clear_hostile_projectiles()
	_clear_hostile_projectiles.call_deferred()

	# Trash steps aside.
	#
	# Leave them and one guardian + four spirits rush at once. Built that way for real and died the
	# instant the last beacon lit. **Not hard — impossible.**
	#
	# Clearing the stage makes the finale a one-on-one with the guardian.
	_prune_spirits()
	for s in _spirits:
		s.retreat()
	_spirits.clear()
	# Stay quiet only while facing the guardian. **Do not freeze forever** —
	# after the kill you are alone on an empty map. Built it that way and learned.
	# Cycle 1 guarantees a 12s duel; higher cycles let trash join earlier.
	# From cycle 5 the floor drops to 3s so late bosses are never alone.
	var quiet: float = 12.0 - 2.0 * float(_cycle - 1)
	_spawn_timer = maxf(quiet, 3.0 if _cycle >= 5 else 5.0)

	_guardian = SPIRIT_SCENE.instantiate()
	var guardian_path: String = _guardian_resource_path()
	var boss: SpiritKind = (load(guardian_path) as SpiritKind).duplicate()
	_analytics_guardian_started_ms = _analytics_elapsed_ms()
	_analytics_track("guardian_started", {
		"guardian": _analytics_resource_id(guardian_path),
		"terrain": _analytics_terrain_id(),
		"cycle": _cycle,
		"elapsed_ms": _analytics_guardian_started_ms,
	})
	_guardian.set_meta(GUARDIAN_KIND_SOURCE_PATH_META, guardian_path)
	_guardian.set("guardian_cycle", _cycle)
	boss.score_value = boss.score_value * _cycle
	# Tighten the burst-damage budget ratio each cycle too. Scaling only HP lets the cap grow with
	# HP and keeps minimum kill time constant. The floor each cycle is set by
	# `guardian_budget_floor()`.
	var pressure: float = SpiritKind.cycle_pressure(_cycle)
	var budget_floor: float = SpiritKind.guardian_budget_floor(_cycle)
	boss.guardian_burst_fraction = maxf(
		boss.guardian_burst_fraction / pressure, budget_floor)
	boss.guardian_sustain_fraction = maxf(
		boss.guardian_sustain_fraction / pressure, budget_floor)
	_guardian.kind = boss
	# Stack guardian-only acceleration on the trash multiplier. Late bosses must not become a weaker
	# climax than elite trash.
	_guardian.toughness = guardian_toughness()
	# Farthest from the player. Spawning beside the last beacon means a hit the moment it lights.
	_guardian.position = _farthest_spawn()
	add_child.call_deferred(_guardian)
	_register_spirit(_guardian)
	# Listen to the guardian alone. Mixing with trash leads to messy name compares.
	_guardian.perished.connect(func(_k: SpiritKind, _at: Vector2, _elite: bool) -> void:
		# Projectiles already in flight behind the result screen can finish the guardian.
		# Do not reopen cycle, heal, or loot panels on an ended run.
		if _over:
			return
		_guardian = null
		_finish_cycle())
	# **`materialize()` must be deferred too.** `add_child` was deferred just above, so the guardian
	# is still outside the tree and `@onready var _hitbox` has not run.
	# Calling now dies with `Invalid assignment ... on a base object of type 'Nil'`.
	# Deferred calls run in registration order, so add_child is first. Reserve both at the same moment
	# so release intro timing stays the same. The second helper discards an already-attached guardian
	# only if debug direction capture turned on in between.
	_materialize_or_discard_guardian.call_deferred(_guardian)
	# Give the name and how to dodge in one line first. It should not look like a boss that only differs
	# in HP and color — learn this terrain's rule before taking the first pattern.
	_hud.announce(tr("GUARDIAN_INTRO") % [
		tr(boss.display_name), tr(boss.guardian_rule)], boss.boss_accent)
	_say("guardian")

	# Music changes. The ear knows the finale first.
	_bgm.stop()
	_bgm.stream = GUARDIAN_THEME
	# A guardian fight pushes one step harder than explore.
	_bgm.pitch_scale = minf(_arena_bgm_pitch() + 0.05, BGM_PITCH_MAX)
	_bgm.play()


func _materialize_or_discard_guardian(guardian: Node2D) -> void:
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		if is_instance_valid(guardian):
			guardian.queue_free()
		if _guardian == guardian:
			_guardian = null
		return
	if not is_instance_valid(guardian):
		return
	guardian.materialize()


## Dash button pressed.
##
## Direction is **wherever you are walking now.** Standing still dashes the facing way.
## Used to be the right-stick push; a button has no direction, so take it from movement.
## In survivors dash is not "where should I go" but **"I need out now,"** so
## leaving the way you were already going is the right call.
func _on_dash_pressed() -> void:
	if _over or _transitioning:
		return
	var direction: Vector2 = _stick.get_value()
	if direction.length() < 0.01:
		direction = _player.facing_vector()
	var from: Vector2 = _player.global_position
	if not _player.dash(direction):
		return
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		return
	_analytics_tutorial_step("dash")
	_advance_beacon_hint()
	if Relic.family_resonant(_taken, Relic.Family.STARFALL):
		_starfall_primed = true
	if Relic.family_resonant(_taken, Relic.Family.FULL_MOON):
		_full_moon_primed = true
	if Relic.family_resonant(_taken, Relic.Family.MOON_DANCE) \
			or Relic.family_evolved(_taken, Relic.Family.MOON_DANCE):
		_moon_dance_sweep(from)


## Moon Dance — scan the dash segment once. At most 40 distance checks, no standing Area2D.
func _moon_dance_sweep(from: Vector2) -> void:
	await get_tree().create_timer(0.2, false).timeout
	if _over or _transitioning or not is_inside_tree():
		return
	var to: Vector2 = _player.global_position
	var total: int = Relic.family_total(_taken, Relic.Family.MOON_DANCE)
	var evolved: bool = Relic.family_evolved(_taken, Relic.Family.MOON_DANCE)
	var damage: int = _scaled(AUX_BASE_HIT,
		(0.8 if evolved else 0.55) * pow(1.15, float(maxi(total - 2, 0)))
		* _damage_mult * _frailty() * _moonfire_damage())
	for spirit in _spirits:
		if not is_instance_valid(spirit) or not spirit.is_attackable():
			continue
		if _distance_to_segment(spirit.global_position, from, to) <= 22.0:
			spirit.take_damage(damage, from)
	_player.play_moon_dance()


func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var line: Vector2 = to - from
	var length_sq: float = line.length_squared()
	if length_sq <= 0.001:
		return point.distance_to(from)
	var along: float = clampf((point - from).dot(line) / length_sq, 0.0, 1.0)
	return point.distance_to(from + line * along)


func _begin_tutorial() -> void:
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		_tutorial_step = 4
		_hud.debug_unlock_capture_banner()
		_hud.set_banner_suppressed(true)
		return
	# High-rank test states are not onboarding targets.
	if _cycle != 1 or _survived > 1.0 or _over:
		_tutorial_step = 4
		return
	_tutorial_step = 1
	_onboarding = true
	_open_run_story()
	_hud.announce(tr("TUTORIAL_MOVE"), Color(0.74, 0.9, 1.0, 1), ONBOARD_HOLD)


## Open the first line of a run.
##
## `STORY_CYCLE_1` — "this is today's ground" — never appeared before.
## Cycle stories queue **after** `_cycle += 1`, so they always started at 2. Cycles 2–8 attach to
## each cycle entry, so 1's place is this moment the run opens.
##
## This dialogue pauses the game (`get_tree().paused`). That is why it must open only on a run a
## human is actually playing.
##
## - Regression tests spawn the arena and simulate combat. Pausing here derails that simulation
##   wholesale — thirty missile-loop checks broke at once. They skip the title, so `RunEntry`
##   filters them.
## - Store capture enters the real game with a boot request file left behind. It also passes the
##   title, so `RunEntry` alone cannot filter. Both freeze-enable and this call are `call_deferred`,
##   so order is not guaranteed — read the request file directly.
##   Even one frame of a half-screen dialogue forces all four locale sets to be recaptured.
##
## Other gates already live in `_show_cycle_story()` — evolution capture, progress freeze,
## missing translation keys.
func _open_run_story() -> void:
	# Only runs that entered from the title pass. Filtering by tree shape failed twice —
	# the hero-direction capture test does `get_tree().root.add_child()` then also sets
	# `current_scene` to the arena, so both checks passed.
	# See `RunEntry`.
	if not RunEntry.consume_from_title():
		return
	if not STORE_CAPTURE_BOOT.read_request().is_empty():
		return
	_show_cycle_story()
	_flush_cycle_story()


## Teach a first-seen concept once, on the spot.
##
## Do not show during capture — the banner would land in the store shot.
func _onboard(key: String) -> void:
	if not _onboarding or _over or _capture_progress_frozen:
		return
	if _onboarded.get(key, false):
		return
	_onboarded[key] = true
	_hud.announce(tr(key), Color(0.82, 0.92, 1.0, 1), ONBOARD_HOLD)


## Open the beacon tip once. Called from both dash and beacon approach.
func _advance_beacon_hint() -> void:
	if _tutorial_step != 2:
		return
	_tutorial_step = 3
	if not _onboarding or _over or _capture_progress_frozen:
		return
	_hud.announce(tr("TUTORIAL_BEACON"), Color(1.0, 0.82, 0.48, 1), ONBOARD_HOLD)


func _tick_tutorial() -> void:
	# That attacks fire on their own is taught by **distance moved**, not by spawn.
	# On spawn the banner pops at a timer-chosen random moment and collides with checks that watch
	# whether leftover tips have cleared.
	if _onboarding and _tutorial_step >= 2 \
			and _player.position.distance_to(_tutorial_origin) > 96.0:
		_onboard("TUTORIAL_AUTO_ATTACK")
	# Beacon rules are this whole game. Teaching them only on dash-button press means anyone who never
	# presses the button never sees them. Also open when a beacon is close enough to enter the screen —
	# whichever comes first.
	if _tutorial_step == 2:
		for beacon in _beacons:
			if not is_instance_valid(beacon) or not beacon.visible or beacon.lit:
				continue
			if _player.position.distance_to(beacon.position) < BEACON_HINT_RADIUS:
				_advance_beacon_hint()
				break
	if _tutorial_step != 1:
		return
	if _player.position.distance_to(_tutorial_origin) < 28.0:
		return
	_tutorial_step = 2
	_analytics_tutorial_step("move")
	_hud.announce(tr("TUTORIAL_DASH"), Color(0.76, 0.88, 1.0, 1), ONBOARD_HOLD)


## Contact with a spirit. Screen flashes red and one heart drops.
##
## Lesson 8 only flashed. Health and game over landed in Lesson 9; heart display in Lesson 10.
func _on_player_hit(from_position: Vector2) -> void:
	if _over or _invulnerable > 0.0:
		return
	# Moon Dance only slips contact for the short dash window. It does not clear shots or grant long i-frames.
	if Relic.family_evolved(_taken, Relic.Family.MOON_DANCE) and _player.is_dashing():
		return
	_invulnerable = _invulnerable_time
	_player.knock_back(from_position)
	if _shielded:
		return
	_set_health(_health - 1)
	_onboard("TUTORIAL_HEART")
	_eject_missile_power()
	if _health <= 0:
		_finish(false)

	if _flash != null and _flash.is_valid():
		_flash.kill()
	_hit_flash.modulate.a = 1.0
	_flash = create_tween()
	_flash.tween_property(_hit_flash, "modulate:a", 0.0, HIT_FLASH_SECONDS)


## Pass the fill a beacon reported to the ring under the player's feet.
##
## Standing between two beacons fills both. Show the one **filled the most.**
func _on_beacon_charge_changed(_beacon: Node2D, _ratio: float) -> void:
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		_player.set_charge(0.0)
		return
	var top: float = 0.0
	for beacon in _beacons:
		top = maxf(top, beacon.get_charge())
	_player.set_charge(top)


## Charge complete still does not raise the progress count yet. Lock the move finger and only after
## the modal picks stable lighting or overcharge does a real `ignite()` fire once.
func _on_beacon_charge_completed(beacon: Node2D) -> void:
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		beacon.ignite()
		return
	if _over or _transitioning or _pending_beacon_choice != null \
			or _overcharge_beacon != null or not is_instance_valid(beacon):
		if is_instance_valid(beacon):
			beacon.freeze()
		return
	var active_index: int = clampi(_zone_index, 0, _beacons.size() - 1)
	if not beacon.visible or beacon != _beacons[active_index]:
		beacon.freeze()
		return

	_pending_beacon_choice = beacon
	_player.set_charge(0.0)
	_player.set_move_input(Vector2.ZERO)
	_stick.set_active(false)
	_pause.set_available(false)
	_run_choice.open_beacon(
		beacon, _overcharge_successes, _overcharge_core_available())


func _on_run_choice_made(
		mode: RunChoicePanel.Mode,
		choice: RunChoicePanel.Choice,
		context: Variant) -> void:
	if mode == RunChoicePanel.Mode.BEACON:
		var beacon: Node2D = context as Node2D
		if beacon == null or not is_instance_valid(beacon) \
				or beacon != _pending_beacon_choice or _over:
			_pending_beacon_choice = null
			_restore_run_controls()
			return
		_pending_beacon_choice = null
		var beacon_mode: String = "overcharge" \
			if choice == RunChoicePanel.Choice.RIGHT else "normal"
		_analytics_track("beacon_choice", {
			"beacon": clampi(_beacons.find(beacon) + 1, 1, 9),
			"cycle": _cycle,
			"terrain": _analytics_terrain_id(),
			"mode": beacon_mode,
			"elapsed_ms": _analytics_elapsed_ms(),
		})
		_restore_run_controls()
		if choice == RunChoicePanel.Choice.RIGHT:
			_begin_overcharge(beacon)
		else:
			beacon.set_meta(&"_analytics_beacon_mode", "normal")
			beacon.ignite()
		return

	if mode != RunChoicePanel.Mode.CYCLE or not _cycle_decision_queued \
			or int(context) != _completed_cycle or _over:
		return
	_cycle_decision_queued = false
	_analytics_track("cycle_decision", {
		"choice": "cashout" if choice == RunChoicePanel.Choice.LEFT else "continue",
		"cycle": _completed_cycle,
		"overcharges": _completed_cycle_overcharges,
		"elapsed_ms": _analytics_elapsed_ms(),
	})
	if choice == RunChoicePanel.Choice.LEFT:
		_finish(true)
		return
	_restore_run_controls()
	_announce_world_rule()
	_flush_cycle_story.call_deferred()


func _restore_run_controls() -> void:
	if _over or _transitioning:
		return
	_stick.set_active(true)
	_pause.set_available(true)


## A small boss fight holding the beacon for 6.5s. Briefly pause the normal spawn clock and send
## only two terrain-specific formations so the choice's risk reads.
func _begin_overcharge(beacon: Node2D) -> void:
	if _over or not is_instance_valid(beacon) or not beacon.begin_overcharge():
		if is_instance_valid(beacon) and not beacon.lit:
			beacon.ignite()
		return
	_overcharge_beacon = beacon
	beacon.set_meta(&"_analytics_beacon_mode", "overcharge")
	_overcharge_progress = 0.0
	_analytics_overcharge_started_ms = _analytics_elapsed_ms()
	_overcharge_abandon_left = OVERCHARGE_ABANDON_GRACE
	_overcharge_second_wave_sent = false
	_player.set_charge_overcharge(true)
	_player.set_charge(0.01)
	_raid_queue.clear()
	_queue_overcharge_wave(false)
	_hud.announce(tr("OVERCHARGE_STARTED"), Color(0.78, 0.58, 1.0, 1), 2.4)
	_shake(2.4)


func _tick_overcharge(delta: float) -> void:
	if _overcharge_beacon == null:
		return
	if not is_instance_valid(_overcharge_beacon) \
			or not _overcharge_beacon.is_overcharging():
		_finish_overcharge(false)
		return
	var distance: float = _player.global_position.distance_to(
		_overcharge_beacon.global_position)
	if distance <= OVERCHARGE_RADIUS:
		_overcharge_progress += delta / OVERCHARGE_SECONDS
		_overcharge_abandon_left = OVERCHARGE_ABANDON_GRACE
	else:
		_overcharge_progress -= delta / OVERCHARGE_SECONDS * OVERCHARGE_DECAY_SCALE
		if distance > OVERCHARGE_ABANDON_RADIUS:
			_overcharge_abandon_left -= delta
		else:
			_overcharge_abandon_left = minf(
				_overcharge_abandon_left + delta, OVERCHARGE_ABANDON_GRACE)
	_overcharge_progress = clampf(_overcharge_progress, 0.0, 1.0)
	_player.set_charge(_overcharge_progress)

	if not _overcharge_second_wave_sent \
			and _overcharge_progress >= OVERCHARGE_WAVE_AT:
		_overcharge_second_wave_sent = true
		_queue_overcharge_wave(true)
	if _overcharge_abandon_left <= 0.0:
		_finish_overcharge(false, true)
	elif _overcharge_progress >= 1.0:
		_finish_overcharge(true)


func _queue_overcharge_wave(second_wave: bool) -> void:
	_prune_spirits()
	var available: int = spirit_cap() - _spirits.size() - _raid_queue.size()
	var many: int = mini(
		OVERCHARGE_BASE_WAVE + (_cycle - 1) + (1 if second_wave else 0),
		maxi(available, 0))
	if many <= 0:
		return
	match _encounter_kind():
		RoomKind.Encounter.CROSSFIRE:
			_queue_crossfire(many)
		RoomKind.Encounter.CARAVAN:
			_queue_caravan(many)
		_:
			_queue_ambush(many)
	_raid_spawn_left = 0.0


func _finish_overcharge(success: bool, abandoned: bool = false) -> void:
	var beacon: Node2D = _overcharge_beacon
	var outcome: String = "success" if success \
		else ("abandoned" if abandoned else "failed")
	_overcharge_beacon = null
	_overcharge_progress = 0.0
	_overcharge_abandon_left = 0.0
	_overcharge_second_wave_sent = false
	_player.set_charge(0.0)
	_player.set_charge_overcharge(false)
	if not is_instance_valid(beacon):
		_analytics_track_overcharge_resolution(outcome, "none")
		return
	var core_granted: bool = false
	var reward: String = "none"
	if success:
		_overcharge_successes += 1
		_gain_moonfire(BEACON_CHARGE)
		core_granted = _grant_overcharge_core(beacon.position)
		reward = "core" if core_granted else "growth"
		_gain_progress(false)
		_shake(4.0)
	_analytics_track_overcharge_resolution(outcome, reward)
	beacon.resolve_overcharge()
	# The third beacon's following guardian guide matters more. Leave overcharge outcomes as the last
	# banner only on the first two beacons.
	if _lit_count < _beacons.size():
		if success:
			var success_copy: String = tr(
				"OVERCHARGE_SUCCEEDED" if core_granted \
				else "OVERCHARGE_SUCCEEDED_MAX")
			if success_copy.contains("%d"):
				success_copy %= [_overcharge_successes, _beacons.size()]
			_hud.announce(
				success_copy,
				Color(1.0, 0.78, 0.36, 1), 2.6)
		else:
			_hud.announce(
				tr("OVERCHARGE_FAILED"), Color(1.0, 0.5, 0.48, 1), 2.2)


func _overcharge_core_available() -> bool:
	return _overcharge_reward_power() >= 0


## Re-count cores already complete and waiting in current progress by per-rank threshold.
##
## Regular cores keep the difficulty of the next power to collect; ejected cores keep the difficulty
## of the original recoverable power. If reserved cores already fill max power, modal and grant both
## return to growth; otherwise return the exact threshold rank of the next one core.
func _overcharge_reward_power() -> int:
	var committed: int = _missile_power + _regular_cores_outstanding
	if committed >= MissileProgression.MAX_POWER:
		return -1
	var base_power: int = _missile_threshold_power() + _regular_cores_outstanding
	var remaining: int = maxi(_missile_progress, 0)
	var queued: int = 0
	while committed + queued < MissileProgression.MAX_POWER:
		var queued_power: int = clampi(
			base_power + queued, 0, MissileProgression.MAX_POWER - 1)
		var needed: int = MissileProgression.threshold(queued_power)
		if remaining < needed:
			break
		remaining -= needed
		queued += 1
	if committed + queued >= MissileProgression.MAX_POWER:
		return -1
	return clampi(
		base_power + queued, 0, MissileProgression.MAX_POWER - 1)


func _grant_overcharge_core(at: Vector2) -> bool:
	# A floor ejected core is lost power and not yet recovered. Counting this state as max power
	# silently drops overcharge rewards. Treat only live power and already-earned regular cores as
	# confirmed power; when an ejected core frees its slot, the backlog below
	# comes out as a regular core.
	var reward_power: int = _overcharge_reward_power()
	if reward_power < 0:
		return false
	_missile_progress += MissileProgression.threshold(reward_power)
	_try_drop_missile_core(at)
	_refresh_missile_hud()
	return true


## Beacon heal checks whether this cycle already received it — not which beacon it was.
## Separated from signal handling so the once-per-cycle combat rule can be tested without side effects.
func _try_apply_beacon_heal() -> bool:
	if _beacon_healed_cycle == _cycle:
		return false
	# As the copy says, the cycle's first beacon spends the chance. Record it even if HP was full at
	# the first beacon or no relic is held yet. Do not create a hidden rule that defers the heal to a
	# second beacon after picking a relic or taking intentional damage.
	_beacon_healed_cycle = _cycle
	if _beacon_heal <= 0:
		return false
	if _health >= _max_health:
		return false
	_set_health(_health + _beacon_heal)
	return true


func _on_beacon_lit_changed(beacon: Node2D, is_lit: bool) -> void:
	if OS.is_debug_build() and _debug_hero_direction_capture_active:
		if is_lit:
			beacon.reset()
		beacon.freeze()
		return
	if not is_lit and beacon.has_meta(&"_ignore_hidden_reset_signal"):
		# Paired signal from the defensive reset below. It pairs with a true that was never counted, so
		# do not subtract it from the progress count either.
		beacon.remove_meta(&"_ignore_hidden_reset_signal")
		return
	if is_lit and not beacon.visible:
		# Do not raise progress when a debug/deferred signal lights a hidden next-terrain beacon.
		beacon.set_meta(&"_ignore_hidden_reset_signal", true)
		beacon.reset.call_deferred()
		beacon.set_active.call_deferred(false)
		return
	_lit_count += 1 if is_lit else -1
	_lit_count = clampi(_lit_count, 0, _beacons.size())

	# Raise the night tint by how many are lit. Which index lit does not matter.
	_hud.set_beacons(_lit_count, _beacons.size())

	if is_lit:
		var beacon_mode: String = str(beacon.get_meta(
			&"_analytics_beacon_mode", "normal"))
		beacon.remove_meta(&"_analytics_beacon_mode")
		_analytics_total_beacons += 1
		_analytics_track("beacon_lit", {
			"beacon": clampi(_beacons.find(beacon) + 1, 1, 9),
			"cycle": _cycle,
			"terrain": _analytics_terrain_id(),
			"mode": beacon_mode,
			"elapsed_ms": _analytics_elapsed_ms(),
		})
		_analytics_tutorial_step("beacon")
		if _tutorial_step < 4:
			_tutorial_step = 4
		_try_apply_beacon_heal()
		# The moment a zone paints one step. First and last beacon have different lines.
		if _lit_count >= _beacons.size():
			_say("beacon_last")
		elif _lit_count == 1:
			_say("beacon_first")
		else:
			_say("beacon_mid")

		if _lit_count >= _beacons.size():
			# The reward for hunting turns into combat power immediately. It stays on until the guardian
			# falls, so time spent finding a far-spawned boss is not a loss.
			_escape_active = false
			_gate.close()
			_activate_moonfire(true, false)
			_summon_guardian()
		else:
			var extended_moonfire: bool = _moonfire_on and not _moonfire_locked
			if extended_moonfire:
				_moonfire_left += BEACON_MOONFIRE_EXTENSION
				_hud.set_moonfire(_moonfire_left / MOONFIRE_SECONDS, true, false)
			else:
				_gain_moonfire(BEACON_CHARGE)
			_open_escape(extended_moonfire)

	# First beacon is blue dawn, second sunrise, third day. Not just exposure — color temperature
	# must shift too or night does not look like it actually passed.
	_apply_time_tone()

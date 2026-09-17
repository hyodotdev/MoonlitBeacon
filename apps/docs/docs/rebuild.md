---
title: 2.0 rebuild — fixing a game that was not fun
---

# 2.0 rebuild — fixing a game that was not fun

We shipped 1.0.0 and played it ourselves. Then we wrote this.

> "Still not fun. One-and-done, the map is too small, and there are
> screen transitions all over the place. There should be a heal item
> mid-run you can pick up, and it would be good to actually defeat the
> monsters."

This document is what we changed after that, and why, and how.
**It includes the grounds for the decisions and what we threw away.**
Results alone will not tell you why a number is that number, and a few
months from now even we get lost.

## How to read this

Twenty-three sections. You do not have to read them in order. They group
into four clumps.

| Clump | Sections | What |
| --- | --- | --- |
| **Change the genre** | 1–9 | from 90-second dodge to endless survivor. Map, camera, enemies, controls, wayfinding |
| **Make a run fun** | 10–17 | weapons and relics, visible firepower, something to lose |
| **Build outside the run** | 18–20 | growth that survives death, characters, ladder |
| **Make it fixable** | 17 · 21–23 | verification tools, performance, paths we never ran |

**If you only care how we fixed things, start at 17, 21, and 22.** The
most valuable things in this rebuild were not new features. They were
**a button that jumps to the late game in one second** and **a gauge
stuck on the screen.** Without those two we would never have found
"growth is locked for 3 minutes" or "we call `move_and_slide()` while
nothing collides."

## What changed

| | 1.0.0 | now |
| --- | --- | --- |
| Run length | 90-second countdown | endless |
| Map | one screen (808×360) | 1900×1180, camera follows |
| Enemies | one kind, 3 at once | seven kinds + elites + guardians, 40 at once |
| Weapons | none (dodge only) | slash · arrows · homing missiles · ring · ripple |
| In-run growth | none | 16 relics, stacking |
| Out-of-run growth | none | shards · 6 boons · 6 characters (1 free + 5 paid) |
| Records | one best score | latest-version-first top 10, name · character · app version |

---

## 1. Find why it is not fun in numbers

Start from impressions and you cannot find what to fix. We opened the
code and looked at values.

| Where | Value | What it means |
| --- | --- | --- |
| `player.gd` `speed` | **96.0** | |
| `ember.tres` `speed` | **84.0** | **the fastest enemy is slower than the player** |
| `arena.gd` `SPAWN_INTERVAL` | 13.0s | max 6 in a 90-second run |
| `arena.gd` `MAX_SPIRITS` | 3 | |
| code that plants a seed | **none** | every run is literally the same |

Three things show up at once.

1. **Turn your back and walk straight for 90 seconds and you never get
   hit.** The dash from Lesson 12 was never needed in a run.
2. **Empty-screen time is longer.** One every 13 seconds, and no way to
   kill them.
3. **Nothing differs per run.** Nowhere called `randi()`.

:::tip Turning an impression into a number is the first step
"Not fun" cannot be fixed. "The enemy is 12px/s slower than the player"
can.
:::

---

## 2. Attack — without adding a button

To defeat monsters you need an attack. **There is nowhere to put one.**

In `arena.tscn`, `LeftStick` covers x 0–404, `RightStick` covers x 404–808,
and `virtual_stick.gd` sets `mouse_filter = STOP`. **Zero pixels of
808×360 are uncovered by a stick.** Put a button there and the stick
will not raise on that spot, and the floating-stick premise ("press
anywhere and a stick appears") breaks.

So we picked **auto-attack**. If a spirit is nearby, it goes out on its own.

```gdscript
# arena.gd — every frame
if _player.can_attack():
    var target: Node2D = _nearest_spirit()
    if target != null:
        _swing_at(target)
```

### Finding enemies is not the player's job

The arena already holds the enemy list as `_spirits`. We keep the rule
from Lesson 6: "the player does not even read the stick." If the player
starts walking the scene tree, Lesson 8's enemy cannot share the same
body.

### Visible range and hit range must match

The fan angle lives in **two places**.

- `ATTACK_ARC = 110.0` in `player.gd`
- `ARC_DEGREES = 110.0` in `tools/build_slash.py`

**If the two values differ you get "I clearly hit it and it did not
die."** So we do not draw the slash by hand. Python bakes it. Change the
angle and the picture follows.

### The hit feeling needs all four

White flash (0.06s) · knockback · hitch · dissolve (0.25s). We tried
flash only first, and the spirit kept walking in, so **you could not
tell whether it was hit.**

:::danger Do not put the flash on the root
Multiplying white on the whole `Spirit` node brightened the child
`Shadow` too, and **the ground shadow popped as a pink bar.** We saw it
in an emulator capture.
Put it on `Sprite` only — it is a sibling of `Shadow`, so they do not
affect each other.
:::

---

## 3. Balance — close the "running away is the answer" door

| | before | after |
| --- | --- | --- |
| Ember spirit | 84 | **104** (faster than the player's 96) |
| Night bat | 70 | 88 |
| Spawn interval | 13s fixed | tightens 6.0 → 1.1s |
| Simultaneous max | 3 | 24 |
| Health | 3 | 5 |

Making one enemy faster than the player is the core. That one kind
means **running away is no longer the answer.**

### Why we raised enemy health

At first it was 2–3, but auto-attack range 34 is **much farther** than
contact radius 11, so spirits died before they reached you. Standing
still became a no-hit run. We raised it to 4–5 so they survive the
approach.

---

## 4. Healing — the point is that it does not vanish

Moon Dew drops at 12% where a spirit scattered. 28% if you are on one
heart, and at full health it does not drop — it becomes score instead.

**No lifetime. It does not vanish.** That was the whole design at the
time.

Usually you remove it after 8–12 seconds. Then "it is dangerous, pick it
up later" cannot exist, so you either dive the instant it drops or give
up, and neither is fun.
Leave it and **the ground you already walked becomes emergency food.**

### The call we reversed in 1.0.1

Long sessions showed this call was wrong. After kill speed rose, dew
kept piling across the map, and combined with around ten hearts, loss
almost disappeared. 1.0.1 caps dew at 3 on the field and removes it
after 18 seconds. Normal drops share a 12-second cooldown across the
whole field, and only killing an elite while on one heart with no dew on
the field guarantees one rescue dew. Healing is not an infinite pantry.
It is a choice to take a risk now.

---

## 5. A large map and a camera

We threw away one room being one screen. Now it is one **1900 × 1180**
map and `Player/Cam` follows.

```
[node name="Cam" type="Camera2D" parent="."]
position_smoothing_enabled = false
limit_right = 1900
limit_bottom = 1180
```

Player movement fills between 30Hz physics ticks with the engine's 2D
physics interpolation. The camera, a child of Player, follows that same
interpolated transform. We do not stack a separate position smoother.
Two corrections at once can make character and background lag on
different beats, and small dot outlines can look doubled.

The point is that it does not fit on 808×360. **Not knowing what comes
out of the dark is what makes tension.**

### Do not put the background in a scene file

The title forest (`night_forest.tscn`) has 1,294 trees baked into the
scene. 295KB. Do a large map that way and tens of thousands of lines
enter the repo, and moving one tree is work.

We split it into `RoomKind` (one `.tres` is one map) + `Room` (layout
from a seed). Same pattern as `SpiritKind` — **growing maps does not
grow code or scenes.**

:::warning Edge-only trees become a prairie
At first we planted trees only on the map rim. The rim is outside
1900×1180 and the screen is 808×360, so **around the player you only saw
grass.** Scatter trees inside too, **clumped like brush.**
Even scatter looks artificial and never makes terrain to weave through.
Clumps make paths between them.
:::

---

## 6. Endless growth

This is the largest change.

| | 1.0 | 2.0 |
| --- | --- | --- |
| Time | 90-second count**down** | survived time **goes up** |
| End | escape or time out | **until you die** |
| Growth | none | a relic every level-up |

**The 90-second countdown was the biggest shackle.** Put an ending clock
on a game that grows forever and the run ends before growth starts.

### The story of hanging relics on beacons, then moving them

At first **lighting a beacon** gave a relic. Three beacons, three times
a run. We built it and **three gifts and done was not endless growth.**

So we **hung it on kills.** Scatter a spirit, level progress fills, and
each level you pick a relic. No end.

```gdscript
const LEVEL_FIRST: int = 4      # the first level has to come fast
const LEVEL_GROWTH: float = 1.28  # it stretches later
```

There is a reason the first level is 4 kills. **You have to hold a relic
within 30 seconds** or you stop. A distant first reward ends as "it is
just the same."

### Relics

One `.tres` is one relic. The `SpiritKind` · `RoomKind` pattern paid off
a third time.

| Relic | Effect |
| --- | --- |
| Long Blade | range **+40%** |
| Swift Hand | swing interval **−30%** |
| Sharp Moonlight | damage **+1** |
| Wide Slash | angle +50% |
| Light Step | speed +18 |
| Tenacious Life | heart +1 · instant heal |
| Moonlit Step | dash −35% |
| Shadow Veil | i-frames +0.6s |
| Dew Hunter | dew ×2 |
| Beacon's Warmth | heal one heart per beacon |

**Effects are large.** "A little stronger" is not a reason to pick.
The fingertips have to change the moment you pick, or you will not hunt
the next level.

Relics have to change values mid-run, so constants like `ATTACK_RANGE`,
`ATTACK_COOLDOWN`, and `MAX_HEALTH` became variables. Defaults stay as
`DEFAULT_` — you need a baseline to multiply.

---

## 7. Diversify enemies — by behavior, not speed

There were three spirits, but **all three were "chase."** Only speed and
turn rate differed, so more kinds still did the same thing on screen,
and the answer stayed the same.

We put **behavior** on `SpiritKind`.

```gdscript
enum Behavior { CHASE, CHARGE, ORBIT, SHOOT }
```

| Behavior | What it does | How you answer |
| --- | --- | --- |
| `CHASE` | comes straight | slash or dodge |
| `CHARGE` | stops, aims, then a straight rush | **step aside during the telegraph** |
| `ORBIT` | circles in | hard to aim. Wait and hit |
| `SHOOT` | keeps distance and fires moonlight | **you have to dash in to catch it** |

Seven kinds **unlock by time survived.** All of them from the start and
you have seen everything in 30 seconds and get bored. New faces as you
last is a reason to keep going.

```gdscript
const SPIRIT_UNLOCKS: Array = [
    [0.0,   "wisp"],     [20.0,  "drifter"], [45.0,  "weaver"],
    [75.0,  "ember"],    [105.0, "stalker"], [140.0, "caster"],
    [180.0, "swarm"],
]
```

We weight the late unlocks. **Last 20 minutes and still only drifting
spirits, and growth feels wasted.**

### A charge must have a telegraph

`CHARGE` **shakes red** in place for 0.85 seconds while it aims. Only
then does it rush, and during the rush the direction is locked so it
does not follow. So **step aside and it misses.**

No telegraph and you just get hit unfairly. Something you cannot dodge
is a penalty, not a threat.

### Orbs do not home

Moonlight orbs from `SHOOT` only go straight. Same reason — homing
leaves no way to dodge.

Orbs **parent to the arena.** As children of the spirit that fired them,
they vanish the instant that spirit dies. And when an orb hits, it
re-emits the spirit's `touched_player` signal.
From the arena's view **body or orb is the same event**, so there is no
reason to split handling.

---

## 8. Controls — when the genre changes, controls have to follow

Near the end of the rebuild we played it and this came out.

> "The D-pad slides if I do it from the center and moves if I do it from
> the left. Is that right?"

The behavior itself was as designed. The problem was that **the design
was wrong.**

### Why it was that way

1.0 controls were a **Brawl Stars-style dual floating joystick.**

```
0 ─────────── 404 ─────────── 808
   left = move      right = dash
              ↑ exact screen center
```

Brawl Stars is a **twin-stick shooter.** Left move · right aim-and-fire —
right for that genre.
This game had become a **survivor** through the rebuild. Only the control
scheme was left in the old genre.

The boundary is exact screen center and **there is no mark.** A natural
thumb rest sits right on that seam, so every press you could not tell
move from dash.

### What successful games do

We looked.

| Game | Controls |
| --- | --- |
| Vampire Survivors | **one** joystick on the left. Attack and skills all automatic |
| Survivor.io | one joystick, auto-attack. **one-hand play** |

The genre standard is **one move stick + auto-attack.** If there is a
dash, it is **a small button in a corner**, not half the screen.

### What we changed to

```
now:  [whole screen = move]  +  [bottom-right dash button]
```

- **Press anywhere and you walk.** "I pressed the middle and it slid"
  disappears at the source.
- The dash button sits **after** the stick in the tree, takes input
  first, and does not pass it down with `accept_event()`. You do not
  walk off while trying to press the button.
- The button has no direction, so you leave **the way you were going.**
  Standing still, the way you face.
  In a survivor a dash is not "where shall I go." It is "I have to get
  out now," so the way you were going is actually right.

:::tip If you changed the genre, look at the controls again
While we changed the game's structure we did not touch controls. So
**only the controls stayed in the old genre**, and that did not show
until we played it. The maker knows the rule, so they do not get confused.
:::

We also changed the "locked values" table in `AGENTS.md`. Locked does
not mean you can never change it — **when the reason you locked it
collapses, you change it.**

---

## 9. Wayfinding — a large map needs a compass

The cost of growing the map to 1900×1180 showed up immediately. The
screen is 808×360, so **the objective is usually off-screen.** Mid-play
the same question came twice.

> "I lit the 3 beacons, where am I supposed to go"
>
> "I lit all 3 beacons, where do I go"

**The second one hurts more.** The first compass only pointed at *unlit
beacons*. Light all three and there is nothing to point at, so the arrow
vanished, and that is when the guardian had appeared off-screen.

What you point at is not **"a beacon." It is "what you should do now."**
Guardian if there is one, otherwise the nearest unlit beacon. Color
separates them — moonlight (beacon) · blood (guardian).

### Do not put it in the middle of the screen

At first it orbited 116px from screen center. **Right next to the player,
so it blocked view.** A guide has to be seen, but it must not cover the
game.

Now it **sticks to the screen edge.** The intersection of a ray from
center toward the target with the edge. It has to be a **rectangle**,
not a circle —
`stretch aspect=expand` can widen the aspect to 4:1, and a circle leaves
left and right empty on a wide screen.

```gdscript
var tx: float = half.x / absf(direction.x)
var ty: float = half.y / absf(direction.y)
return view * 0.5 + direction * minf(tx, ty)   # whichever hits first
```

### A one-layer triangle sinks into the background

The first arrow was a solid triangle. Invisible on a dark forest. We
draw three layers.

1. **Outer bloom** — the same shape, twice as faint
2. **Body** — a chevron with a bite out of the back. Direction is clearer
   than a plain triangle
3. **Tip dot** — near white. Where the eye lands

And **farther means larger and faster.** It settles as you get close —
your body reads that you have arrived.
No image file. `_draw()`. Color and size keep changing, so code is cheaper.

---

## 10. Split the weapon in two — so the screen is not dull

A line from play.

> "Slashing is too bland. Can it slash cooler, or fly out like a gun, or
> power up. Old plane games and survivor games had a lot of those effects."

Fair. **One melee slash meant the same thing always happened on screen.**
Survivor fun comes from several weapons firing on their own and
**getting visibly stronger** — the feeling in old plane games when
bullets go from one to three.

### Moonlight arrows

We added a second weapon. Every 1.15 seconds it flies at the nearest
spirit on its own.

| | Slash | Arrow |
| --- | --- | --- |
| Range | 34 | **240** |
| Interval | 0.55s | 1.15s |
| Trait | fan, several at once | straight, can pierce |

**The two ranges overlapping is what creates "where do I stand."** Close
in and the slash turns; fall back and only arrows go. Where you stand
becomes a choice.

### Growth has to be visible

We added four arrow relics — twin (+1 shot) · piercing (pierce +1) ·
swift string (interval −30%) · heavy (damage +1).

Several shots **spread like a fan.** Stack them on one point and two
shots or three look the same on screen. 13 degrees apart and the extra
is obvious at a glance.

:::warning `Hitbox` is not what gets found
Arrows hit nothing at first. We tried to catch the spirit's `Hitbox`
with `area_entered`, but that node has `collision_layer = 0` — **it is
the finder of the player, not the found.**
What gets found is the body (`CharacterBody2D`, layer 4), so use
`body_entered`.
:::

---

## 11. Stacking — growth must not stop

A line from play: **"The weapon doesn't get stronger. Do stronger effects
appear? I wish they showed up sooner."**

A design mistake. We had made relics **not appear again once picked.**

- Eat `Sharp Moonlight` (damage +1) once and that is it
- Eat all fourteen and **a level-up gives nothing.** Growth stops there
- The total power-up you can get in a run is fixed from the start

**Survivors are the opposite.** Keep raising the same weapon until Lv 1
becomes Lv 8. Damage going from 1 to 6 is six stacks.

### What we fixed

- The same relic **appears again.** The card shows the next tier, like
  `Heavy Arrow Lv 3`
- The left HUD chip does not grow; only the number rises, `Heavy Arrow ×3`.
  Keep adding chips and the left of the screen fills with names
- When drawing, **put ones you do not have yet first.** One relic over
  and over is not a fun choice

### We pulled the first reward forward

| | before | after |
| --- | --- | --- |
| First level | 4 kills | **3 kills** (about 10 seconds) |
| Level multiplier | 1.28 | **1.20** |

1.28 was too steep later — the tenth level needed 40 kills; 1.20 needs
24. **A late first relic starts the game dull.**

---

## 12. Strength has to show on screen

We made fourteen relics, fixed "the weapon doesn't get stronger," and
this time **"attacks keep looking the same so it feels boring"** came out.

Those are different problems. The first was growth stopping. This one is
**growth you cannot see.** Damage goes from 1 to 6 and the screen still
fires the same one slash. The number is not even on the HUD, so the
player has no way to know.

### Grow the weapons you have

We first made what we already had visible. Three relics each change the
picture **in a different direction.**

```gdscript
var reach: float = attack_range / DEFAULT_ATTACK_RANGE
var width: float = attack_arc / DEFAULT_ATTACK_ARC
_slash.scale = Vector2(reach, reach * width)      # range is length, fan is width

var heat: float = clampf(float(attack_damage - 1) / 5.0, 0.0, 1.0)
_slash.modulate = Color(3.1 + 1.6 * heat, 2.8 + 1.0 * heat, 1.9 + 0.4 * heat, 1.0)
```

Stack `Long Blade` and the slash gets longer, stack `Wide Slash` and it
gets wider, stack `Sharp Moonlight` and it burns white. Arrows thicken
the same way, and pierce puts a blue tint on them.

### Add more weapons

Size and color have a ceiling. The survivor answer is **add one more
weapon.** A bible orbits, garlic spreads, lightning drops.
You know you got stronger not from a number but from **the screen getting
noisy.**

We made two relics that way. Unlike the previous fourteen, these two do
not change values. They attach a node.

| Relic | What appears | On stack |
| --- | --- | --- |
| Moon Ring | orbs orbit the player | more of them, they spin faster |
| Moonlit Ripple | light spreads in every direction | wider, more often, more painful |

Neither has a sprite. `_draw()` — a few circles, and a texture would
make resizing on every stack a chore.

For the ring, **drawing the trail with it** mattered. Dots alone look
like blinking, not orbiting.

```gdscript
for t in 4:
    var back: float = angle - 0.13 * float(t + 1)
    var fade: float = 0.22 * (1.0 - float(t) / 4.0)
    draw_circle(Vector2.RIGHT.rotated(back) * RADIUS, ..., Color(0.62, 0.82, 1.0, fade))
```

Orbs need a re-hit delay. Without it they hit **every frame** while
touching, and the spirit dies instantly.

:::caution `kind` is shared by several spirits
Write `kind.score_value *= 4` to raise an elite's score and **every
spirit of that kind** gets elite score. `.tres` is a shared resource.
`kind = kind.duplicate()` first, so only that one changes.
:::

## 13. If endless is not to get boring

After adding weapons, the next problem showed. **Spirits stayed the same
as the cycle rose.** Only the guardian got stronger, fodder was cycle 1,
so in cycle 3 with nine relics you melted everything by walking. Cycles
became waiting, not a goal.

Endless play needed three things.

### 1. Spirits grow with you

```gdscript
func toughness() -> float:
    if _cycle <= 3:
        return pow(1.35, float(_cycle - 1))
    return pow(1.35, 2.0) * pow(1.58, float(_cycle - 3))
```

The player adds about three relics per cycle. Raise to that growth or
tension leaves. Too steep is a wall; too shallow is a stroll.

Guardians need more than this multiplier. Burst budget is a **health
ratio**, so on a finished-firepower run the boss melted at the same
second even as cycles rose. From cycle 4 we drop the budget floor
further, add `1.22` on the boss only, and speed barrages and charges.
Accelerate fodder the same way and you get a pretty screen of unkillable
enemies.

The cap grows too. Fix it at 24 and cycle 5 still looks as empty as
cycle 1, and the five weapons you worked to grow cannot find anything
to hit.

### 2. Elites mix in

Sometimes a 3×-tough one appears. What matters is **not health. It is
being obvious.** If you do not change size and light first, the player
does not know why this one will not die.

They do not appear in cycle 1. A 3×-tough thing with zero relics kills
you before you learn.

### 3. Raids — quiet and mayhem

The largest change. **A steady stream alone makes endless boring.**
Spirits walking in one at a time at a fixed interval feel the same at
10 minutes or 30.

Once every 32 seconds they **surround** the player and appear at once.

```gdscript
var lead: float = randf() * TAU
for i in many:
    var angle: float = lead + TAU * float(i) / float(many) + randf_range(-0.2, 0.2)
    var at: Vector2 = _player.global_position + Vector2.RIGHT.rotated(angle) * reach
    _summon(_room.clamp_to_play(at))
```

Surround is the point. A pile from one side and you just walk the other
way. A circle cages you and **you have to break out.** That is also when
dash earns its keep.

`clamp_to_play()` was needed. On the map edge, half the circle is
outside the wall, and spirits placed outside cannot walk in, so **they
do not exist.**

After a raid it is quiet for a moment. **Drop only exists if quiet
follows.** Cut the interval to 20 seconds and raids become the default,
and the drop disappears whole.

:::tip Notices overlapped
The raid notice and the relic-panel title stacked on one line. Moving
the position is worse than **clearing the banner when the panel opens** —
text left behind a paused screen has no reason to be read anyway.
:::

## 14. The real reason growth stopped

"After the weapon is kind of there it doesn't get stronger so it's less
fun." This came after sixteen relics and stacking. Fixing by feel would
be wrong again, so we **checked numbers first.** What came out was not
what we expected.

### Stacking was locked for 3 minutes

Relic-card draw code was this.

```gdscript
var order: Array[String] = fresh + owned
for i in mini(CARD_COUNT, order.size()):
```

A comment said we would weight "already stacked ones a little less,"
but **the code had no weights.** Concatenation is not a weight. It is a
hard priority.

With 16 relics, while `fresh.size() >= 3`, i.e. **through the fourteenth
pick all 3 cards are new relics.** The first stack card appears on pick
15. About 3 minutes.

Survivor growth comes from stacking. Seal that for half the game and of
course it feels like filling a checklist.

Now one card slot is new, one is **the most stacked**, and the rest mix.
You can push a main from the first run.

### Additive vs exponential

There was a more fundamental problem.

| | Growth | 10 stacks / 10 cycles |
| --- | --- | --- |
| Player damage | `attack_damage += 1` | ×11 |
| Spirit health | `pow(1.35, cycle - 1)` | ×20 |

**Different dimensions.** The first stack is +100% (1→2) but the tenth
is +9% (11→12).
Spirits are ×1.35 every cycle, no exceptions. Absolute damage rises, but
kills per second peaked at 3.5 at 2 minutes and **fell to 0.35 at 15
minutes.**

The screen gets prettier and spirits die less. That was the identity of
"not getting stronger."

We made damage relics multiplicative. Not `+1`, `×1.35`. Now the player
grows exponentially too, and they fight in the same dimension.

```gdscript
_damage_mult *= relic.amount
_player.attack_damage = _scaled(Player.DEFAULT_ATTACK_DAMAGE, _damage_mult)
```

`_scaled()` rounds and guarantees a minimum of 1. Truncate with `int()`
and two multiplies of 1.35 stay 1 → 1 → 1, and two stacks vanish whole.

### Things that quietly did nothing

Sweeping the numbers found several places where **you picked a card and
nothing changed.**

- **Wide Slash** — `minf(arc * 1.5, 300.0)`. 110 → 165 → 247 → 300 (clip) → 300.
  Loss starts at 3 stacks and from 4 stacks it is exactly 0. The card
  still appeared and the description still said "+50%."
- **Moon Ring** — the re-hit cooldown dictionary hung on one `MoonRing`
  node. Grow orbs to eight and one spirit still takes one hit per 0.45s.
  `count` made the screen pretty and DPS did not rise a grain.
- **Integer truncation** — `1 + int((count - 1) * 0.5)` is 1,1,2,2,3,3…
  Even stacks add exactly 0.
- **Swift Hand** — once the attack interval is shorter than 1/60s,
  nothing happens after that. One `if` in `_process` forced once per
  frame.

:::caution A cap kills the card
Put `minf(..., cap)` on a value and the moment that relic hits the cap
it becomes a **dead card.**
The player cannot tell they ate it and nothing happened.
If you need a cap, send the overflow down another axis. The fan stops at
360 degrees, and the excess goes to damage.
:::

## 15. Missiles going out like crazy

"Old plane games, you know, that dopamine of missiles going out like crazy."

Straight arrows, however many shots, only widen the fan. Miss and they
just pass. Homing is different — **everything you fire goes to hit.**

Stack three or more arrow-line relics and arrows become `Moonlit Meteor`.

```gdscript
if _arrow_invest() >= MISSILE_AT:
    _fire_missiles(target)
    return
```

### Full homing looks like a straight line

Stick to the target and fly and the picture is an arrow. It has to pop
out to the side first and curve in slowly **for the curve to show.**

```gdscript
var turn: float = clampf(_heading.angle_to(want), -TURN_RATE * delta, TURN_RATE * delta)
_heading = _heading.rotated(turn)
```

`lerp` turns faster the farther you are, so you get a polyline, not a
curve. Cap the max turn angle and take that much each time for smoothness.

Split the targets too. Twelve shots on one body and the rest vanish, and
the screen is one stacked explosion.

### Strength has to keep being visible

Linear visual emphasis saturates fast. A ceiling at damage 6 made 6 and
60 the same blade size and color to the pixel. We switched to log.

```gdscript
var heat: float = clampf(log(float(maxi(attack_damage, 1))) / log(64.0), 0.0, 1.0)
```

The same multiplier brightens by the same width. 5 → 10 and 50 → 100
look like the same jump.

## 16. You dodge if there is something to lose

If firepower only goes up, late-game tension leaves. Invincible is boring.

Old plane games had an answer. **Take a hit and a power-up pops off and
rolls around.** You decide on the spot whether to risk your life to pick
it up or give it up.

Take a hit and the most recently eaten relic becomes an orb and pops
out. Pick it up within 9 seconds and it returns; miss it and it is gone
forever. It blinks fast just before vanishing to hurry you.

Health also hangs directly on power. One heart left is 65%.

```gdscript
func _frailty() -> float:
    var ratio: float = float(_health) / float(maxi(_max_health, 1))
    return lerpf(FRAIL_FLOOR, 1.0, clampf(ratio, 0.0, 1.0))
```

Halve it and you get an unrecoverable death spiral — weaker so you take
more hits, more hits so you get weaker. 65% is the width one dew pip
brings back by feel.

### When you lose a relic, do not subtract in reverse

Reversing relic effects one by one means divide the multiplies and
subtract the adds, and **anything that hit a cap cannot be reversed.**
One wrong division and stats stay quietly wrong for the rest of the run.

Revert to defaults and **feed what remains from the start again.** That
mistake becomes impossible at the source. Forty relics still take under
a millisecond, and we only call it on hit.

:::danger You cannot attach a node during physics processing
`Can't change this state while flushing queries`.

Getting hit, picking up, and a spirit scattering are all inside
`body_entered`, i.e. while the engine is walking collision queries.
Attach or detach an `Area2D` in there and it dies.

This was a **bug that did not show** until homing missiles. Missiles
started catching spirits inside physics, and the old Moon Dew drop code
blew up with them.

`add_child.call_deferred(node)` attaches next frame.
:::

## 17. If verification takes 5 minutes you cannot fix anything

This chapter's work was possible only because we first made **a button
that jumps to the late game in one second.**

Auto input (`adb shell input`) cannot dodge, so it dies around a minute.
A human playing 20 minutes is not an answer either — 20 minutes per
number change means checking costs more than fixing.

We put three buttons bottom-left on the title: `Lv10` · `Lv20·3 cycles` ·
`Lv40·5 cycles`.
If `OS.is_debug_build()` is false they `queue_free()` themselves.
Not a check, not a hide — if they stay, they will show someday.

We did not make a new autoload to pass values. `SceneTree`'s root lives
across scene changes.

```gdscript
get_tree().root.set_meta(BOOST_META, [level, cycle])
get_tree().change_scene_to_file("res://scenes/gameplay/arena.tscn")
```

**We were lied to twice.** First we did not push `_survived`, so cycle 5
spawned at early density. We almost judged "firepower is weak" trusting
that screen as late game.
Second we did not fill enemies, so the screen was empty. Forty relics in
hand and nothing to hit.

Now we push survival time and call a raid three times so enemies fill too.

### Headless check does not compile scripts

`pnpm game:check` opens the main scene and quits. **A script the title
screen never touches is not even compiled.** Arena, spirits, and
projectiles only parse when you actually start a game.

We kept seeing `Identifier "heat" not declared` after a green light, an
APK, install, and launch. A 5-minute round trip.

`tools/check_scripts.gd` `load()`s everything under `res://scripts`.
For GDScript, load is compile.

```bash
pnpm check:scripts   # compile check of 38 scripts
```

Run it **as a scene**, not `--script`. `--script` mode has no autoloads,
so every script that uses `Records` or `Settings` falsely flags
"Identifier not found."

Be clear about what it cannot catch. It only sees whether it compiles —
we deleted `take_random()` and this check still passed. Calling a missing
function is a runtime error, so you have to run it.

## 18. Something that survives death — without this they will not launch again

That was the **inside-a-run** story. Relics stack, weapons evolve, the
screen gets noisy. Die and it all vanishes. What remains is one best-score
number.

In an endless survivor that is fatal. Play well for 30 minutes, die, and
the next run is **bare-handed level 1 again.** Unless skill grows, yesterday
and today are the same. No reason to launch again.

Every successful game in this genre has out-of-run growth. Something has
to have gone up when a run ends, or you do not get "one more run."
Without that it is not a good game. It is **a good demo.**

### Shards and boons

When a run ends you get `moon shards` equal to score. At the title's
`Moonlit Shrine` you buy `boons` with shards — a boon pulls the next
run's starting line a little forward.

| Boon | What changes | Cap |
| --- | --- | --- |
| Sturdy Heart | starting hearts +1 | 3 |
| Honed Edge | starting damage +12% | 5 |
| Light Foot | walk speed +8 | 3 |
| First Gift | start holding a relic | 2 |
| Dew Scent | dew chance +15% | 3 |
| Shard Sense | shard gain +20% | 3 |

They pair with `Relic` — relics live only inside a run, boons live across
runs. Same `.tres` pattern, so a new one does not grow code.

```gdscript
func grace(kind: int) -> float:
    var sum: float = 0.0
    for path in POOL:
        var rank: int = rank_of(path)
        if rank <= 0:
            continue
        var boon: Boon = load(path) as Boon
        if boon != null and boon.grace == kind:
            sum += boon.amount_at(rank)
    return sum
```

### There must be a cap

Every boon has a tier cap. Without it a long-time player becomes
**invincible from the start** and the game disappears for that person
only. A boon pulls the starting line. It is not a skip-the-run device.

### The first upgrade has to land in two or three runs

At first we set one shard per 900 score. Real runs dropped three or four
a run, and the cheapest boon (35) needed **twelve runs.** That is enough
to quit without knowing shards exist.

We cut it to 500 and first-tier prices to 12–45. A decent run (4,000
points) is eight shards; two runs and the first boon is in hand. Too
generous and you buy everything in two runs and nothing remains again —
finding that gap is the whole job.

### Keep the files separate

This repo already split `settings.cfg` and `records.cfg` —
"records are play results and settings are taste." The vault is a third:
**not play results, but wealth piled up by play.** Records can wipe and
wealth should remain, and the reverse too.

:::caution A new `class_name` is not visible until the project is rescanned
Make `class_name Boon` and use it immediately and you get
`Could not find type "Boon"`.
The global class list updates when the editor imports.

```bash
godot --headless --path apps/game --quit --editor
```

That is why CI runs this line first.
:::

## 19. Characters — a different run from the first second

Boons raise numbers a little. That alone does not make the run different.
Relics are random too, so repeated runs eventually arrive at similar
places.

**A character is different from the first second.** Which weapon you
start holding sets the run's direction.

| Character | Grain | Unlock |
| --- | --- | --- |
| Moonlit Warden | even performance. slash and arrows | from the start |
| Shadow Dancer | fast move and dash · violet twin-crescent · `Moon Ring` | non-consumable $4.99 |
| Beacon Keeper | sturdy health · jade lantern ripple · `Moonlit Ripple` | non-consumable $9.99 |
| Silver Moon Knight | heavy defense · silver crescent fan · long slash | non-consumable $14.99 |
| Eclipse Mage | agile combos · crimson eclipse ring · Swift Hand | non-consumable $19.99 |
| Constellation Sage | long-range pierce · teal constellation chain · twin arrows | non-consumable $24.99 |

Same pattern as `SpiritKind` · `Relic` · `Boon` — one `.tres` is one
character, and a new one does not grow code. This repo uses the same
shape **a fourth time.** That is how right the pattern was.

### Keep the totals close

If one is obviously strong, the rest are decoration and choosing is not
fun. The dancer hangs back and grinds with orbs; the keeper dives in
and spends with ripples.
What differs is **grain, not strength.**

### Order matters

Feed the character first, then put boons on top.

```gdscript
var hero: Hero = Vault.hero()
_max_health = hero.health
_damage_mult *= hero.damage_scale
...
var hearts: int = int(Vault.grace(Boon.Grace.START_HEALTH))
```

Reverse the order and multipliers overwrite each other, and Beacon
Keeper's damage bonus vanishes.

### Free clear and paid heroes

Moonlit Warden alone can play every terrain, guardian, and cycle to the
end. The other five are not combat-power ranks. They are balanced
options with different starting relics, colors, and projectile/cast
effects. Tap a shop portrait to preview look and effect text even while
locked, then equip at the shrine after purchase. On reinstall or device
change, `Restore purchases` brings them back.

:::tip Do not try to write the save file from outside
Checking the shrine needs shards, and earning them normally takes tens
of runs.
We tried to write `user://vault.cfg` directly with `adb run-as` and
**permission was denied.**

```text
can't create /data/data/.../files/vault.cfg: Permission denied
```

A grant button inside the debug build is more reliable.
:::

## 20. Ladder — arcade high score

Die, the score appears, and if you are in the top you enter a name. The
table appears and your row stays bright.

### Local first

A global ladder is nice, but **the game has to run without it.** No
network or no API key baked in, and it quietly uses local only — it does
not stall the result screen or throw an error. Someone playing in
airplane mode must not be blocked from the game by a ladder.

The Firestore project (`moonlitbeacon-778ee`) is ready and the attach
point is in place, but **the web API key is not baked into the repo.**
Google assumes the key itself is public, but having the key lets someone
burn quota as a joke.

### Do not force a listing

Ask for a name every time and you are annoyed by the third run. **Ask
only when you make the top ten** — then asking itself is a reward.

Prefill the last name. Make people type every time and they skip listing
on the second run.

```gdscript
_name.text = Ladder.last_name
_name.select_all()
```

### Write character and version too

Heroes grew to six, and **who got that score on which character** is
half the ladder. Per-character ranks later come from this data too.

Scores after a balance change cannot be compared as-is with previous-build
scores. So before listing a name we confirm **character · app version ·
score** on one line, and we leave the version at the end of each saved
row. The table groups latest version first and sorts by score inside a
version. Existing records without a version field migrate as first-ship
`1.0.0`.

### One panel has two faces

The moment you enter a name and the moment the rank goes up are
**one connected scene.** Change the screen and that connection breaks.
Enter a name and the table appears in place, and your row stays bright.

:::caution Always turn the previous panel off
The ladder panel's dim is 0.82, so the back shows through. Leave the
result screen on and score breakdown and name field stack on one
screen — we actually captured that.

```gdscript
_result.visible = false
_ladder.ask(...)
```
:::

### Only here we use JSON

Until now the repo only used ConfigFile (`records.cfg` · `settings.cfg` ·
`vault.cfg`).
The ladder is different because we put **dictionaries inside an array.**
A ten-row table in ConfigFile means keys like `row_0_name`, and then the
reader has to know the table's shape.

### Upload globally

Godot has no Firebase SDK. **We call Firestore REST directly.**
There is little to attach, and if it fails we can quietly step back.

```gdscript
var url: String = "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/%s?key=%s"
```

Firestore writes a type name on every value. **Numbers are sent as
strings too** — a spec that avoids integer-range differences across
languages.

```gdscript
"score": {"integerValue": str(score)},
```

`runQuery` comes back one line per document, and no results is a single
line with no `document` key.
So walk the array and pick only what is there.

#### Do not bake the key into the repo

```gdscript
const KEY_PATH: String = "res://firebase.cfg"
```

Google assumes a web API key itself is public (unzip the APK and you see
it anyway).
Bake it into the repo and **a fork burns someone else's quota.**
No file, and the global feature turns off whole — that is the default.

To use it, make `apps/game/firebase.cfg` (it is in `.gitignore`).

```ini
[firebase]
web_api_key="..."
```

Five things to do in the console and the repo.

1. **Firestore Database** → create a database → production mode
2. In **Rules**, allow **create only** on the `scores` collection (read
   public, no update or delete)
3. From the repo root run
   `firebase deploy --only firestore:indexes --project moonlitbeacon-778ee`
   → confirm index status is **Ready** in the console
4. Copy **Project settings → General → Web API key**
5. Paste into `apps/game/firebase.cfg`

Android internet permission is also needed. We spelled it in
`export_presets.cfg` — better not to trust Godot defaults. We confirmed
`android.permission.INTERNET` in the actual APK manifest.

:::caution The game has to run without it
No key or no network and this autoload does nothing, and the ladder
panel shows the local table as-is. It does not stall the result screen
or throw an error.
**Someone playing in airplane mode must not be blocked from the game by
a ladder.**

Response wait also cuts at 6 seconds. Making a person wait is worse than
one record.
:::

:::danger An autoload name must not collide with an engine class
We first named it `Sky` and it **hit Godot's built-in `Sky` (skybox
resource)** so neither signals nor functions could be found. An autoload
name is a global identifier.

```text
Parse Error: Cannot find member "board_arrived" in base "Sky".
```
:::

### What we have not done yet

A name is a place other people see. We did not filter swearing — a list
is punched through quickly, and doing it properly needs a server. **Handle
it together when you actually turn on a global ladder.** That you can
tamper a score the client sends also has to be designed honestly then.

## 21. From 1fps to 30fps — you cannot fix it without a gauge

Late game was 1fps. The `fps` number alone does not say where it is slow,
so we **stuck a gauge on first** — cpu · phys · draw calls · primitives ·
node count on screen.

Every outside-measurement path was blocked.

| Attempt | Result |
| --- | --- |
| `dumpsys gfxinfo` | `Total frames rendered: 0`. Godot uses its own SurfaceView |
| `dumpsys SurfaceFlinger --latency` | the emulator does not fill timestamps |

### Fix order and actual effect

| Change | fps | phys |
| --- | --- | --- |
| (start) | 1 | 112ms |
| `antialiased = false` | 4 | 26ms |
| drop fills · entity count · physics 30 ticks | 7 | 73ms |
| fewer draw calls · missile cap | 13 | 49ms |
| `Area2D` to instant queries | 11 | 51ms |
| remove hot-path allocations | 11 | 55ms |
| **remove `move_and_slide()`** | **30** | **30ms** |

### We were wrong three times

**Antialiasing.** Godot's 2D `antialiased = true` turns one line into
dozens of triangles. Turn it off on `draw_arc` and
`draw_polyline_colors` and Lv20 went from 3fps to 50fps. One line.

**`phys` was a symptom, not a cause.** When a frame collapses, several
physics ticks pile into one render and the time inflates. Read this
number as a cause and you dig physics in the wrong place.

**Removing `Area2D` had no effect.** We switched ripple and ring to
instant queries and `phys` stayed 51ms. The code got cleaner, but it
was not the bottleneck.

### The real culprit

Spirits have `collision_mask = 0`. **They collide with nothing and we
were still calling `move_and_slide()`.** That function still runs a
motion query with no collision targets.
Forty bodies is forty wasted queries every physics tick.

```gdscript
func _glide() -> void:
    position += velocity * get_physics_process_delta_time()
```

Those three lines took `phys` from 55ms to 30ms, fps from 11 to 30.
**Node count had actually gone up** (1033 → 1208).

:::tip If it does not collide, do not use `move_and_slide()`
Using `CharacterBody2D` does not mean you have to use that function.
No walls and nothing to push, and moving the coordinates yourself is
dozens of times cheaper.
:::

### Remaining honest limits

Emulator numbers. GLES→host conversion can differ from a real device.
The gauge is in the debug build, so you can check on a device immediately.

## 22. There was a path we had never run

Through this whole rebuild we had never run **three beacons → guardian →
next cycle** to the end. Even though it is the game's central loop.

The reason is simple. Auto input cannot find beacons on a 1900×1180 map,
and a human still takes over a minute per cycle. Every time we touched
cycle-transition code we could not spend that time, so we went with
**"it should work, the code looks right."**

### A tool that changes state inside the arena

The title test buttons only create the state that **opens** a run. They
cannot change state **while a run is going.** And the unconfirmed path
happened to be mid-run.

We put one more debug-only row on the arena — `3 beacons` and `health↑`.
In release they vanish with `queue_free()`.

### And a bug came out immediately

```text
SCRIPT ERROR: Invalid assignment of property or key 'monitoring'
              with value of type 'bool' on a base object of type 'Nil'.
   at: materialize (res://scripts/actors/spirit.gd:237)
```

To block node adds during physics we switched to
`add_child.call_deferred(_guardian)`, and **left `materialize()` on the
next line as-is.** At that moment the guardian is still outside the tree,
so `@onready var _hitbox` has not run.

```gdscript
add_child.call_deferred(_guardian)
...
_guardian.materialize.call_deferred()   # this has to be deferred too
```

Deferred calls run in registration order, so `add_child` runs first.

**It was a code path that only appears after lighting three beacons, so
nobody had stepped on it.** Headless check and script compile check
cannot catch this — it compiles and only dies at runtime.

### What we confirmed after the fix

Beacons 3/3 → `The Guardian awakens` and a health bar → kill →
`Beacons 0/3 (wave 2)`.
The cycle actually advanced. **The first time.**

### One loop was not enough — through eight

One advance can be luck. To see if it repeats you have to run several
loops **in one run**, and we hit two walls there.

**First, you die.** A heal button alone was not enough — twelve hearts
gone between heals and you die, restart, cycle goes back to 1, and the
check is from scratch.
We added an `invincible` toggle.

**Second, you cannot reach the guardian.** Auto input only draws circles
in place, meteor range is 312px, and the map is 1900×1180. The guardian
appears at the point farthest from the player. In cycle 3 we tried eight
times and **never met it once.**

Here we split: make one more tool, or go with "3 worked so we are done."
We picked making it — **what we are confirming is whether
`_finish_cycle()` runs any number of times, not pathfinding skill.**
`guardian↓` puts it down immediately.

Repeat `3 beacons → guardian↓` eight times and we reached **`wave 8` in
one run.** No errors, 60fps, elites mix in. `_cycle` goes back to 1 on
restart, so the number 8 itself is evidence of eight consecutive
transitions.

:::tip Time spent making verification tools is not a cost
`3 beacons` · `health↑` · `invincible` · `damage×10` · `guardian↓` took
under an hour for five of them. Those five **found a bug on a path we
had never run**, and confirmed eight cycle loops in a few minutes. A
human takes over ten.

All of them vanish with `queue_free()` unless `OS.is_debug_build()`.
:::

:::tip Count the paths you have not run
"Looks right in code" is not verification. Everything that actually died
in this rebuild sat on **a line that had never executed** — the guardian
that only appears after three beacons, the orb that only drops on hit,
the recalculation that only runs when you lose a relic.

If checking is expensive, **make checking cheap** first. That beats
making one more feature.
:::

## 23. What headless check cannot catch

`pnpm game:check` only opens and closes the project. **It does not load
the arena scene.** Several things showed only on device during the rebuild.

### Missing `class_name`

We used `Room.PLAY` and `room.gd` had no `class_name Room`.
`game:check` passed and the device died with
`Identifier "Room" not declared`.

### A typed lambda meeting a freed object

```gdscript
# do not write it this way
_spirits = _spirits.filter(func(s: Node2D) -> bool: return is_instance_valid(s))
```

It could not convert a freed object to `Node2D`, and every call printed
two error lines.

```
Cannot convert argument 1 from Object to Object.
Trying to assign an array of type "Array" to a variable of type "Array[Node2D]"
```

**Worse, the assignment fails and the dead references stay.** Dead
spirits occupied the `MAX_SPIRITS` cap and new spirits did not spawn.
Through Lesson 13 spirits only vanished on `retreat()`, so it almost
never hit; once you could slash, it blew up on every death.

We fixed it with a plain `for`.

:::tip Look at emulator logcat
```bash
adb logcat -d | grep "E godot"
```
Even if `pnpm game:check` passes, look once more with this. Both of the
above came from here.
:::

---

## 24. What we kept while making it

### About the code

- **One `.tres` is one** — `SpiritKind` · `RoomKind` · `Relic` · `Boon` · `Hero`.
  A new one does not grow code. This pattern paid off **five times.**
- **Split the side that decides from the side that draws** — the HUD
  judges nothing, and the player does not find enemies.
- **Write a reason on a number** — why 34, why 0.55 seconds. When you
  change it later you know what you break.
- **Do not subtract in reverse; recompute from the start** — reverse
  relic effects one by one when you lose one and you cannot restore
  anything that hit a cap. Revert to defaults and feed what remains
  again, and that mistake becomes impossible at the source.
- **A cap kills the card** — put `minf(value, cap)` on it and the moment
  that relic hits the cap it becomes a card that does nothing. Send the
  overflow down another axis.

### About how to fix

- **Turn impressions into numbers.** "Not fun" cannot be fixed. "The
  enemy is 12px/s slower" can. Sections 1 and 14 of this document are
  the same method.
- **If checking takes 5 minutes you cannot fix it.** If every number
  change means making an APK, installing, and playing 20 minutes,
  checking costs more than fixing.
  **Make verification tools first.**
- **Do not trust your eyes. Measure.** Several calls we judged by eye in
  this rebuild were wrong — we thought night had vanished but brightness
  was 36/255, we thought the hit flash was broken but it was one frame,
  and the reason frames were slow was wrong all three times.
- **Try to refute the criticism.** 34 of 42 hostile reviews were
  refuted. Without a verification step we would have broken healthy code
  fixing those 34.

### What we have not done yet

Left honestly.

- Cycle 1 → 2 we ran to the end and confirmed (section 22). We have not
  gone **through cycle 5 in one run.** Late-game firepower we confirmed
  by skipping with debug buttons.
- Performance numbers are all from the emulator. A real device can differ.
- The ladder is local only. Going global means designing name filtering
  and score-tamper prevention together — a score the client sends can be
  tampered in 5 minutes.

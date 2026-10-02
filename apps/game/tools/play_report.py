#!/usr/bin/env python3
"""Read what the play bot wrote and say what it found.

    python3 apps/game/tools/play_report.py builds/play/b1a.json builds/play/b1b.json

One line per run, then the same runs broken down by what a designer asks: where the hits came from, how
long each place and each guardian took and how much it hurt, whether anything got the bot stuck, whether
the field ever went quiet for too long, how the frame time held. It only summarises; what to change is
a judgement, and the numbers are here to make that judgement about the play and not about a feeling.
"""

from __future__ import annotations

import json
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path


def load(paths: list[str]) -> list[dict]:
    runs: list[dict] = []
    for path in paths:
        for run in json.loads(Path(path).read_text()):
            run["source"] = Path(path).stem
            runs.append(run)
    return runs


def cause_family(cause: str) -> str:
    return cause.split(":")[0]


def main() -> int:
    runs = load(sys.argv[1:])
    if not runs:
        print("no runs")
        return 1
    print(f"{len(runs)} runs, {sum(int(r['stats']['loops_done']) for r in runs)} loops")
    print()
    print("run  hero      loops  time   cycle  lvl  kills  hits  hp  dash  stuck  spike  end")
    for run in runs:
        s = run["stats"]
        print(f"{run['source'][-3:]}{int(run['run']):>2}  {run['hero']:<9} {run['loops']}      "
              f"{s['seconds']:>5.0f}  c{s['cycle']:<4} {s['level']:<4} {s['kills']:<6} {s['hits']:<5} "
              f"{s['hp_left']:<3} {s.get('dashes', 0):<5} {s['stuck']:<6} {s.get('spikes', 0):<6} {s['reason']}")

    total_minutes = sum(float(r["stats"]["seconds"]) for r in runs) / 60.0
    hits = [h for r in runs for h in r["hits"]]
    print()
    print(f"hits: {len(hits)} in {total_minutes:.1f} minutes = {len(hits) / max(total_minutes, 0.01):.2f} a minute")
    by_family = Counter(cause_family(h["cause"]) for h in hits)
    print("  by kind:", dict(by_family.most_common()))
    by_cause = Counter(h["cause"] for h in hits)
    print("  by cause:", dict(by_cause.most_common(12)))
    boss_hits = [h for h in hits if h["guardian"]]
    print(f"  in guardian fights: {len(boss_hits)}   in zones: {len(hits) - len(boss_hits)}")

    print()
    print("places (zone time, hits a minute, arrival hp):")
    place_time: dict[str, float] = defaultdict(float)
    place_hits: Counter = Counter()
    place_count: Counter = Counter()
    for run in runs:
        zones = run["zones"]
        ends = [z["t"] for z in zones[1:]] + [run["stats"]["seconds"]]
        for zone, end in zip(zones, ends):
            place_time[zone["place"]] += end - zone["t"]
            place_count[zone["place"]] += 1
        for hit in run["hits"]:
            zone = next((z for z, e in zip(zones, ends) if z["t"] <= hit["t"] < e), None)
            if zone is not None and not hit["guardian"]:
                place_hits[zone["place"]] += 1
    for place in ("forest", "field", "camp", "frost", "marsh", "ruins"):
        if place_count[place]:
            minutes = place_time[place] / 60.0
            print(f"  {place:<7} zones {place_count[place]:<3} {place_time[place] / place_count[place]:>5.0f}s each, "
                  f"{place_hits[place] / max(minutes, 0.01):.2f} hits/min")

    print()
    print("guardian fights (kind: fights, seconds, hits, hp before -> after):")
    fights: dict[str, list[dict]] = defaultdict(list)
    for run in runs:
        for fight in run["guardians"]:
            fights[fight["kind"]].append(fight)
    for kind, rows in sorted(fights.items()):
        print(f"  {kind:<22} {len(rows):<2} {statistics.mean(f['seconds'] for f in rows):>6.1f}s "
              f"{statistics.mean(f['hits'] for f in rows):>4.1f} hits   hp {statistics.mean(f['hp_before'] for f in rows):.1f} "
              f"-> {statistics.mean(f['hp_after'] for f in rows):.1f}   mutations {statistics.mean(f['mutations'] for f in rows):.1f}   "
              f"level {statistics.mean(f['level'] for f in rows):.0f}")

    volleys = [h for h in boss_hits if h.get("volley") is not None]
    if volleys:
        print()
        print("guardian bolt hits by what fired them and how long the bolt had been in the air:")
        by_volley: dict[str, list[float]] = defaultdict(list)
        for h in volleys:
            by_volley[h["volley"] or "?"].append(float(h["age"]))
        for label, ages in sorted(by_volley.items(), key=lambda kv: -len(kv[1])):
            fast = sum(1 for a in ages if a < 0.5)
            print(f"  {label:<10} {len(ages):>3} hits   median age {statistics.median(ages):.1f}s   "
                  f"within half a second {fast}")

    print()
    stuck = [s for r in runs for s in r["stuck"]]
    print(f"stuck: {len(stuck)}", [(s["place"], s["goal"], s["at"]) for s in stuck][:10])
    lulls = [e for r in runs for e in r["events"] if e["kind"] == "lull"]
    print(f"lulls (12 s with nothing near): {len(lulls)}")
    spikes = [e for r in runs for e in r["events"] if e["kind"] == "frame_spike"]
    if spikes:
        print("frame spikes:", [(e["ms"], "travel" if e["transitioning"] else "play", e["cycle"]) for e in spikes][:10])
    soft = [r for r in runs if r["stats"]["reason"] == "soft_lock"]
    print(f"soft locks: {len(soft)}")
    peaks = [r["stats"]["bolt_peak"] for r in runs]
    print(f"bolt peak: max {max(peaks)}  spirit peak: max {max(r['stats']['spirit_peak'] for r in runs)}  "
          f"frame max: {max(r['stats']['frame_max_ms'] for r in runs)} ms")
    if any("bullet_peak" in r["stats"] for r in runs):
        print(f"bullets: peak {max(r['stats'].get('bullet_peak', 0) for r in runs)}, "
              f"average in the air {statistics.mean(r['stats'].get('bullet_avg', 0) for r in runs):.1f}, "
              f"share of the time with one within 80 px (weaving) "
              f"{100 * statistics.mean(r['stats'].get('weave_share', 0) for r in runs):.0f}%")

    gates = [g for r in runs for g in r["gates"] if g["options"]]
    if gates:
        picked = Counter(g["options"][g["picked"]] for g in gates)
        offered = Counter(o for g in gates for o in g["options"])
        print(f"forks: {len(gates)}  offered {dict(offered)}  taken {dict(picked)}")
    picks = [p for r in runs for p in r["picks"]]
    skills = [p for p in picks if p["new_skill"]]
    print(f"cards: {len(picks)}  new skills taken: {[p['relic'] for p in skills]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

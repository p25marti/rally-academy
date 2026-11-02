"""Stage 1 (docs/DRIVER.md): tune a technique card's dials for one surface with CMA-ES (es.py), in fast mode.

    python tools/driver/tune.py C08 [--surface gravel] [--generations 12] [--starts 3] [--select 10] [--seed 1]

Each generation tries every candidate from the same few varied starts (attempt.varied_start), so candidates are
compared on equal terms; a candidate's fitness is its mean score (attempt.score) over them. The safety-net time limits
on the card (the *MinS / *MaxS dials) aren't tuned.

Three starts are too few to pick the winner by: the best single fitness is mostly luck with the starts (on gravel,
2026-11-02, the best of 396 attempts passed 15 of 20 fresh starts, worse than the card's own dials, while later
candidates passed 20 of 20). So the run ends with a selection: the top candidates of the second half of the run, and
the optimiser's final mean, each drive the same `--select` fresh starts; the one with the most passes (then the best
mean score) is written to dials/<card>-<surface>.json, which attempt.py then uses. Every attempt is logged to logs/
(not committed).
"""
import argparse
import contextlib
import datetime
import json
import random
import statistics
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "ingame"))
sys.path.insert(0, str(HERE))
sys.stdout.reconfigure(encoding="utf-8")

import attempt as AT  # noqa: E402
import es  # noqa: E402

LOGS = HERE / "logs"
FIXED = ("feintMinS", "feintMaxS", "loadMinS", "loadMaxS", "catchMaxS")  # safety nets, not tuned


def tunable(c):
    return [name for name in AT.dial_specs(c) if name not in FIXED]


def to_unit(c, names, values):
    specs = AT.dial_specs(c)
    return [(values[n] - specs[n][0]) / (specs[n][1] - specs[n][0]) for n in names]


def from_unit(c, names, x):
    specs = AT.dial_specs(c)
    return {n: round(specs[n][0] + v * (specs[n][1] - specs[n][0]), 3) for n, v in zip(names, x)}


def fitness(scores):
    """Mean score; a run that misses already scores below 1, so misses pull the mean down."""
    return statistics.fmean(scores)


def shortlist(candidates, generations, k=5):
    """The `k` fittest of the second half of the run (later generations first among equals). candidates:
    [{"gen", "fitness", "dials"}, ...]."""
    late = [c for c in candidates if c["gen"] >= generations // 2]
    return sorted(late, key=lambda c: (-c["fitness"], -c["gen"]))[:k]


def pick(results):
    """The most reliable of the shortlist: most passes on the selection starts, then the best mean score."""
    return max(results, key=lambda r: (r["passes"], r["meanScore"]))


def drive(drill_id, cfg, dials, starts, log, tag):
    """The dials from each start; returns (scores, verdicts), logging every attempt."""
    scores, verdicts = [], []
    for start in starts:
        graded, report = AT.attempt(drill_id, {**cfg, "dials": dials}, start)
        scores.append(AT.score(graded, report))
        verdicts.append(graded["tier"] or ("pass" if graded["passed"] else "miss"))
        log.write(json.dumps({**tag, "start": start, "dials": dials, "graded": graded, "report": report,
                              "score": scores[-1]}) + "\n")
        log.flush()
    return scores, verdicts


def tune(base, surface, generations, n_starts, n_select, seed, fast_mode=True, sigma=0.15):
    import fast  # noqa: PLC0415
    c = AT.card(AT.DRILLS[base])
    drill_id = AT.drill_id_for(base, surface)
    names = tunable(c)
    rng, select_rng = random.Random(seed), random.Random(seed + 1000)
    LOGS.mkdir(exist_ok=True)
    log_path = LOGS / f"{c['id']}-{surface}-{datetime.datetime.now():%Y%m%d-%H%M%S}.jsonl"
    with AT.session(drill_id):
        cfg = AT.config(c, drill_id, surface, tuned=False)
        start_dials = cfg["dials"]
        opt = es.SepCMA(to_unit(c, names, start_dials), sigma=sigma, seed=seed)
        t0, candidates = time.time(), []
        print(f"tuning {len(names)} dials of {c['id']} on {surface}: {opt.lam} candidates x {n_starts} starts "
              f"x {generations} generations = {opt.lam * n_starts * generations} attempts, then a selection on "
              f"{n_select} fresh starts", flush=True)
        with fast.fast() if fast_mode else contextlib.nullcontext(), log_path.open("a", encoding="utf-8") as log:
            for gen in range(generations):
                starts = [AT.varied_start(rng) for _ in range(n_starts)]
                xs = opt.ask()
                fits = []
                for k, x in enumerate(xs):
                    dials = {**start_dials, **from_unit(c, names, x)}
                    scores, verdicts = drive(drill_id, cfg, dials, starts, log, {"gen": gen, "k": k})
                    fits.append(fitness(scores))
                    candidates.append({"gen": gen, "k": k, "fitness": fits[-1], "dials": dials})
                    print(f"  gen {gen + 1} cand {k + 1}/{len(xs)}: fitness {fits[-1]:5.2f} {' '.join(verdicts)}",
                          flush=True)
                opt.tell(xs, [-f for f in fits])
                log.write(json.dumps({"gen": gen, "mean": {**start_dials, **from_unit(c, names, opt.m)}}) + "\n")
                print(f"gen {gen + 1}/{generations}: best {max(fits):.2f} mean {statistics.fmean(fits):.2f} | "
                      f"step {statistics.fmean(opt.spread()):.3f} | {len(candidates) * n_starts} attempts, "
                      f"{(time.time() - t0) / 60:.1f} min", flush=True)

            pool = shortlist(candidates, generations)
            pool.append({"gen": generations, "k": "mean", "fitness": None,
                         "dials": {**start_dials, **from_unit(c, names, opt.m)}})
            starts = [AT.varied_start(select_rng) for _ in range(n_select)]
            results = []
            for cand in pool:
                scores, verdicts = drive(drill_id, cfg, cand["dials"], starts, log,
                                         {"select": True, "gen": cand["gen"], "k": cand["k"]})
                passes = sum(v != "miss" for v in verdicts)
                results.append({**cand, "passes": passes, "meanScore": round(statistics.fmean(scores), 3),
                                "verdicts": verdicts})
                print(f"select gen {cand['gen'] + 1 if cand['k'] != 'mean' else 'final'} cand {cand['k']}: "
                      f"{passes}/{n_select} passed, mean score {statistics.fmean(scores):.2f}", flush=True)
        best = pick(results)
        write_best(c, surface, best, n_select, len(candidates) * n_starts + len(pool) * n_select)
        print(f"best: {best['passes']}/{n_select} on the selection starts -> {AT.tuned_path(c, surface)}")
        print(f"log: {log_path}")
        return best


def write_best(c, surface, best, n_select, evals):
    AT.DIALS.mkdir(exist_ok=True)
    names = tunable(c)
    AT.tuned_path(c, surface).write_text(json.dumps({
        "card": c["id"], "surface": surface, "date": f"{datetime.date.today()}", "attempts": evals,
        "from": "the optimiser's final mean" if best["k"] == "mean" else f"generation {best['gen'] + 1}, candidate "
                                                                          f"{best['k'] + 1}",
        "selection": {"passes": best["passes"], "starts": n_select, "meanScore": best["meanScore"],
                      "verdicts": best["verdicts"]},
        "dials": {n: best["dials"][n] for n in names},
    }, indent=2) + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("drill", choices=sorted(AT.DRILLS))
    ap.add_argument("--surface", default="gravel", choices=AT.SURFACES)
    ap.add_argument("--generations", type=int, default=12)
    ap.add_argument("--starts", type=int, default=3, help="varied starts per candidate")
    ap.add_argument("--select", type=int, default=10, help="fresh starts for choosing the winner")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--normal", action="store_true", help="normal speed instead of fast mode")
    args = ap.parse_args()
    tune(args.drill, args.surface, args.generations, args.starts, args.select, args.seed, not args.normal)


if __name__ == "__main__":
    main()

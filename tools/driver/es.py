"""A small CMA-ES (the separable, diagonal variant: Ros and Hansen, 2008) for tuning a technique card's dials
(docs/DRIVER.md, stage 1). Standard library only, like the rest of tools/.

It minimises: ask() gives a generation of candidates in [0, 1]^n (each dial scaled to its card range), tell() takes
their costs. The diagonal variant learns a step size per dial but not their correlations, which suits a dozen dials and
a few hundred noisy evaluations.
"""
import math
import random


class SepCMA:
    def __init__(self, x0, sigma=0.15, popsize=None, seed=None, lower=0.0, upper=1.0):
        self.n = n = len(x0)
        self.m = list(x0)
        self.sigma = sigma
        self.lower, self.upper = lower, upper
        self.rng = random.Random(seed)
        self.lam = popsize or 4 + int(3 * math.log(n))
        self.mu = self.lam // 2
        w = [math.log(self.mu + 0.5) - math.log(i + 1) for i in range(self.mu)]
        s = sum(w)
        self.w = [x / s for x in w]
        self.mueff = 1 / sum(x * x for x in self.w)
        mueff = self.mueff
        self.cs = (mueff + 2) / (n + mueff + 5)
        self.ds = 1 + 2 * max(0.0, math.sqrt((mueff - 1) / (n + 1)) - 1) + self.cs
        self.cc = (4 + mueff / n) / (n + 4 + 2 * mueff / n)
        c1 = 2 / ((n + 1.3) ** 2 + mueff)
        cmu = min(1 - c1, 2 * (mueff - 2 + 1 / mueff) / ((n + 2) ** 2 + mueff))
        scale = (n + 2) / 3  # the separable variant can learn faster
        self.c1 = min(1.0, c1 * scale)
        self.cmu = min(1.0 - self.c1, cmu * scale)
        self.chi = math.sqrt(n) * (1 - 1 / (4 * n) + 1 / (21 * n * n))
        self.c = [1.0] * n
        self.ps = [0.0] * n
        self.pc = [0.0] * n
        self.gen = 0
        self._ys = None

    def ask(self):
        """A generation of candidates, each clipped to [lower, upper]."""
        xs, ys = [], []
        for _ in range(self.lam):
            x = []
            for i in range(self.n):
                xi = self.m[i] + self.sigma * math.sqrt(self.c[i]) * self.rng.gauss(0, 1)
                x.append(min(self.upper, max(self.lower, xi)))
            xs.append(x)
            ys.append([(x[i] - self.m[i]) / self.sigma for i in range(self.n)])  # the step actually taken
        self._ys = ys
        return xs

    def tell(self, xs, costs):
        """Update from the costs of the candidates ask() gave (lower is better)."""
        order = sorted(range(len(xs)), key=lambda k: costs[k])[:self.mu]
        ys = [self._ys[k] for k in order]
        n = self.n
        yw = [sum(self.w[j] * ys[j][i] for j in range(self.mu)) for i in range(n)]
        self.m = [min(self.upper, max(self.lower, self.m[i] + self.sigma * yw[i])) for i in range(n)]
        a = math.sqrt(self.cs * (2 - self.cs) * self.mueff)
        self.ps = [(1 - self.cs) * self.ps[i] + a * yw[i] / math.sqrt(self.c[i]) for i in range(n)]
        norm = math.sqrt(sum(p * p for p in self.ps))
        self.gen += 1
        hsig = norm / math.sqrt(1 - (1 - self.cs) ** (2 * self.gen)) / self.chi < 1.4 + 2 / (n + 1)
        b = math.sqrt(self.cc * (2 - self.cc) * self.mueff)
        self.pc = [(1 - self.cc) * self.pc[i] + (b * yw[i] if hsig else 0.0) for i in range(n)]
        for i in range(n):
            rank_mu = sum(self.w[j] * ys[j][i] ** 2 for j in range(self.mu))
            rank_one = self.pc[i] ** 2 + (0.0 if hsig else self.cc * (2 - self.cc) * self.c[i])
            self.c[i] = (1 - self.c1 - self.cmu) * self.c[i] + self.c1 * rank_one + self.cmu * rank_mu
        self.sigma *= math.exp((self.cs / self.ds) * (norm / self.chi - 1))
        self.sigma = min(self.sigma, 0.5 * (self.upper - self.lower))

    def spread(self):
        """The current step size per dial, in the [0, 1] scale."""
        return [self.sigma * math.sqrt(c) for c in self.c]

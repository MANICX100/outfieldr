![](res/outfieldr-title.png)

# A [TLDR](https://github.com/tldr-pages/tldr) client in Zig.

![](res/example-ip.png)

# Usage

To view the TLDR page for `chmod`:
```
tldr chmod
```

Works with multiple-word pages as well, for example:
```
tldr git rebase
```

Fetch the most recent pages and update your local cache (you'll need to do this before using it for the first time):
```
tldr --fetch
```

To specify language (in this case, español):
```
tldr --lang es bash
```

# Building

You'll need [Zig](https://ziglang.org/) and
[Gyro](https://github.com/mattnite/gyro). You'll likely need a version
of Zig from master, as this is what it was developed with and what
it's dependencies require.

First, you need to fetch the packages used by this repo:
```
gyro fetch
```

Then build, adding whatever build flags you may want:
```
zig build
```

# Performance

It runs ~20-30 times faster than
[Tealdeer](https://github.com/dbrgn/tealdeer), which is written in
Rust and claims to be faster than the rest. For this, Tealdeer was
built with `--release`, and Outfieldr was built with `-Drelease-fast`.
It's worth noting that building with `-Drelease-safe` will give very
similar results, only adding 0.1ms extra here or there.

It was bench-marked with hyperfine, nothing super scientific.
Especially since Outfieldr is sitting at the lower bound of what
hyperfine is able to measure. A comparision of viewing the `ip` page
is [here](bench/hyperfine-outfieldr-tealdeer-ip).

# TODO

- [X] Pretty-print tldr pages

- [X] Update the local cache by fetching/extracting a tarball from the tldr repo

- [X] Make language overridable

- [X] Make OS overridable

- [ ] Handle terminals that don't like color

- [ ] List all available pages with small description

- [ ] List all available languages

- [ ] Improve help page

- [ ] Maybe add a config file for whatever

# Why the name?

I did a regex on a dictionary to find words that contained the letters
't', 'l', 'd', and 'r' in that order. This was the word I liked the
most. Just be thankful it wasn't named _kettledrum_.

# P.S.

This is my first Zig project. I wrote this to primarily to familiarize
myself with the language. If anybody wants to give feedback on my
code, positive or negative, I'd much appreciate it. Feel free to open
an issue, PR, or just message me wherever.

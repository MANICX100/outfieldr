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

Fetch the most recent pages and update your local cache (you'll need
to do this before using it for the first time):
```
tldr --fetch
```

To specify language (in this case, español):
```
tldr --lang es bash
```

You can specify the platform too, it defaults to the platform the
source was built for.
```
tldr --os osx caffeinate
```

You can list all pages, as well as supported languages and operating
systems:
```
tldr --list-pages
tldr --list-langs
tldr --list-os
```

Specifying your language/os alongside `list-pages` works as expected.
```
tldr --lang fr --os linux --list-pages
```

For more, try:
```
tldr --help
```

# Building

You'll need [`zig-0.8.0-dev`](https://ziglang.org/download/) and Git.

First, you need to init and update the submoduled dependencies:
```
git submodule init
git submodule update
```

Then, you can build the project. To build a release-safe binary, run:
```
zig build -Drelease-safe
```

I recommend you build with `-Drelease-safe`. The performance penalty
for runtime safety is quite minimal. If you _gotta go fast_ and want
to disable all runtime safety checks for the most speed possible,
build with `-Drelease-fast` instead. But again, this is not
recommended.

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

- [X] Improve help page

- [X] List all available languages

- [X] List all supported operating systems

- [X] List all available pages with small description

- [ ] Handle terminals that don't like color

# Why the name?

I did a regex on a dictionary to find words that contained the letters
't', 'l', 'd', and 'r' in that order. This was the word I liked the
most. Just be thankful it wasn't named _kettledrum_.

# P.S.

This is my first Zig project. I wrote this to primarily to familiarize
myself with the language. If anybody wants to give feedback on my
code, positive or negative, I'd much appreciate it. Feel free to open
an issue, PR, or just message me wherever.

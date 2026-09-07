# Contributing

This project is built by the community and the team behind it, and we would
love your suggestions for improvement. If something is missing, unclear, or
just plain wrong, please let us know: open an issue for a question or a
gap, and a pull request for anything you have already worked out.

Two things worth reading first, so a report doesn't retread known ground:

- `README.md` and `tools/android/RUNBOOK.md` both say, more than once, that
  this port has not yet been run on Android hardware. A report that only
  reproduces "the docs describe something no real device has confirmed" is
  already known.
- Jolt itself, and the libraries this project sits on (raylib-jlt,
  jolt-lang/nrepl, the pinned raylib revision), are still evolving. Check
  the version pins in `deps.edn` against what you actually have installed
  before filing a mismatch as a bug here.

## Etiquette

Adapted from the Clojure community's own
[etiquette guide](https://clojure.org/community/etiquette), since it says
what we would want to say ourselves and says it well.

Issues, pull requests and discussion here are for people who make things.
Most messages should have one of these forms:

- I made something. Here is my contribution.
- I am trying to use this and having trouble, please help.
- I can help you with that.
- I am trying to build something on top of this and having trouble, please
  help.
- I can help you build something.

They are not the place for opinion pieces or diatribes, and not the place
for advocacy about what "ought" to be built. If you think something ought
to exist, the fastest way to find out is to build it and send a pull
request. Otherwise, respect that other people get to choose what they do
with their time.

Disagreements about how something has been, or will be, done should take
the form of technical arguments. A technical argument that gets, and
gives, respect:

- Keeps it short.
- Sticks to the facts.
- Uses logic.
- Leaves people out of it.
- Avoids rhetorical devices: superfluous or opinion-laden adjectives,
  claims to speak for the community or that everyone agrees with you,
  threats of what will happen unless things go your way, any flavour of
  "the sky is falling."

If you are not the one doing the work, restrict your input to short
technical arguments supporting your position. If someone has already made
your point, a "+1" is enough, and keeping posts short is worth doing on
its own.

Ignoring these guidelines costs the time of the people who make things,
which is worth caring about if you intend to be one of them.

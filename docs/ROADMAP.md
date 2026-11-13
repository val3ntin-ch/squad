# Roadmap

## Later: one container per seat (decided by V!, 13 Nov 2026)

**When:** once a second, more powerful machine is available.

**What:** run each seat (or at least each dev and the tester) in its own container, with its own
CPU and memory share, instead of all seats on one Mac behind one heavy-run lock.

**Why:** the top systems isolate each agent and drop shared locks.
- Cursor: "Twenty agents would slow down to the effective throughput of two or three, with most time
  spent waiting" (https://cursor.com/blog/scaling-agents); workers "work on their own copy of the
  repo" (https://cursor.com/blog/self-driving-codebases).
- Anthropic's C compiler: "for each agent, a Docker container is spun up with the repo mounted to
  `/upstream`" (https://www.anthropic.com/engineering/building-c-compiler).
- Claude Code on the web, Cursor cloud agents, Devin and OpenHands each run an agent in its own VM
  or sandbox (sources in docs/research/2026-11-13-software-factories.md, row 3).

**Until then:** `squad heavy` is the build slot on the one machine: one heavy run at a time, an
owner, a time limit, a snapshot per dev run, a process group per run, and a sample mode for devs.

**To decide then:** container runtime (Docker, Podman, OrbStack), how herdr panes attach to a
container, shared caches (package store, build cache), and whether the heavy lock stays for a
shared resource such as a browser farm.

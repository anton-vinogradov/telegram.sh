# telegram.sh

Send messages, files, images and videos to Telegram from the command line — a
single, dependency-light `bash` script that talks to the Telegram Bot API.

Handy for server notifications: cronjob results, backup status, monitoring
alerts, or grabbing a small file off a box when SCP is inconvenient.

> **Lineage & license.** This is a maintained continuation of
> [fabianonline/telegram.sh](https://github.com/fabianonline/telegram.sh)
> (original author Fabian Schlenz; upstream inactive since 2022). It keeps the
> original **GPLv3** license and the full commit history. See
> [Changelog](#changelog) for what has been added since upstream v0.5.

## Features

- Send **text**, **files** (`-f`), **images** (`-i`) and **videos** (`-V`).
- **Markdown** / **HTML** formatting, monospace code blocks, message titles.
- Send to **multiple chats** in one call (`-c` repeated).
- **Per-recipient retries** (`-a`) that retry only *transient* failures and
  fail fast on permanent ones — see [Retries & exit code](#retries--exit-code).
- Read config/secrets from **files or environment variables**.
- Works behind a **proxy** (SOCKS/HTTP).
- Only needs `bash` and `curl` (`jq` optional).

## Requirements

- `bash` and `curl`.
- `jq` is **optional**. It makes `-l` (listing chats) nicer and lets the retry
  logic read Telegram error codes precisely; without it the script falls back
  to plain text parsing and still works.

## Installation

```bash
# 1. Grab the script and put it on your PATH.
curl -o /usr/local/bin/telegram https://raw.githubusercontent.com/anton-vinogradov/telegram.sh/master/telegram
chmod +x /usr/local/bin/telegram
```

Or track the repository so you can update with `git pull`:

```bash
git clone https://github.com/anton-vinogradov/telegram.sh.git
ln -s "$PWD/telegram.sh/telegram" /usr/local/bin/telegram
```

Then create a bot and find your chat id:

1. Talk to [`@BotFather`](https://t.me/botfather), run `/newbot`, and keep the
   **token** it gives you.
2. Send your new bot any message from your Telegram client.
3. Discover your **chat id**: `telegram -t <TOKEN> -l`. With `jq` installed the
   chats are listed nicely; the number in front is your chat id.
4. Send your first message: `telegram -t <TOKEN> -c <CHAT_ID> "Hello there."`

## Quick start

```bash
telegram -t 123456:AbcDefGhi-JklMnoPrw -c 12345 "Hello, World."
```

Once your token and chat id live in a config file or environment (see
[Configuration](#configuration)), you can simply run:

```bash
telegram "Hello, World."
```

## Usage

```
telegram [options] [message]
```

`message` may be `-`, in which case it is read from **stdin**.

| Option | Description |
|--------|-------------|
| `-t <TOKEN>` | Bot token to use (see [Configuration](#configuration)). |
| `-c <CHAT_ID>` | Recipient chat. **Repeatable** — send to several chats at once. |
| `-e <CHAT:MSGID>` | **Edit** an existing message instead of sending. Repeatable; replaces `-c`. With `-V`/`-i`/`-f` the message *becomes* that media (`editMessageMedia` — this also turns a plain text message into a media message); with text only, the text is replaced (`editMessageText`). |
| `-I` | Print `msgid <chat> <message_id>` for every delivered message, so you can `-e` it later. |
| `-q <DIR>` | **Queue on failure** (store-and-forward): recipients that still fail after all retries are written to `DIR` as queue files. See [Offline queue](#offline-queue). |
| `-d <DIR>` | **Drain** a queue directory: replay every queued delivery (oldest first, under a lock). |
| `-x <SECONDS>` | With `-d`: entries older than this expire — the message argument is delivered as an expiry notice instead. |
| `-a <N>` | Attempts per recipient (**retries**). Recipients are independent. See [Retries](#retries--exit-code). |
| `-p` | Deliver to all recipients **in parallel** (independently) instead of sequentially. |
| `-f <FILE>` | Send a file. |
| `-i <FILE>` | Send a file as an image (must be a real image). |
| `-V <FILE>` | Send a file as a video. |
| `-M` | Enable **Markdown** parsing. |
| `-H` | Enable **HTML** parsing. |
| `-C` | Send text as monospace code — handy when piping command output. |
| `-r` | Like `-C`, but a first line starting with `+ ` is specially formatted. |
| `-T <TITLE>` | Set a title (bold when `-M`/`-H` is used). |
| `-D` | Disable web-page preview (text messages only). |
| `-N` | Silent notification (no sound). |
| `-l` | List known chat ids. |
| `-m` | Print the last received message: `<Message ID> <Sender ID> <Chat ID> <Text>`. |
| `-R` | Receive a file that was sent to the bot. |

**Debugging options**

| Option | Description |
|--------|-------------|
| `-v` | Verbose output (the bot token is masked). |
| `-j` | Pretend `jq` is not installed. |
| `-n` | Dry-run — print what would be sent, don't send. |

## Retries & exit code

`-a <N>` retries delivery to **each recipient independently** up to `N` times.
It is deliberately conservative about *what* it retries:

- **Retried (transient):** curl/network errors, HTTP **5xx**, and **429** rate
  limits. On `429` the `retry_after` value from Telegram is honored.
- **Not retried (permanent):** `400`, `401`, `403`, `404`, … — these won't
  succeed on a retry (bad token, unknown chat, bot blocked), so they fail fast.

Recipients are independent: a failure to one chat does not stop delivery to the
others. The delay between attempts is `RETRY_DELAY` seconds (default `2`,
overridable in a config file).

**Exit code:** `0` if every recipient was delivered, non-zero if any recipient
ultimately failed — convenient for scripting and monitoring.

```bash
# Try each recipient up to 10 times, retrying only transient failures.
telegram -c 111 -c 222 -a 10 -V event.mp4
```

## Offline queue

With `-q <dir>` a delivery that still fails after all retries is not lost: each
failed recipient becomes a small queue file capturing the exact send (target,
media file, text, parse mode — and the bot token, so **keep the directory
private**, e.g. `chmod 700`). A later `telegram -d <dir>` run — typically from
cron or a systemd timer — replays the queue oldest-first under a lock:

- delivered or *permanently* rejected entries are removed;
- *transient* failures (network down, 5xx, 429) stay for the next run;
- with `-x <seconds>`, entries older than that expire: the message argument is
  delivered instead as a best-effort notice (as an **edit** for
  `<chat>:<message_id>` targets, as a plain message otherwise), and the entry
  is dropped.

```bash
# Sender: queue anything that can't be delivered right now.
telegram -c 1234 -a 3 -q /var/spool/telegram-queue -V clip.mp4

# Cron / systemd timer, every couple of minutes:
telegram -d /var/spool/telegram-queue -x 21600 "❌ delivery failed"
```

Combined with `-I`/`-e` this gives full store-and-forward for the
placeholder-then-morph pattern: the placeholder is already in the chat, and the
queued edit turns it into the real media as soon as the network returns.

## Configuration

`TOKEN` and `CHAT_ID` can be provided in six ways. **Later sources override
earlier ones**, so you can set global defaults and override per call:

1. `/etc/telegram.sh.conf`
2. `~/.telegram.sh`
3. `~/.telegram.sh.conf`
4. `./.telegram.sh.conf` (next to the script)
5. Environment variables `TELEGRAM_TOKEN` and `TELEGRAM_CHAT`
6. Command-line options `-t` and `-c`

A config file is plain shell:

```bash
TELEGRAM_TOKEN="123456:AbcDefGhi-JlkMno"
TELEGRAM_CHAT="12345678"
```

Multiple chats can be set as a bash array:

```bash
TELEGRAM_TOKEN="123456:AbcDefGhi-JlkMno"
CHATS=(12345678 23456789 34567)
```

> ⚠️ Keep your bot token secret. Config files with a token should not be
> world-readable. (`-v` and dry-run output mask the token since 0.10.)

### Proxy

Simplest — point curl at a proxy via the environment:

```bash
HTTPS_PROXY="socks5://127.0.0.1:1234" telegram "Hello, World."
```

For a permanent, host-local setup you can override `CURL_OPTIONS` in a config
file. The default is `-s --connect-timeout 10 --max-time 300`; overriding
replaces it entirely, so keep the timeouts you want:

```bash
# /etc/telegram.sh.conf
CURL_OPTIONS="-s -x socks5://127.0.0.1:1234 --connect-timeout 10 --max-time 60"
```

See the curl documentation for the supported proxy protocols.

## Examples

Every option, grouped by task. `TOKEN`/`CHAT_ID` are assumed to come from a
config file or the environment (see [Configuration](#configuration)) unless
`-t`/`-c` are shown explicitly.

### Sending text

```bash
# Explicit token and chat id (-t, -c) - override config and environment.
telegram -t 123456:AbcDefGhi-JklMnoPrw -c 12345 "Hello, World."

# Several recipients at once - repeat -c.
telegram -c 1234 -c 6789 "Hello, Planets."

# Multi-line message.
telegram "Hello,"$'\n'"World."

# Read the message from stdin ('-' as the message).
echo "Hello from a pipe." | telegram -

# Silent delivery (-N) - the client gets the message without a sound.
telegram -N "3am cron finished, don't wake anyone."
```

### Formatting

```bash
# Markdown (-M) and HTML (-H) parsing.
telegram -M "To *boldly* go, where _no man_ has gone before."
telegram -H "To <b>boldly</b> go, where <i>no man</i> has gone before."

# Title above the message (-T; printed bold with -M or -H).
telegram -M -T "Backup report" "Everything is fine."

# Send piped command output as monospace code (-C).
df -h | telegram -C -

# Cron mode (-r): like -C, but exits silently unless the input contains
# a line starting with '+ ' (e.g. 'sh -x' traces) - keeps quiet crons quiet.
make deploy 2>&1 | telegram -r -

# Don't unfurl links into previews (-D; text messages only).
telegram -D "Docs: https://example.com/very/loud/page"
```

### Files, images, video

```bash
# Document (-f, max 50MB) with a caption.
telegram -f results.txt "Here are the results."

# Photo (-i, max 10MB) - caption optional.
telegram -i solar_system.png "The neighbourhood."

# Video (-V, max 50MB). Streams inline; width/height/duration are probed
# with ffprobe when available, so the preview and aspect ratio are right.
telegram -V clip.mp4 "Look what the cat did."
```

### Retries and parallel delivery

```bash
# Up to 5 attempts per recipient (-a). Only transient failures are retried
# (network errors, HTTP 5xx, 429 - retry_after is honored); permanent ones
# (bad token, blocked bot, ...) fail immediately without retrying.
telegram -a 5 "Important."

# Deliver to all recipients in parallel and independently (-p):
# one broken chat doesn't delay or block the others.
telegram -c 1234 -c 6789 -a 5 -p -V clip.mp4 "For both of you."

# Exit code is 0 only if EVERY recipient got the message; failed chats are
# listed on stderr as "Failed to deliver to: <ids>".
```

### Editing messages (`-I` + `-e`): one message that upgrades itself

How it works, in one breath: `-I` makes every successful send print
`msgid <chat> <message_id>` on stdout. Save those pairs. Later, pass them back
as `-e <chat>:<message_id>` *instead of* `-c <chat>` — the bot then **edits**
that message rather than sending a new one: with a message argument the text
is replaced, with `-V`/`-i`/`-f` the message *becomes* that media (a plain
text message really does turn into a photo or video in place). Edits are
silent — subscribers get exactly one notification, from the original send.

Real wiring — one Telegram message per camera event that upgrades itself
(instant text → alarm snapshot a second later → full video at event end):

```bash
#!/bin/bash
CHATS=(-c 1234 -c 6789)

# Phase 1 - the instant something happens: cheap text, delivered in ~0.2s.
# -p delivers to all chats in parallel, -I prints one "msgid ..." line each.
out=$(telegram "${CHATS[@]}" -p -I -a 2 "🎥 $(date +%H:%M:%S)")

# Turn the msgid lines into "-e chat:id" targets for the next phases.
targets=()
while read -r _ chat id; do targets+=(-e "$chat:$id"); done < <(grep ^msgid <<< "$out")

# Phase 2 - a snapshot exists: the text message BECOMES a photo.
# Best-effort (-a 1): if it fails, the video will replace it anyway.
telegram "${targets[@]}" -p -a 1 -i alarm.jpg "$(date +%H:%M:%S)"

# Phase 3 - the video is ready: the same message becomes the video.
telegram "${targets[@]}" -p -a 3 -V event.mp4
```

The chat shows a *single* message the whole time: it appears instantly as
text, sprouts a picture a second later, and finally plays as a video. The
notification sound fires once — for the text.

### Offline queue (`-q` + `-d`): guaranteed delivery

How it works, in one breath: with `-q <dir>`, every recipient that is still
undelivered after all `-a` retries is written into `<dir>` as one small file
describing the exact delivery (target, media file, text, token — so
`chmod 700` the directory). A separate `telegram -d <dir>` run — from cron or
a systemd timer — replays those files oldest-first: delivered and permanently
rejected entries are deleted, transient failures stay queued for the next
run. With `-x <seconds>` an entry eventually expires: the message argument is
delivered *instead of* the payload (as an **edit** if the target was
`chat:msgid`, as a plain message otherwise), and the entry is dropped.

Real wiring — sender plus a retry timer:

```bash
# Sender (camera event, backup job, ...): 3 attempts now, spool on failure.
telegram -c 1234 -c 6789 -p -a 3 -q /var/spool/tg-queue -V event.mp4
```

```bash
# /etc/cron.d/telegram-drain - retry every 2 minutes, give up after 6 hours.
*/2 * * * * root /usr/local/bin/telegram -d /var/spool/tg-queue -x 21600 "❌ delivery failed"
```

What actually happens when the network dies mid-day:

```
14:02  send fails after 3 attempts  -> queue file written, sender exits 1
14:04  drain: network still down    -> entry stays queued
14:06  drain: still down            -> entry stays queued
14:37  drain: network is back       -> video delivered, entry removed
```

The two recipes compose. Add `-q` to phase 3 of the camera script above: the
placeholder is already in the chat, so when the network returns the queued
*edit* turns it into the video — and if 6 hours pass first, the very same
message turns into "❌ delivery failed" instead. Either way the subscriber
sees the event and its outcome in one message, in the right chronological
position.

### Discovering chats, receiving

```bash
# Which chats can the bot see? (Message the bot first, then:)
telegram -l

# Print the last message sent to the bot.
telegram -m            # -> <Message ID> <Sender ID> <Chat ID> <Text>

# Download the last file sent to the bot into the current directory.
telegram -R
```

### Debugging

```bash
telegram -v "Verbose run."   # log every step (the token is masked)
telegram -n "Dry run."       # print the curl invocation, send nothing
telegram -j "No jq."         # pretend jq is absent (exercise fallbacks)
telegram -h                  # full usage
```

## Docker

```bash
docker build -t telegram:latest .
docker run --rm telegram -t <TOKEN> -c <CHAT_ID> "Hello from Docker."
```

## Changelog

### 0.12
- **Offline queue (store-and-forward):** `-q <dir>` writes every recipient that
  still fails after all retries into a queue directory; `-d <dir>` replays the
  queue (oldest first, locked) — delivered/permanent entries are removed,
  transient ones stay; `-x <seconds>` expires old entries by delivering the
  message argument as a notice (edit for `chat:msgid` targets) and dropping
  them. Queue files carry the bot token — keep the directory `chmod 700`.

### 0.11
- **Editing messages:** new `-e <chat>:<message_id>` mode (repeatable, replaces
  `-c`). With a file it runs `editMessageMedia` — including turning a plain
  *text* message into a video/photo/document; with text only it runs
  `editMessageText`. Retries (`-a`), parallelism (`-p`) and the transient/
  permanent error classification apply to edits exactly as to sends.
- **`-I`:** print `msgid <chat> <message_id>` for every delivered message, so
  callers can edit it later (placeholder-then-morph workflows).
- `ffprobe` metadata (width/height/duration) is embedded in the `InputMediaVideo`
  object on edits, same as on `sendVideo`.

### 0.10
- **Fixed precedence:** `-c`/`-t` on the command line now really override
  config files (a config defining `CHATS=(...)` used to win silently).
  The documented order — config files < environment < options — now holds.
- **Files with spaces** (and commas/semicolons) in their names now upload
  correctly: curl arguments are built as an array and file paths use curl's
  quoted-filename syntax.
- **Default network timeouts** (`--connect-timeout 10 --max-time 300`), so a
  dead proxy or hung connection can't block a cronjob forever. Overridable
  via `CURL_OPTIONS`.
- Usage errors (unknown option, missing argument) now exit with code `2`
  instead of printing help and exiting `0`.
- `429 retry_after` is honored even without `jq`.
- `sendPhoto` is checked against its real 10MB limit; captions longer than
  1024 characters produce a warning.
- `-l` lists groups and channels by title, skips non-message updates and
  dedupes chats (no more `null - null null (@null)`).
- The bot token is masked in `-v` and dry-run output.
- Docker image now has an `ENTRYPOINT` and ships `jq`.
- Real smoke-test suite (`test.sh`, 26 checks) + GitHub Actions CI
  (shellcheck + tests).

### 0.9
- `sendVideo` now sends `supports_streaming=true` and, when `ffprobe` is
  available, `width`/`height`/`duration` — for reliable inline playback and a
  correct preview/aspect ratio.
- `-D` now uses `link_preview_options` (the current Bot API field) instead of
  the removed `disable_web_page_preview`.

### 0.8
- New `-p` option: deliver to all recipients **in parallel** (independently)
  instead of sequentially, so a slow or unreachable recipient no longer holds
  up the others.

### 0.7
- Smarter `-a` retries: only **transient** failures (network/curl errors, HTTP
  5xx, 429) are retried, honoring the `429 retry_after` hint; permanent errors
  (4xx) now **fail fast** instead of exhausting all attempts.
- Fixed dry-run (`-n`) falsely reporting a failure when `jq` is unavailable.

### 0.6
- New `-a <N>` option: retry delivery to each recipient up to `N` times.
  Recipients are independent, and the exit code is non-zero if any recipient
  ultimately failed.

### 0.5
- New option `-V` to send a video file.
- Configuration can also be read from `./.telegram.sh.conf` next to the script.

### 0.4
- New option `-m` to output the last received message — useful for polling and
  reacting to commands.

## Credits

Original author **Fabian Schlenz** and upstream contributors: abadroot,
dbarthe, hugows, kgizdov, KOPACb, rerime, rusalex, sergiks.

## License

GPLv3 — see [LICENSE](LICENSE).

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
| `-a <N>` | Attempts per recipient (**retries**). Recipients are independent. See [Retries](#retries--exit-code). |
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
| `-v` | Verbose output. ⚠️ prints the token — do not use where output is logged. |
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
> world-readable, and avoid `-v` anywhere the output is captured to logs.

### Proxy

Simplest — point curl at a proxy via the environment:

```bash
HTTPS_PROXY="socks5://127.0.0.1:1234" telegram "Hello, World."
```

For a permanent, host-local setup you can override `CURL_OPTIONS` in a config
file (this also lets you add a timeout, etc.):

```bash
# /etc/telegram.sh.conf
CURL_OPTIONS="-s -x socks5://127.0.0.1:1234 --max-time 60"
```

See the curl documentation for the supported proxy protocols.

## Examples

```bash
# Message from token + chat id.
telegram -t 123456:AbcDefGhi-JklMnoPrw -c 12345 "Hello, World."

# Multi-line message.
telegram "Hello,"$'\n'"World."
echo -e "Hello\nWorld." | telegram -

# Send to multiple chats at once.
telegram -c 1234 -c 6789 "Hello, Planets."

# Pipe command output (sent as monospace code).
ls -l | telegram -

# Markdown (HTML is available via -H).
telegram -M "To *boldly* go, where _no man_ has gone before."

# Send a file, an image, or a video.
telegram -f results.txt "Here are the results."
telegram -i solar_system.png
telegram -V clip.mp4
```

## Docker

```bash
docker build -t telegram:latest .
docker run -it --rm telegram
```

## Changelog

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

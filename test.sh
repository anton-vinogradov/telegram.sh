#!/bin/bash
# Smoke tests for telegram.sh. No network access: everything runs in -n
# (dry-run) mode against a copy of the script in a temp directory, with
# HOME pointed there so user config files can't interfere.
set -u

cd "$(dirname "$0")" || exit 1
SCRIPT_SRC="$PWD/telegram"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$SCRIPT_SRC" "$TMP/telegram"
cd "$TMP" || exit 1

PASS=0
FAIL=0

# run <args...>  - run the script isolated from the caller's environment.
run() {
	env -u TELEGRAM_TOKEN -u TELEGRAM_CHAT HOME="$TMP" "$@"
}

# indent <text> - print text indented for failure details.
indent() {
	while IFS= read -r l; do printf '       %s\n' "$l"; done <<< "$1"
}

# t <name> <expected_exit> <expected_pattern> -- <cmd...>
# Pattern is a fixed string; prefix with '!' to assert absence; '-' skips.
t() {
	local name="$1" want_exit="$2" want="$3"
	shift 3
	[ "$1" = "--" ] && shift
	local out rc
	out=$(run "$@" 2>&1)
	rc=$?
	if [ "$rc" != "$want_exit" ]; then
		echo "FAIL: $name - exit $rc, expected $want_exit"
		indent "$out"
		FAIL=$((FAIL + 1))
		return
	fi
	if [ "$want" != "-" ]; then
		if [ "${want:0:1}" = "!" ]; then
			if grep -qF -- "${want:1}" <<< "$out"; then
				echo "FAIL: $name - output must NOT contain: ${want:1}"
				indent "$out"
				FAIL=$((FAIL + 1))
				return
			fi
		elif ! grep -qF -- "$want" <<< "$out"; then
			echo "FAIL: $name - output does not contain: $want"
			indent "$out"
			FAIL=$((FAIL + 1))
			return
		fi
	fi
	echo "ok:   $name"
	PASS=$((PASS + 1))
}

### Configuration precedence ##################################################
printf 'CHATS=(111 222)\n' > .telegram.sh.conf

t "config CHATS used when no -c given"      0 "chat_id=111" -- ./telegram -t T -n hi
t "CLI -c overrides config CHATS"           0 "chat_id=999" -- ./telegram -t T -c 999 -n hi
t "CLI -c: config chats are NOT used"       0 "!chat_id=111" -- ./telegram -t T -c 999 -n hi
t "env TELEGRAM_CHAT overrides config"      0 "chat_id=333" -- env TELEGRAM_CHAT=333 ./telegram -t T -n hi
t "CLI -c overrides env TELEGRAM_CHAT"      0 "chat_id=777" -- env TELEGRAM_CHAT=333 ./telegram -t T -c 777 -n hi

rm -f .telegram.sh.conf

### Files with special characters #############################################
: > "my file.txt"

t "file with spaces stays one curl arg"     0 'document=@\"my\ file.txt\"' -- ./telegram -t T -c 1 -n -f "my file.txt" cap
t "image and video flags accepted"          0 "sendVideo" -- ./telegram -t T -c 1 -n -V "my file.txt" cap

### Usage errors and exit codes ###############################################
t "invalid option exits 2"                  2 "Invalid option" -- ./telegram -Z
t "missing option argument exits 2"         2 "needs an argument" -- ./telegram -T
t "-h exits 0 and prints usage"             0 "Usage" -- ./telegram -h
t "no token exits 1"                        1 "No bot token" -- ./telegram -c 1 -n hi
t "no chats exits 1"                        1 "No chat(s)" -- ./telegram -t T -n hi
t "no message exits 1"                      1 "Neither text" -- ./telegram -t T -c 1 -n
t "-f and -i conflict"                      1 "at the same time" -- ./telegram -t T -c 1 -n -f "my file.txt" -i "my file.txt"
t "-C and -r conflict"                      1 "not both" -- ./telegram -t T -c 1 -n -C -r hi
t "nonexistent file exits 1"                1 "does not exist" -- ./telegram -t T -c 1 -n -f no-such-file.bin

### Message formatting ########################################################
t "-C wraps text in code fences"            0 '```' -- ./telegram -t T -c 1 -n -C hi
t "-M sets parse_mode"                      0 "parse_mode=Markdown" -- ./telegram -t T -c 1 -n -M hi
t "-D sets link_preview_options"            0 "is_disabled" -- ./telegram -t T -c 1 -n -D hi
t "-N sets disable_notification"            0 "disable_notification=true" -- ./telegram -t T -c 1 -n -N hi
t "-T prepends bold title with -M"          0 '*Title*' -- ./telegram -t T -c 1 -n -M -T Title hi
t "stdin message via -"                     0 "Text: from stdin" -- bash -c 'echo "from stdin" | ./telegram -t T -c 1 -n -'

### Editing messages (-e) and message ids (-I) ################################
t "-e with -V uses editMessageMedia"        0 "editMessageMedia" -- ./telegram -t T -n -e 123:45 -V "my file.txt" cap
t "-e media JSON is InputMediaVideo"        0 'media=\{\"type\":\"video\"' -- ./telegram -t T -n -e 123:45 -V "my file.txt" cap
t "-e passes message_id"                    0 "message_id=45" -- ./telegram -t T -n -e 123:45 -V "my file.txt" cap
t "-e splits chat_id from target"           0 "chat_id=123" -- ./telegram -t T -n -e 123:45 -V "my file.txt" cap
t "-e negative chat id accepted"            0 "chat_id=-100987" -- ./telegram -t T -n -e -100987:45 -V "my file.txt" cap
# token "SECRET" (not "T"): mask_token would mangle the literal "editMessageText"
t "-e text only uses editMessageText"       0 "editMessageText" -- ./telegram -t SECRET -n -e 123:45 "new text"
t "-e works without -c"                     0 "!No chat(s)" -- ./telegram -t T -n -e 123:45 hi
t "-e bad target rejected"                  1 "Invalid -e target" -- ./telegram -t T -n -e nonsense -V "my file.txt" cap
t "-I flag accepted"                        0 - -- ./telegram -t T -c 1 -n -I hi

### Size limits ###############################################################
dd if=/dev/zero of=big.bin bs=1024 count=11264 2>/dev/null

t "11MB photo rejected (10MB limit)"        1 "10MB" -- ./telegram -t T -c 1 -n -i big.bin
t "11MB document accepted (50MB limit)"     0 - -- ./telegram -t T -c 1 -n -f big.bin cap

rm -f big.bin

### Token hygiene #############################################################
t "dry-run masks the token"                 0 "!123456:FULLSECRETTOKEN" -- ./telegram -t "123456:FULLSECRETTOKEN" -c 1 -n hi
t "verbose masks the token"                 0 "!123456:FULLSECRETTOKEN" -- ./telegram -t "123456:FULLSECRETTOKEN" -c 1 -n -v hi

### Summary ###################################################################
echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]

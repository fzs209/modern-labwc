#!/usr/bin/env python3

import sys
import time
import json
import argparse
import os
import re
import subprocess
import select

# Configuration
config_dir = os.path.dirname(os.path.realpath(__file__))
state_file = os.path.join(config_dir, "state.json")
tmp_state_file = os.path.join(config_dir, "state.json.tmp")
fifo_path = os.path.join(config_dir, "timer.fifo")
sound_file = os.path.join(config_dir, "beep.wav")

# Notification IDs
notify_id_sw = "string:x-canonical-private-synchronous:stopwatch"
notify_id_cd = "string:x-canonical-private-synchronous:countdown"
notify_id_pom = "string:x-canonical-private-synchronous:pomodoro"
timeout_normal = "3000"
timeout_crit = "4000"

# Icons
sw_icon = "<big>\u2009</big>"
cd_icon = ""
break_icon = "<big>\u2009\u2009</big>"
pom_icon = "<big></big>"

#######################################
# State helpers                       #
#######################################


def get_default_state():
    return {
        "view": "stopwatch",
        "stopwatch": {"status": "stopped", "start_ts": 0, "accumulated": 0},
        "countdown": {
            "status": "stopped",
            "start_ts": 0,
            "total_duration": 0,
            "remaining": 0,
        },
        "pomodoro": {
            "status": "stopped",
            "start_ts": 0,
            "remaining": 0,
            "current_phase": "work",
            "work_duration": 1500,
            "break_duration": 300,
        },
    }


def load_state():
    if not os.path.exists(state_file):
        return get_default_state()
    try:
        with open(state_file, "r") as f:
            state = json.load(f)
            default = get_default_state()
            for key in default:
                if key not in state:
                    state[key] = default[key]
            return state
    except (json.JSONDecodeError, IOError):
        return get_default_state()


def save_state(state):
    """Atomic write via temporary file and rename."""
    try:
        os.makedirs(config_dir, exist_ok=True)
        with open(tmp_state_file, "w") as f:
            json.dump(state, f, indent=4)
        os.replace(tmp_state_file, state_file)
    except IOError:
        pass


#########################################
# Sound and Notification                #
#########################################


def play_sound(mode="single"):
    if not os.path.exists(sound_file):
        return
    aplay_cmd = f'aplay -q "{sound_file}"'
    if mode == "single":
        cmd = f"{aplay_cmd} &"
    elif mode == "double":
        cmd = f"{aplay_cmd} & sleep 0.3; {aplay_cmd}"
    elif mode == "alarm":
        cmd = (
            f"for i in {{1..5}}; do "
            f"{aplay_cmd} & sleep 0.2; "
            f"{aplay_cmd} & wait; "
            f"sleep 0.8; "
            f"done; wait"
        )
    try:
        subprocess.Popen(cmd, shell=True)
    except:
        pass


def send_notification(notif_id, title, body="", level="normal"):
    timeout = timeout_normal
    urgency = "normal"
    if level == "critical":
        timeout = timeout_crit
        urgency = "critical"
    try:
        cmd = ["notify-send", "-h", notif_id, "-t", timeout, "-u", urgency, title]
        if body:
            cmd.append(body)
        subprocess.Popen(cmd)
    except:
        pass


##############################################
# Time helpers                              #
##############################################


def parse_time(arg):
    if ":" in arg:
        parts = arg.split(":")
        try:
            parts = [int(p) for p in parts]
        except ValueError:
            return 0
        if len(parts) == 3:
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        if len(parts) == 2:
            return parts[0] * 60 + parts[1]
    match = re.match(r"(\d+)([a-zA-Z]+)", arg)
    if match:
        val = int(match.group(1))
        unit = match.group(2).lower()
        if "h" in unit:
            return val * 3600
        if "m" in unit:
            return val * 60
        if "s" in unit:
            return val
    if arg.isdigit():
        return int(arg)
    return 0


def get_time_parts(seconds):
    if seconds is None:
        seconds = 0
    sign = "-" if seconds < 0 else ""
    seconds = abs(seconds)
    total_seconds = int(seconds)
    m, s = divmod(total_seconds, 60)
    h, m = divmod(m, 60)
    cs = int((seconds - total_seconds) * 100)
    return sign, h, m, s, cs


def format_time(seconds, adaptive=False):
    sign, h, m, s, cs = get_time_parts(seconds)
    if adaptive:
        if h > 0:
            return f"{sign}{h:02d}:{m:02d}:{s:02d}"
        elif m > 0:
            return f"{sign}{m:02d}:{s:02d}:{cs:02d}"
        else:
            return f"{sign}{s:02d}:{cs:02d}"
    return f"{sign}{h:02d}:{m:02d}:{s:02d}:{cs:02d}"


def short_time(seconds):
    sign, h, m, s, _ = get_time_parts(seconds)
    if h > 0:
        return f"{sign}{h}:{m:02d}:{s:02d}"
    elif m > 0:
        return f"{sign}{m}:{s:02d}"
    else:
        return f"{sign}{s}"


def readable_time(seconds):
    _, h, m, s, _ = get_time_parts(seconds)
    parts = []
    if h:
        parts.append(f"{h}h")
    if m:
        parts.append(f"{m}m")
    if s or not parts:
        parts.append(f"{s}s")
    return " ".join(parts)


##########################################
# In‑memory command handlers             #
##########################################


def handle_stopwatch(state, action):
    sw = state["stopwatch"]
    now = time.time()
    changed = False
    notif_body = ""
    level = "normal"

    if action == "toggle-pause":
        action = "pause" if sw["status"] == "running" else "resume"
    if action == "start" and sw["accumulated"] > 0:
        action = "resume"

    if action in ("start", "resume"):
        if sw["status"] != "running":
            sw["status"] = "running"
            sw["start_ts"] = now
            if action == "start":
                sw["accumulated"] = 0
                notif_body = "Started"
            else:
                notif_body = "Resumed"
            if state.get("view") != "split":
                state["view"] = "stopwatch"
            changed = True
    elif action == "pause" and sw["status"] == "running":
        sw["status"] = "paused"
        elapsed = now - sw["start_ts"]
        sw["accumulated"] += elapsed
        notif_body = f"Paused at {readable_time(sw['accumulated'])}"
        changed = True
    elif action == "reset":
        sw["status"] = "stopped"
        sw["accumulated"] = 0
        notif_body = "Reset"
        level = "critical"
        changed = True

    if notif_body:
        play_sound("single")
        send_notification(notify_id_sw, "Stopwatch", notif_body, level=level)

    return changed


def handle_countdown(state, args_list):
    cd = state["countdown"]
    now = time.time()
    changed = False
    notif_body = ""
    level = "normal"
    arg = args_list[0] if args_list else "resume"

    if arg == "add" and len(args_list) > 1:
        sec = parse_time(args_list[1])
        cd["remaining"] = max(0, cd["remaining"] + sec)
        cd["total_duration"] += sec
        notif_body = f"Added {readable_time(sec)}"
        changed = True
    elif arg == "toggle-pause":
        if cd["status"] == "running":
            cd["status"] = "paused"
            cd["remaining"] -= now - cd["start_ts"]
            notif_body = f"Paused ({readable_time(cd['remaining'])} left)"
            changed = True
        else:
            if cd["remaining"] <= 0:
                cd["remaining"] = 1800
                cd["total_duration"] = 1800
            cd["status"] = "running"
            cd["start_ts"] = now
            notif_body = "Resumed"
            changed = True
    elif arg == "reset":
        cd["status"] = "stopped"
        cd["remaining"] = 0
        cd["total_duration"] = 0
        notif_body = "Reset"
        level = "critical"
        changed = True
    elif arg == "pause" and cd["status"] == "running":
        cd["status"] = "paused"
        cd["remaining"] -= now - cd["start_ts"]
        notif_body = f"Paused ({readable_time(cd['remaining'])} left)"
        changed = True
    elif arg == "start":
        if cd["remaining"] > 0:
            if cd["status"] != "running":
                cd["status"] = "running"
                cd["start_ts"] = now
                notif_body = f"Resumed ({readable_time(cd['remaining'])})"
                changed = True
        else:
            tgt = cd["total_duration"] if cd["total_duration"] > 0 else 1800
            cd["remaining"] = tgt
            cd["total_duration"] = tgt
            cd["status"] = "running"
            cd["start_ts"] = now
            notif_body = f"Started ({readable_time(tgt)})"
            changed = True
        if state.get("view") != "split":
            state["view"] = "countdown"
            changed = True
    elif arg == "resume":
        if cd["remaining"] > 0 and cd["status"] != "running":
            cd["status"] = "running"
            cd["start_ts"] = now
            notif_body = f"Resumed ({readable_time(cd['remaining'])})"
            changed = True
            if state.get("view") != "split":
                state["view"] = "countdown"
    else:
        sec = parse_time(arg)
        if sec > 0:
            cd["status"] = "running"
            cd["start_ts"] = now
            cd["remaining"] = sec
            cd["total_duration"] = sec
            notif_body = f"Started ({readable_time(sec)})"
            changed = True
            if state.get("view") != "split":
                state["view"] = "countdown"

    if notif_body:
        play_sound("single")
        send_notification(notify_id_cd, "Countdown", notif_body, level=level)

    return changed


def handle_pomodoro(state, args):
    pom = state["pomodoro"]
    now = time.time()
    changed = False
    notif_body = ""
    level = "normal"

    if not args:
        args = ["toggle-pause"]

    arg0 = args[0]
    if arg0 == "toggle-pause":
        if pom["status"] == "running":
            pom["status"] = "paused"
            pom["remaining"] -= now - pom["start_ts"]
            notif_body = f"Paused ({readable_time(pom['remaining'])} left)"
            changed = True
        else:
            if pom["remaining"] <= 0:
                pom["remaining"] = pom["work_duration"]
            pom["status"] = "running"
            pom["start_ts"] = now
            notif_body = f"Resumed {pom['current_phase'].upper()}"
            changed = True
    elif arg0 == "pause" and pom["status"] == "running":
        pom["status"] = "paused"
        pom["remaining"] -= now - pom["start_ts"]
        notif_body = f"Paused ({readable_time(pom['remaining'])} left)"
        changed = True
    elif arg0 == "resume" and pom["status"] != "running":
        if pom["remaining"] <= 0:
            pom["remaining"] = pom["work_duration"]
        pom["status"] = "running"
        pom["start_ts"] = now
        notif_body = f"Resumed {pom['current_phase'].upper()}"
        changed = True
    elif arg0 == "start":
        if pom["remaining"] > 0:
            if pom["status"] != "running":
                pom["status"] = "running"
                pom["start_ts"] = now
                notif_body = f"Resumed {pom['current_phase'].upper()}"
                changed = True
        else:
            pom["current_phase"] = "work"
            pom["remaining"] = pom["work_duration"]
            pom["status"] = "running"
            pom["start_ts"] = now
            notif_body = f"Started\nWork: {readable_time(pom['work_duration'])}, Break: {readable_time(pom['break_duration'])}"
            changed = True
        if state.get("view") != "split":
            state["view"] = "pomodoro"
            changed = True
    elif arg0 == "reset":
        pom["status"] = "stopped"
        pom["remaining"] = 0
        notif_body = "Reset"
        level = "critical"
        changed = True
    elif len(args) >= 2:
        w = parse_time(args[0])
        b = parse_time(args[1])
        pom.update(
            {
                "status": "running",
                "start_ts": now,
                "remaining": w,
                "work_duration": w,
                "break_duration": b,
                "current_phase": "work",
            }
        )
        notif_body = f"Started\nWork: {readable_time(w)}, Break: {readable_time(b)}"
        changed = True
        if state.get("view") != "split":
            state["view"] = "pomodoro"

    if notif_body:
        play_sound("single")
        send_notification(notify_id_pom, "Pomodoro", notif_body, level=level)

    return changed


def handle_view_toggle(state):
    modes = ["stopwatch", "countdown", "pomodoro", "split"]
    current = state.get("view", "stopwatch")
    idx = modes.index(current) if current in modes else 0
    state["view"] = modes[(idx + 1) % len(modes)]
    return True


def handle_split_toggle_pause(state):
    timers = {
        "stopwatch": state["stopwatch"],
        "countdown": state["countdown"],
        "pomodoro": state["pomodoro"],
    }

    def rank(status):
        if status == "running":
            return 1
        if status == "paused":
            return 2
        return 3

    timer_ranks = {name: rank(t["status"]) for name, t in timers.items()}
    highest = min(timer_ranks.values())

    changed = False
    for name, r in timer_ranks.items():
        if r != highest:
            continue
        action = "pause" if r == 1 else ("resume" if r == 2 else "start")
        if name == "stopwatch":
            changed = handle_stopwatch(state, action) or changed
        elif name == "countdown":
            changed = handle_countdown(state, [action]) or changed
        elif name == "pomodoro":
            changed = handle_pomodoro(state, [action]) or changed
    return changed


def handle_smart_action(state, action):
    view = state.get("view", "stopwatch")
    if view == "stopwatch":
        return handle_stopwatch(state, action)
    elif view == "countdown":
        return handle_countdown(state, [action])
    elif view == "pomodoro":
        return handle_pomodoro(state, [action])
    elif view == "split":
        if action == "toggle-pause":
            return handle_split_toggle_pause(state)
        else:
            c1 = handle_stopwatch(state, action)
            c2 = handle_countdown(state, [action])
            c3 = handle_pomodoro(state, [action])
            return c1 or c2 or c3
    return False


##########################################
# Output builder                         #
##########################################


def build_output(state, now):
    sw = state["stopwatch"]
    sw_sec = sw["accumulated"] + (
        now - sw["start_ts"] if sw["status"] == "running" else 0
    )

    cd = state["countdown"]
    cd_sec = cd["remaining"]
    if cd["status"] == "running":
        cd_sec = cd["remaining"] - (now - cd["start_ts"])
        if cd_sec < 0:
            cd_sec = 0

    pom = state["pomodoro"]
    pom_sec = pom["remaining"]
    if pom["status"] == "running":
        pom_sec = pom["remaining"] - (now - pom["start_ts"])
        if pom_sec < 0:
            pom_sec = 0

    curr_pom_icon = (
        break_icon
        if pom["current_phase"] == "break" and pom["status"] != "stopped"
        else pom_icon
    )
    view = state.get("view", "stopwatch")

    sw_disp = (
        f"{sw_icon} {format_time(sw_sec, True)}"
        if sw["status"] != "stopped"
        else sw_icon
    )
    cd_disp = (
        f"{cd_icon} Done!"
        if cd["status"] == "done"
        else (
            f"{cd_icon} {format_time(cd_sec, True)}"
            if cd["status"] != "stopped"
            else cd_icon
        )
    )
    pom_disp = (
        f"{curr_pom_icon} {format_time(pom_sec, True)}"
        if pom["status"] != "stopped"
        else pom_icon
    )

    if view == "stopwatch":
        final_text = sw_disp
        tooltip = f"Mode: Stopwatch\nStatus: {sw['status']}"
    elif view == "countdown":
        final_text = cd_disp
        tooltip = f"Mode: Countdown\nStatus: {cd['status']}"
        if cd["total_duration"] > 0:
            tooltip += f"\nTarget: {readable_time(cd['total_duration'])}"
    elif view == "pomodoro":
        final_text = pom_disp
        tooltip = f"Mode: Pomodoro\nStatus: {pom['status']}\nPhase: {pom['current_phase'].upper()}\nWork: {readable_time(pom['work_duration'])} | Break: {readable_time(pom['break_duration'])}"
    else:  # split view
        s_sw = (
            f"{sw_icon} {short_time(sw_sec)}" if sw["status"] != "stopped" else sw_icon
        )
        s_cd = (
            f"{cd_icon} {short_time(cd_sec)}"
            if cd["status"] not in ["stopped", "done"]
            else (f"{cd_icon} Done!" if cd["status"] == "done" else cd_icon)
        )
        s_pom = (
            f"{curr_pom_icon} {short_time(pom_sec)}"
            if pom["status"] != "stopped"
            else pom_icon
        )
        final_text = f"{s_sw} | {s_cd} | {s_pom}"
        tooltip = "Split View\nOrder: Stopwatch | Countdown | Pomodoro"

    is_running = any(t["status"] == "running" for t in (sw, cd, pom))
    is_paused = any(t["status"] == "paused" for t in (sw, cd, pom))
    global_status = "running" if is_running else "paused" if is_paused else "stopped"
    if cd["status"] == "done":
        global_status += " expired"

    class_list = [view] + global_status.split()
    if pom["status"] != "stopped":
        class_list += ["pomodoro", pom["current_phase"]]

    return json.dumps(
        {
            "text": final_text,
            "tooltip": tooltip,
            "class": class_list,
            "alt": view,
        }
    )


##########################################
# Monitor loop                           #
##########################################


def run_monitor():
    state = load_state()
    os.makedirs(config_dir, exist_ok=True)

    if not os.path.exists(fifo_path):
        os.mkfifo(fifo_path)
    fifo_fd = os.open(fifo_path, os.O_RDWR | os.O_NONBLOCK)

    # Immediately output the initial state so Waybar isn't blank.
    now = time.time()
    print(build_output(state, now), flush=True)

    buffer = ""

    while True:
        sw = state["stopwatch"]
        cd = state["countdown"]
        pom = state["pomodoro"]
        is_running = any(t["status"] == "running" for t in (sw, cd, pom))
        timeout = 0.1 if is_running else None
        rlist, _, _ = select.select([fifo_fd], [], [], timeout)

        state_changed = False

        # 1. Process all waiting FIFO commands
        if fifo_fd in rlist:
            while True:
                try:
                    data = os.read(fifo_fd, 4096)
                except BlockingIOError:
                    break
                if not data:
                    break
                buffer += data.decode()
            while "\n" in buffer:
                line, buffer = buffer.split("\n", 1)
                line = line.strip()
                if line:
                    if line == "toggle-view":
                        state_changed = handle_view_toggle(state) or state_changed
                    elif line.startswith("current "):
                        action = line[8:].strip()
                        state_changed = (
                            handle_smart_action(state, action) or state_changed
                        )
                    elif line.startswith("stopwatch"):
                        action = line[len("stopwatch") :].strip() or "resume"
                        state_changed = handle_stopwatch(state, action) or state_changed
                    elif line.startswith("countdown"):
                        args = (
                            line[len("countdown") :].strip().split()
                            if line[len("countdown") :].strip()
                            else []
                        )
                        state_changed = (
                            handle_countdown(state, args if args else ["resume"])
                            or state_changed
                        )
                    elif line.startswith("pomodoro"):
                        args = (
                            line[len("pomodoro") :].strip().split()
                            if line[len("pomodoro") :].strip()
                            else []
                        )
                        state_changed = (
                            handle_pomodoro(state, args if args else ["toggle-pause"])
                            or state_changed
                        )

        # 2. Update timers (now after commands to avoid race)
        now = time.time()

        cd = state["countdown"]
        if cd["status"] == "running":
            elapsed = now - cd["start_ts"]
            if elapsed >= cd["remaining"]:
                cd["remaining"] = 0
                cd["status"] = "done"
                state_changed = True
                play_sound("alarm")
                send_notification(
                    notify_id_cd, "Time's Up!", "Countdown finished.", level="critical"
                )

        pom = state["pomodoro"]
        if pom["status"] == "running":
            elapsed = now - pom["start_ts"]
            if elapsed >= pom["remaining"]:
                new_phase = "break" if pom["current_phase"] == "work" else "work"
                new_dur = (
                    pom["break_duration"]
                    if new_phase == "break"
                    else pom["work_duration"]
                )
                pom["current_phase"] = new_phase
                pom["start_ts"] = now
                pom["remaining"] = new_dur
                state_changed = True
                play_sound("double" if new_phase == "break" else "single")
                send_notification(
                    notify_id_pom,
                    f"Pomodoro: {new_phase.upper()}",
                    f"Duration: {readable_time(new_dur)}",
                )

        # 3. Save if anything changed
        if state_changed:
            save_state(state)

        # 4. Print current output
        print(build_output(state, now), flush=True)


##########################################
# IPC helpers (command mode)             #
##########################################


def send_command(msg):
    if not os.path.exists(fifo_path):
        return False
    try:
        fd = os.open(fifo_path, os.O_WRONLY | os.O_NONBLOCK)
        os.write(fd, (msg + "\n").encode())
        os.close(fd)
        return True
    except OSError:
        return False


def fallback_command(cmd_str):
    state = load_state()
    changed = False
    if cmd_str == "toggle-view":
        changed = handle_view_toggle(state)
    elif cmd_str.startswith("current "):
        action = cmd_str[8:].strip()
        changed = handle_smart_action(state, action)
    elif cmd_str.startswith("stopwatch"):
        action = cmd_str[len("stopwatch") :].strip() or "resume"
        changed = handle_stopwatch(state, action)
    elif cmd_str.startswith("countdown"):
        args = (
            cmd_str[len("countdown") :].strip().split()
            if cmd_str[len("countdown") :].strip()
            else []
        )
        changed = handle_countdown(state, args if args else ["resume"])
    elif cmd_str.startswith("pomodoro"):
        args = (
            cmd_str[len("pomodoro") :].strip().split()
            if cmd_str[len("pomodoro") :].strip()
            else []
        )
        changed = handle_pomodoro(state, args if args else ["toggle-pause"])
    if changed:
        save_state(state)


##########################################
# Help message                           #
##########################################


def print_help():
    print(
        """
USAGE:
  python3 waybar_timer.py [COMMAND] [ARGS...]
  python3 waybar_timer.py --monitor
  python3 waybar_timer.py --toggle-view

GLOBAL FLAGS:
  --monitor       Run the JSON output loop for Waybar.
  --toggle-view   Cycle between Stopwatch, Countdown, Pomodoro, and Split views.
  --current <ACT> Perform an action on the currently visible timer.

ACTIONS:
    start/resume           Start or resume the timer.
    pause                  Pause the timer if running.
    toggle-pause           Toggle between pause and resume.
    reset                  Stop and reset the timer.  
    add <time>             (Countdown) Add time to the current timer.
    <time>                 (Countdown) Start a new timer with the specified duration.

COMMANDS:

  1. stopwatch [action]

  2. countdown [time | action]
     Examples:
        countdown 10m           Start a 10-minute countdown.
        countdown 1:30          Start a 1 minute 30 second countdown.
        countdown add 5m        Add 5 minutes to current timer.

  3. pomodoro [action]
     Examples:
        pomodoro 25m 5m          Start: 25min Work, 5min Break.
        pomodoro start           Start or resume the current Pomodoro phase.
        pomodoro toggle-pause    Pause or Resume.      

TIME FORMATS:
  Strings: "10m", "1h", "30s", "1h30m"
  Colons:  "1:30" (1m 30s), "1:00:00" (1h)
  Integers: Treated as seconds. eg. "90" = 90 seconds = 1m 30s
"""
    )


##########################################
# Entry point                            #
##########################################


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--monitor", action="store_true")
    parser.add_argument("--toggle-view", action="store_true")
    parser.add_argument("--current", metavar="ACTION")

    if "-h" in sys.argv or "--help" in sys.argv:
        print_help()
        sys.exit(0)

    subparsers = parser.add_subparsers(dest="command")
    subparsers.add_parser("stopwatch", add_help=False).add_argument("action", nargs="?")
    subparsers.add_parser("countdown", add_help=False).add_argument("args", nargs="*")
    subparsers.add_parser("pomodoro", add_help=False).add_argument("args", nargs="*")

    args, _ = parser.parse_known_args()
    if not any([args.monitor, args.toggle_view, args.current, args.command]):
        print_help()
        sys.exit(1)

    if args.monitor:
        run_monitor()
        return

    # Build message string for FIFO
    msg = None
    if args.toggle_view:
        msg = "toggle-view"
    elif args.current:
        msg = f"current {args.current}"
    elif args.command == "stopwatch":
        msg = f"stopwatch {args.action or 'resume'}"
    elif args.command == "countdown":
        msg = "countdown " + " ".join(args.args if args.args else ["resume"])
    elif args.command == "pomodoro":
        msg = "pomodoro " + " ".join(args.args if args.args else ["toggle-pause"])

    if msg:
        if not send_command(msg):
            fallback_command(msg)


if __name__ == "__main__":
    main()

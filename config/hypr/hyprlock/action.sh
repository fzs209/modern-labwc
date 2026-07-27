#!/bin/bash

#####################################
## author @Harsh-bin Github #########
#####################################

state_file="/tmp/hyprlock_action_state"

#############################################
# UI GETTERS (Used by hyprlock text=cmd) ####
#############################################
if [[ "$1" == "--get-yes" ]]; then
    state=$(<"$state_file")
    if [[ -n "$state" && "$state" != "none"* ]]; then
        echo "<span> Yes</span>"
    fi
    exit 0

elif [[ "$1" == "--get-no" ]]; then
    state=$(<"$state_file")
    if [[ -n "$state" && "$state" != "none"* ]]; then
        echo "<span> No</span>"
    fi
    exit 0

elif [[ "$1" == "--get-message" ]]; then
    state=$(<"$state_file")
    if [[ -n "$state" && "$state" != "none"* ]]; then
        # split the state file into Action, Time Left, and Run ID
        IFS=',' read -r action time _ <<< "$state"

        # Fallback just in case time is missing
        if [[ -z "$time" ]]; then time="60"; fi

        case "$action" in
        shutdown)
            echo "<span>Shutdown Now? Auto shutting down in ${time}sec...</span>"
            ;;
        reboot)
            echo "<span>Reboot Now? Auto rebooting in ${time}sec...</span>"
            ;;
        hibernate)
            echo "<span>Hibernate Now? Auto hibernating in ${time}sec...</span>"
            ;;
        esac
    fi
    exit 0
fi

#############################
# HANDLE YES/NO CLICKS ######
#############################

# Helper to instantly trigger hyprlock to update the labels
update_ui() {
    pkill -USR2 hyprlock >/dev/null 2>&1
}

current_state=$(<"$state_file")
# Correctly extract the action even if there are 3 fields (Action,Time,ID)
current_action="${current_state%%,*}"

if [[ "$1" == "yes" ]]; then
    if [[ -z "$current_action" || "$current_action" == "none" ]]; then exit 0; fi

    echo "none" >"$state_file"
    update_ui
    sleep 0.2

    case "$current_action" in
    shutdown)
        shutdown now
        ;;
    reboot)
        reboot
        ;;
    hibernate)
        systemctl hibernate
        ;;
    esac
    exit 0

elif [[ "$1" == "no" ]]; then
    echo "none" >"$state_file"
    update_ui
    exit 0
fi

#######################################
# HANDLE INITIAL ACTION REQUESTS ######
#######################################

# State Lock: Ignore new clicks if an action is already pending!
if [[ -n "$current_action" && "$current_action" != "none" ]]; then
    exit 0
fi

command=""
action_name=""
case "$1" in
--shutdown)
    command="shutdown now"
    action_name="shutdown"
    ;;
--reboot)
    command="reboot"
    action_name="reboot"
    ;;
--sleep)
    systemctl suspend
    update_ui   # updates play-pause indicator of nowplaying.
    exit 0
    ;;
--hibernate)
    command="systemctl hibernate"
    action_name="hibernate"
    ;;
*) exit 1 ;;
esac

# Create a unique Run ID for this background loop using script PID
run_id=$$

# Initialize state with 60 seconds and the unique ID
echo "$action_name,60,$run_id" >"$state_file"
sleep 0.01
update_ui

########################################
# BACKGROUND LIVE COUNTDOWN TIMER ######
########################################
(
    # Loop from 59 down to 1
    for i in {59..1}; do
        # user unlock the PC (hyprlock closed) exit script
        if ! pidof hyprlock >/dev/null; then
            echo "none" >"$state_file"
            exit 0
        fi

        # Extract current state details
        check_state=$(<"$state_file")
        IFS=',' read -r check_action _ check_id <<< "$check_state"

        # Check if the user clicked 'No' OR started a new action (different loop ID)
        if [[ "$check_action" != "$action_name" || "$check_id" != "$run_id" ]]; then
            exit 0
        fi

        # Update the exact remaining seconds in the state file
        echo "$action_name,$i,$run_id" >"$state_file"

        # Instantly update hyprlock UI to show the new countdown number
        update_ui

        sleep 1
    done

    # If the timer completes 60 seconds without being cancelled. Auto-execute!
    check_state=$(<"$state_file")
    IFS=',' read -r check_action _ check_id <<< "$check_state"

    if [[ "$check_action" == "$action_name" && "$check_id" == "$run_id" ]]; then
        echo "none" >"$state_file"
        update_ui
        sleep 0.2
        $command
    fi
) &
disown

exit 0
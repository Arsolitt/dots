#!/usr/bin/env fish

# Control the macOS Dock and menu bar.
#
# Subcommands:
#   off        soft-hide the dock (autohide, near-instant) — Launchpad/Mission Control keep working
#   off --hard fully disable the Dock agent — reversible with `on`
#   on         re-enable the Dock agent and restore default autohide settings
#   hide-bar   hide the menu bar
#   show-bar   show the menu bar

function usage
    echo "Usage: dock.fish <command> [args]"
    echo ""
    echo "Commands:"
    echo "  off          Soft-hide the dock (autohide with no animation; Launchpad and Mission Control keep working)"
    echo "  off --hard   Fully disable the Dock agent (kills Launchpad, Mission Control, ctrl+arrow space switching)"
    echo "  on           Re-enable the Dock and restore default autohide settings"
    echo "  hide-bar     Hide the macOS menu bar (relog if it does not apply)"
    echo "  show-bar     Show the macOS menu bar again (relog if it does not apply)"
end

argparse --name=dock h/help hard -- $argv
or exit 1 # argparse already printed an error

if set -q _flag_help
    usage
    exit 0
end

# A subcommand is required.
if test (count $argv) -lt 1
    usage
    exit 1
end

set -l uid (id -u)
set -l cmd $argv[1]

switch $cmd
    case off
        begin
            if set -q _flag_hard
                # WARNING: this kills Launchpad, Mission Control and ctrl+arrow space switching.
                # Use Raycast or yabai for window/space management instead.
                # Fully reversible with `dock.fish on`.
                echo "Hard-disabling the Dock agent via launchctl..."
                launchctl disable gui/$uid/com.apple.dock
                launchctl bootout gui/$uid/com.apple.dock 2>/dev/null
                echo "Dock agent disabled: Launchpad, Mission Control and ctrl+arrow space switching are gone."
                echo "Use Raycast or yabai for windows/spaces. Re-enable with: dock.fish on"
            else
                # Soft hide: the dock still hosts Launchpad and Mission Control, it just stays out of sight.
                echo "Soft-hiding the dock (autohide, no animation)..."
                defaults write com.apple.dock autohide -bool true
                defaults write com.apple.dock autohide-delay -float 60
                defaults write com.apple.dock autohide-time-modifier -float 0
                killall Dock
                echo "Dock hidden; Launchpad and Mission Control keep working. Restore with: dock.fish on"
            end
        end
    case on
        begin
            echo "Re-enabling the Dock agent and restoring default autohide settings..."
            launchctl enable gui/$uid/com.apple.dock
            launchctl bootstrap gui/$uid /System/Library/LaunchAgents/com.apple.dock.plist 2>/dev/null
            # Remove the soft-hide tweaks written by `off`.
            defaults delete com.apple.dock autohide 2>/dev/null
            defaults delete com.apple.dock autohide-delay 2>/dev/null
            defaults delete com.apple.dock autohide-time-modifier 2>/dev/null
            killall Dock
            echo "Dock restored to defaults."
        end
    case hide-bar
        begin
            echo "Hiding the menu bar (relog if it does not apply)..."
            defaults write NSGlobalDomain _HIHideMenuBar -bool true
            killall SystemUIServer 2>/dev/null
            echo "Menu bar hidden; relog if it did not apply."
        end
    case show-bar
        begin
            echo "Showing the menu bar (relog if it does not apply)..."
            defaults write NSGlobalDomain _HIHideMenuBar -bool false
            killall SystemUIServer 2>/dev/null
            echo "Menu bar visible again; relog if it did not apply."
        end
    case '*'
        begin
            echo "Unknown command: $cmd" >&2
            usage
            exit 1
        end
end

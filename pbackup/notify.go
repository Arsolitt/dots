package main

import (
	"fmt"
	"os/exec"
	"runtime"
	"strings"
)

// Notify modes understood by config.toml.
const (
	notifyOff      = "off"
	notifyFailures = "failures"
	notifyAlways   = "always"
)

// notifyEnabledForFailure reports whether failed runs are announced.
func notifyEnabledForFailure(cfg *Config) bool {
	return cfg != nil && cfg.Notify != notifyOff
}

// notifyEnabledForSuccess reports whether successful runs are announced.
func notifyEnabledForSuccess(cfg *Config) bool {
	return cfg != nil && cfg.Notify == notifyAlways
}

// notify sends a desktop notification unless notifications are disabled.
// Delivery is best effort: a missing notifier is never fatal.
func notify(cfg *Config, title, message string) {
	if !notifyEnabledForFailure(cfg) {
		return
	}
	switch runtime.GOOS {
	case "darwin":
		script := fmt.Sprintf("display notification %s with title %s", appleScriptString(message), appleScriptString(title))
		_ = exec.Command("osascript", "-e", script).Run()
	case "linux":
		_ = exec.Command("notify-send", title, message).Run()
	}
}

// escapeNotify escapes backslashes and double quotes so the text can be
// embedded in an AppleScript string literal.
func escapeNotify(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `"`, `\"`)
	return s
}

// appleScriptString quotes s as an AppleScript string literal.
func appleScriptString(s string) string {
	return `"` + escapeNotify(s) + `"`
}

// notifyFailure reports a failed run when notifications are enabled.
func notifyFailure(cfg *Config, title, message string) {
	if !notifyEnabledForFailure(cfg) {
		return
	}
	notify(cfg, title, message)
}

// notifySuccess reports a successful run only in "always" mode.
func notifySuccess(cfg *Config, title, message string) {
	if !notifyEnabledForSuccess(cfg) {
		return
	}
	notify(cfg, title, message)
}

package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestStateRoundTrip(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "state")

	empty, err := LoadState(dir)
	if err != nil {
		t.Fatalf("LoadState(missing): %v", err)
	}
	if !empty.LastPush.IsZero() || empty.LastPushOK {
		t.Errorf("missing state = %+v, want zero", empty)
	}

	moment := time.Now().Round(time.Second)
	state := &State{
		LastPush:    moment,
		LastPull:    moment.Add(-time.Hour),
		LastPrune:   moment.Add(-2 * time.Hour),
		LastCheck:   moment.Add(-3 * time.Hour),
		LastPushOK:  true,
		LastPullOK:  true,
		LastPruneOK: true,
		LastCheckOK: true,
	}
	if err := SaveState(dir, state); err != nil {
		t.Fatalf("SaveState: %v", err)
	}
	info, err := os.Stat(filepath.Join(dir, "state.json"))
	if err != nil {
		t.Fatalf("stat state.json: %v", err)
	}
	if got := info.Mode().Perm(); got != 0o600 {
		t.Errorf("state.json mode = %v, want 0600", got)
	}

	loaded, err := LoadState(dir)
	if err != nil {
		t.Fatalf("LoadState: %v", err)
	}
	if !loaded.LastPush.Equal(state.LastPush) || !loaded.LastPull.Equal(state.LastPull) ||
		!loaded.LastPrune.Equal(state.LastPrune) || !loaded.LastCheck.Equal(state.LastCheck) {
		t.Errorf("timestamps = %+v, want %+v", loaded, state)
	}
	if !loaded.LastPushOK {
		t.Error("LastPushOK lost")
	}
	if !loaded.LastPullOK {
		t.Error("LastPullOK lost")
	}
	if !loaded.LastPruneOK {
		t.Error("LastPruneOK lost")
	}
	if !loaded.LastCheckOK {
		t.Error("LastCheckOK lost")
	}

	// Saving again replaces the file atomically and leaves no temp files.
	state.LastPushOK = false
	state.LastPullOK = false
	state.LastPruneOK = false
	state.LastCheckOK = false
	if err := SaveState(dir, state); err != nil {
		t.Fatalf("SaveState(second): %v", err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) != 1 || entries[0].Name() != "state.json" {
		t.Errorf("state dir entries = %v, want only state.json", entries)
	}
	loaded, err = LoadState(dir)
	if err != nil {
		t.Fatalf("LoadState(second): %v", err)
	}
	if loaded.LastPushOK {
		t.Error("LastPushOK not updated")
	}
	if loaded.LastPullOK {
		t.Error("LastPullOK not updated")
	}
	if loaded.LastPruneOK {
		t.Error("LastPruneOK not updated")
	}
	if loaded.LastCheckOK {
		t.Error("LastCheckOK not updated")
	}
}

func TestLogLine(t *testing.T) {
	dir := t.TempDir()
	if err := logLine(dir, "push: %s (%d)", "ok", 3); err != nil {
		t.Fatalf("logLine: %v", err)
	}
	if err := logLine(dir, "pull: ok"); err != nil {
		t.Fatalf("logLine: %v", err)
	}
	data, err := os.ReadFile(filepath.Join(dir, "log"))
	if err != nil {
		t.Fatalf("read log: %v", err)
	}
	lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	if len(lines) != 2 {
		t.Fatalf("log lines = %v", lines)
	}
	if !strings.HasSuffix(lines[0], "push: ok (3)") || !strings.HasSuffix(lines[1], "pull: ok") {
		t.Errorf("log content = %v", lines)
	}
	stamp := strings.Fields(lines[0])[0]
	if _, err := time.Parse(time.RFC3339, stamp); err != nil {
		t.Errorf("timestamp %q is not RFC3339: %v", stamp, err)
	}
}

func TestUpdateStatePersistsAndWarns(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "state")
	cfg := &Config{StateDir: dir}
	var warnings strings.Builder
	moment := time.Now().Round(time.Second)
	updateState(cfg, &warnings, func(state *State) {
		state.LastCheck = moment
		state.LastPushOK = true
	})
	if warnings.Len() != 0 {
		t.Fatalf("unexpected warnings: %s", warnings.String())
	}
	state, err := LoadState(dir)
	if err != nil {
		t.Fatalf("LoadState: %v", err)
	}
	if !state.LastCheck.Equal(moment) || !state.LastPushOK {
		t.Errorf("state = %+v", state)
	}
}

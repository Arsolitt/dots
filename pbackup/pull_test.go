package main

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestRescueArgs(t *testing.T) {
	cfg := &Config{Host: "mac"}
	target := &Target{Name: "kube", Tags: []string{"kube", "configs"}}
	got := rescueArgs(cfg, target, "/Users/x/.kube")
	want := []string{
		"backup", "/Users/x/.kube",
		"--host", "mac",
		"--tag", "manual", "--tag", "kube", "--tag", "configs",
		"--retry-lock", "5m",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("rescueArgs = %v, want %v", got, want)
	}
	if countFlag(got, "--host") != 1 {
		t.Errorf("--host must appear exactly once: %v", got)
	}
}

func TestRestoreArgs(t *testing.T) {
	// exclude_sets must not leak into the restore: they are backup-side size
	// policies, and older snapshots may still hold the data.
	target := &Target{Name: "projects", Exclude: []string{"cache"}, ExcludeSets: []string{"project"}}
	snapshot := &Snapshot{ShortID: "6cec0a65"}

	got := restoreArgs(target, snapshot, "/tmp/restore/projects", true, overwriteIfChanged)
	want := []string{
		"restore", "6cec0a65",
		"--target", "/tmp/restore/projects",
		"--overwrite", "if-changed",
		"--exclude", "cache",
		"--verify",
		"--retry-lock", "5m",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("restoreArgs = %v, want %v", got, want)
	}
	if plain := restoreArgs(target, snapshot, "/tmp/restore/projects", false, overwriteIfChanged); countFlag(plain, "--verify") != 0 {
		t.Errorf("--verify must be omitted without the flag: %v", plain)
	}
	wantRetry := []string{
		"restore", "6cec0a65",
		"--target", "/tmp/restore/projects",
		"--overwrite", "always",
		"--exclude", "cache",
		"--retry-lock", "5m",
	}
	if retried := restoreArgs(target, snapshot, "/tmp/restore/projects", false, overwriteAlways); !reflect.DeepEqual(retried, wantRetry) {
		t.Errorf("restoreArgs retry = %v, want %v", retried, wantRetry)
	}
}

func TestRescueArgsExcludes(t *testing.T) {
	cfg := &Config{Host: "linux", ExcludeSets: map[string][]string{"project": {"**/node_modules", "**/.venv"}}}
	target := &Target{
		Name:        "projects",
		Tags:        []string{"projects", "data"},
		Exclude:     []string{"cache"},
		ExcludeSets: []string{"project"},
	}
	got := rescueArgs(cfg, target, "/home/x/projects")
	want := []string{
		"backup", "/home/x/projects",
		"--host", "linux",
		"--tag", "manual", "--tag", "projects", "--tag", "data",
		"--exclude", "cache", "--exclude", "**/node_modules", "--exclude", "**/.venv",
		"--retry-lock", "5m",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("rescueArgs = %v, want %v", got, want)
	}
}

func TestNonRescueSnapshots(t *testing.T) {
	base := time.Date(2026, 9, 30, 12, 0, 0, 0, time.UTC)
	tags := []string{"fixture", "data"}
	plain := Snapshot{ShortID: "plain", Host: "mac", Time: base, Tags: tags}
	rescue := Snapshot{ShortID: "rescue", Host: "mac", Time: base.Add(time.Hour), Tags: []string{"manual", "fixture", "data"}}
	foreignRescue := Snapshot{ShortID: "foreign-rescue", Host: "linux", Time: base.Add(2 * time.Hour), Tags: []string{"fixture", "manual", "data"}}

	// A rescue point is newer and matches every target tag, but must never be
	// the source of a restore.
	kept := nonRescueSnapshots([]Snapshot{plain, rescue, foreignRescue})
	if len(kept) != 1 || kept[0].ShortID != "plain" {
		t.Fatalf("nonRescueSnapshots = %+v, want only the plain snapshot", kept)
	}
	newest := newestSnapshotFor(kept, tags)
	if newest == nil || newest.ShortID != "plain" {
		t.Fatalf("selected %+v, want the plain snapshot", newest)
	}

	// Only rescue points exist: nothing to restore.
	if got := newestSnapshotFor(nonRescueSnapshots([]Snapshot{rescue, foreignRescue}), tags); got != nil {
		t.Errorf("selected %+v, want no snapshot", got)
	}
}

// fakeRestic puts a restic stand-in first in PATH that logs its arguments and
// fails the first failFirst calls before succeeding.
func fakeRestic(t *testing.T, dir string, failFirst int) string {
	t.Helper()
	bin := filepath.Join(dir, "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	argsLog := filepath.Join(dir, "args.log")
	calls := filepath.Join(dir, "calls")
	script := fmt.Sprintf(`#!/bin/sh
printf '%%s\n' "$*" >> %s
n=$(cat %s 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > %s
[ "$n" -le %d ] && exit 1
exit 0
`, argsLog, calls, calls, failFirst)
	path := filepath.Join(bin, "restic")
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	return argsLog
}

func resticCalls(t *testing.T, argsLog string) []string {
	t.Helper()
	data, err := os.ReadFile(argsLog)
	if err != nil {
		t.Fatal(err)
	}
	trimmed := strings.TrimSpace(string(data))
	if trimmed == "" {
		return nil
	}
	return strings.Split(trimmed, "\n")
}

func TestRestoreTreeRetriesWithContentCheck(t *testing.T) {
	dir := t.TempDir()
	argsLog := fakeRestic(t, dir, 1)
	out := &bytes.Buffer{}
	restic := newRestic(&Config{Host: "t"}, out)

	if err := restoreTree(restic, &Target{Name: "kube"}, &Snapshot{ShortID: "6cec0a65"}, "/tmp/restore/kube", false, false, out); err != nil {
		t.Fatalf("restoreTree: %v", err)
	}
	calls := resticCalls(t, argsLog)
	if len(calls) != 2 {
		t.Fatalf("restic calls = %d, want 2: %v", len(calls), calls)
	}
	if !strings.Contains(calls[0], "--overwrite if-changed") {
		t.Errorf("first attempt must keep if-changed: %s", calls[0])
	}
	if !strings.Contains(calls[1], "--overwrite always") {
		t.Errorf("retry must verify content, not metadata: %s", calls[1])
	}
	if !strings.Contains(out.String(), "дозагружаю недостающее") {
		t.Errorf("retry must be reported: %q", out.String())
	}
}

func TestRestoreTreeResumeVerifiesContentOnFirstAttempt(t *testing.T) {
	dir := t.TempDir()
	argsLog := fakeRestic(t, dir, 0)
	out := &bytes.Buffer{}
	restic := newRestic(&Config{Host: "t"}, out)

	if err := restoreTree(restic, &Target{Name: "kube"}, &Snapshot{ShortID: "6cec0a65"}, "/tmp/restore/kube", false, true, out); err != nil {
		t.Fatalf("restoreTree: %v", err)
	}
	calls := resticCalls(t, argsLog)
	if len(calls) != 1 || !strings.Contains(calls[0], "--overwrite always") {
		t.Fatalf("a resumed tree must be content-verified: %v", calls)
	}
}

func TestRestoreTreeStopsAfterAttempts(t *testing.T) {
	dir := t.TempDir()
	argsLog := fakeRestic(t, dir, restoreAttempts)
	out := &bytes.Buffer{}
	restic := newRestic(&Config{Host: "t"}, out)

	if err := restoreTree(restic, &Target{Name: "kube"}, &Snapshot{ShortID: "6cec0a65"}, "/tmp/restore/kube", false, false, out); err == nil {
		t.Fatal("restoreTree must fail once every attempt failed")
	}
	if calls := resticCalls(t, argsLog); len(calls) != restoreAttempts {
		t.Errorf("restic calls = %d, want %d", len(calls), restoreAttempts)
	}
}

func TestPrepareRestoreDir(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "restore", "projects")
	out := &bytes.Buffer{}

	resumed, err := prepareRestoreDir(dir, "c9f28866", out)
	if err != nil {
		t.Fatalf("prepareRestoreDir: %v", err)
	}
	if resumed {
		t.Error("a fresh cache must not report a resume")
	}
	payload := filepath.Join(dir, "home", "arsolitt", "projects", "kept")
	if err := os.MkdirAll(filepath.Dir(payload), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(payload, []byte("data"), 0o644); err != nil {
		t.Fatal(err)
	}

	resumed, err = prepareRestoreDir(dir, "c9f28866", out)
	if err != nil {
		t.Fatalf("prepareRestoreDir: %v", err)
	}
	if !resumed {
		t.Error("the cache of the same snapshot must be resumed")
	}
	if _, err := os.Stat(payload); err != nil {
		t.Errorf("resume must keep the cached payload: %v", err)
	}

	resumed, err = prepareRestoreDir(dir, "13e9ef35", out)
	if err != nil {
		t.Fatalf("prepareRestoreDir: %v", err)
	}
	if resumed {
		t.Error("the cache of another snapshot must not be resumed")
	}
	if _, err := os.Stat(payload); !os.IsNotExist(err) {
		t.Errorf("the cache of another snapshot must be dropped: %v", err)
	}
}

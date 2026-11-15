package main

import (
	"os"
	"path/filepath"
	"reflect"
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

	got := restoreArgs(target, snapshot, "/tmp/restore/projects", true)
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
	if plain := restoreArgs(target, snapshot, "/tmp/restore/projects", false); countFlag(plain, "--verify") != 0 {
		t.Errorf("--verify must be omitted without the flag: %v", plain)
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

func TestRemoveTreeReadOnlyDirs(t *testing.T) {
	root := t.TempDir()
	readonly := filepath.Join(root, "k8s", "1.35.0-linux-amd64")
	if err := os.MkdirAll(readonly, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(readonly, "etcd"), []byte("binary"), 0o555); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(readonly, 0o555); err != nil {
		t.Fatal(err)
	}
	if err := removeTree(root); err != nil {
		t.Fatalf("removeTree: %v", err)
	}
	if _, err := os.Stat(root); !os.IsNotExist(err) {
		t.Fatalf("tree still exists: %v", err)
	}
}

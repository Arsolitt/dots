package main

import (
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

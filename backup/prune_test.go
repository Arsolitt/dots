package main

import (
	"reflect"
	"testing"
)

func TestStaleSnapshots(t *testing.T) {
	snapshots := []Snapshot{
		{ShortID: "untagged"},
		{ShortID: "manual-with-tags", Tags: []string{"old", "manual"}},
		{ShortID: "manual-only", Tags: []string{"manual"}},
		{ShortID: "active-configs", Tags: []string{"kube", "configs"}},
		{ShortID: "active-data", Tags: []string{"projects", "data"}},
		{ShortID: "stale-configs", Tags: []string{"zen", "configs"}},
		{ShortID: "stale-data", Tags: []string{"old", "data"}},
	}
	registry := map[string]bool{"configs,kube": true, "data,projects": true}

	got := staleIDs(staleSnapshots(snapshots, registry))
	want := []string{"stale-configs", "stale-data"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("stale = %v, want %v", got, want)
	}

	// An empty registry leaves only untagged and manual snapshots alone.
	got = staleIDs(staleSnapshots(snapshots, map[string]bool{}))
	want = []string{"active-configs", "active-data", "stale-configs", "stale-data"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("stale with empty registry = %v, want %v", got, want)
	}
}

func TestTagRegistry(t *testing.T) {
	cfg := &Config{Targets: []Target{
		{Name: "kube", Tags: []string{"kube", "configs"}},
		{Name: "projects", Tags: []string{"projects", "data"}},
		{Name: "media", Tags: []string{"media"}},
		{Name: "projects-dup", Tags: []string{"data", "projects"}},
	}}
	registry := tagRegistry(cfg)
	want := map[string]bool{"configs,kube": true, "data,projects": true, "media": true}
	if !reflect.DeepEqual(registry, want) {
		t.Errorf("registry = %v, want %v", registry, want)
	}
}

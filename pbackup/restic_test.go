package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestSnapshotUnmarshalWithoutTags(t *testing.T) {
	const payload = `[{"short_id":"abc1234","hostname":"mac","time":"2026-09-30T10:11:12Z","paths":["/Users/x/projects"]}]`
	var snapshots []Snapshot
	if err := json.Unmarshal([]byte(payload), &snapshots); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(snapshots) != 1 {
		t.Fatalf("got %d snapshots, want 1", len(snapshots))
	}
	snapshot := snapshots[0]
	if snapshot.ShortID != "abc1234" || snapshot.Host != "mac" {
		t.Errorf("snapshot = %+v", snapshot)
	}
	if snapshot.Tags != nil {
		t.Errorf("Tags = %v, want nil", snapshot.Tags)
	}
	if got := snapshot.TagSet(); got != "" {
		t.Errorf("TagSet = %q, want empty", got)
	}
	if got := snapshot.Time.UTC().Format(time.RFC3339); got != "2026-09-30T10:11:12Z" {
		t.Errorf("Time = %q", got)
	}
	if !reflect.DeepEqual(snapshot.Paths, []string{"/Users/x/projects"}) {
		t.Errorf("Paths = %v", snapshot.Paths)
	}
	if snapshot.HasTag("manual") || snapshot.HasTags([]string{"manual"}) {
		t.Error("untagged snapshot reports tags")
	}
}

func TestSnapshotTagSet(t *testing.T) {
	cases := []struct {
		name string
		tags []string
		want string
	}{
		{"nil", nil, ""},
		{"empty", []string{}, ""},
		{"single", []string{"kube"}, "kube"},
		{"sorted", []string{"kube", "configs"}, "configs,kube"},
		{"duplicates", []string{"configs", "kube", "configs"}, "configs,kube"},
		{"manual", []string{"manual", "projects"}, "manual,projects"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			snapshot := Snapshot{Tags: tc.tags}
			if got := snapshot.TagSet(); got != tc.want {
				t.Errorf("TagSet(%v) = %q, want %q", tc.tags, got, tc.want)
			}
		})
	}
	if !(Snapshot{Tags: []string{"a", "b"}}).HasTags([]string{"b", "a"}) {
		t.Error("HasTags should ignore order")
	}
	if (Snapshot{Tags: []string{"a"}}).HasTags([]string{"a", "b"}) {
		t.Error("HasTags should require every tag")
	}
}

func TestRetentionFlags(t *testing.T) {
	cases := []struct {
		name      string
		retention Retention
		want      []string
	}{
		{"none", Retention{}, nil},
		{"last only", Retention{KeepLast: 3}, []string{"--keep-last", "3"}},
		{"daily and weekly", Retention{KeepDaily: 7, KeepWeekly: 4}, []string{"--keep-daily", "7", "--keep-weekly", "4"}},
		{"all", Retention{KeepLast: 1, KeepDaily: 2, KeepWeekly: 3, KeepMonthly: 4, KeepYearly: 5},
			[]string{"--keep-last", "1", "--keep-daily", "2", "--keep-weekly", "3", "--keep-monthly", "4", "--keep-yearly", "5"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := retentionFlags(tc.retention); !reflect.DeepEqual(got, tc.want) {
				t.Errorf("retentionFlags(%+v) = %v, want %v", tc.retention, got, tc.want)
			}
		})
	}
}

func TestTagFilter(t *testing.T) {
	if got := tagFilter([]string{"kube", "configs"}); got != "kube,configs" {
		t.Errorf("tagFilter = %q", got)
	}
	if got := tagFilter(nil); got != "" {
		t.Errorf("tagFilter(nil) = %q", got)
	}
}

func TestRestorePayloadPath(t *testing.T) {
	dir := filepath.Join("/tmp", "cache", "restore", "projects")
	got, err := restorePayloadPath(dir, Snapshot{ShortID: "abc1234", Paths: []string{"/Users/x/projects"}})
	if err != nil {
		t.Fatalf("restorePayloadPath: %v", err)
	}
	if want := filepath.Join(dir, "Users", "x", "projects"); got != want {
		t.Errorf("payload = %q, want %q", got, want)
	}
	if _, err := restorePayloadPath(dir, Snapshot{ShortID: "abc1234"}); err == nil {
		t.Error("missing snapshot paths = nil error, want failure")
	}
}

func TestResticEnv(t *testing.T) {
	t.Setenv("RESTIC_REPOSITORY", "sftp:stale:/repo")
	t.Setenv("PATH", "/usr/bin:/bin")
	// The machine identity must never travel as RESTIC_HOST: restic uses that
	// variable as the default snapshot filter and would hide other machines.
	previousHost, hadHost := os.LookupEnv("RESTIC_HOST")
	if err := os.Unsetenv("RESTIC_HOST"); err != nil {
		t.Fatalf("unsetenv RESTIC_HOST: %v", err)
	}
	t.Cleanup(func() {
		if hadHost {
			_ = os.Setenv("RESTIC_HOST", previousHost)
		}
	})

	restic := &Restic{
		Repository:      "local:/tmp/repo",
		PasswordCommand: "echo pass",
		Compression:     "auto",
		CacheDir:        "/tmp/cache",
	}
	env := restic.env()
	if got := countEnv(env, "RESTIC_HOST"); got != 0 {
		t.Errorf("RESTIC_HOST present %d times in the child env, want 0", got)
	}
	if got := countEnv(env, "RESTIC_REPOSITORY"); got != 1 {
		t.Errorf("RESTIC_REPOSITORY appears %d times, want 1", got)
	}
	want := map[string]string{
		"RESTIC_REPOSITORY":       "local:/tmp/repo",
		"RESTIC_PASSWORD_COMMAND": "echo pass",
		"RESTIC_COMPRESSION":      "auto",
		"RESTIC_CACHE_DIR":        filepath.Join("/tmp/cache", "restic"),
		// The restic binary shells out to ssh/sftp, so PATH must survive.
		"PATH": "/usr/bin:/bin",
	}
	for key, value := range want {
		if got := envValue(env, key); got != value {
			t.Errorf("%s = %q, want %q", key, got, value)
		}
	}

	restic.ExtraEnv = []string{"RESTIC_CACHE_DIR=/tmp/override", "RESTIC_INSECURE_NO_PASSWORD=true"}
	env = restic.env()
	if got := countEnv(env, "RESTIC_CACHE_DIR"); got != 1 {
		t.Errorf("RESTIC_CACHE_DIR appears %d times, want 1", got)
	}
	if got := envValue(env, "RESTIC_CACHE_DIR"); got != "/tmp/override" {
		t.Errorf("ExtraEnv must win: RESTIC_CACHE_DIR = %q", got)
	}
	if got := envValue(env, "RESTIC_INSECURE_NO_PASSWORD"); got != "true" {
		t.Errorf("ExtraEnv entry missing: %q", got)
	}
}

func TestResticLimitUpload(t *testing.T) {
	restic := &Restic{LimitUpload: 500}
	got := restic.withLimitUpload([]string{"backup", "/data"})
	want := []string{"backup", "/data", "--limit-upload", "500"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("withLimitUpload = %v, want %v", got, want)
	}
	restic.LimitUpload = 0
	if got := restic.withLimitUpload([]string{"backup", "/data"}); !reflect.DeepEqual(got, []string{"backup", "/data"}) {
		t.Errorf("unlimited = %v", got)
	}
}

func TestLastLines(t *testing.T) {
	cases := []struct {
		name string
		in   string
		n    int
		want string
	}{
		{"empty", "", 3, ""},
		{"short", "one\n", 3, "one"},
		{"tail", "a\nb\nc\nd\n", 2, "c\nd"},
		{"no newline", "solo", 3, "solo"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := lastLines(tc.in, tc.n); got != tc.want {
				t.Errorf("lastLines(%q, %d) = %q, want %q", tc.in, tc.n, got, tc.want)
			}
		})
	}
}

func TestNewestSnapshotFor(t *testing.T) {
	base := time.Date(2026, 9, 30, 12, 0, 0, 0, time.UTC)
	snapshots := []Snapshot{
		{ShortID: "old", Time: base.Add(-48 * time.Hour), Tags: []string{"kube", "configs"}},
		{ShortID: "new", Time: base, Tags: []string{"kube", "configs"}},
		{ShortID: "other", Time: base.Add(time.Hour), Tags: []string{"projects", "data"}},
	}
	newest := newestSnapshotFor(snapshots, []string{"configs", "kube"})
	if newest == nil || newest.ShortID != "new" {
		t.Errorf("newestSnapshotFor = %+v, want new", newest)
	}
	if got := newestSnapshotFor(snapshots, []string{"missing"}); got != nil {
		t.Errorf("newestSnapshotFor(missing) = %+v, want nil", got)
	}
}

func TestNewerForeignSnapshot(t *testing.T) {
	base := time.Date(2026, 9, 30, 12, 0, 0, 0, time.UTC)
	snapshots := []Snapshot{
		{ShortID: "mine", Host: "mac", Time: base.Add(time.Hour)},
		{ShortID: "foreign-old", Host: "linux", Time: base.Add(-time.Hour)},
		{ShortID: "foreign-new", Host: "linux", Time: base.Add(2 * time.Hour)},
	}
	if got := newerForeignSnapshot(snapshots, "mac", base); got == nil || got.ShortID != "foreign-new" {
		t.Errorf("newerForeignSnapshot = %+v, want foreign-new", got)
	}
	if got := newerForeignSnapshot(snapshots, "mac", base.Add(3*time.Hour)); got != nil {
		t.Errorf("newerForeignSnapshot after all = %+v, want nil", got)
	}
	if got := newerForeignSnapshot(snapshots, "mac", time.Time{}); got == nil || got.ShortID != "foreign-new" {
		t.Errorf("zero baseline = %+v, want foreign-new", got)
	}
}

// countEnv counts how many entries carry the given key.
func countEnv(env []string, key string) int {
	count := 0
	for _, kv := range env {
		if name, _, ok := strings.Cut(kv, "="); ok && name == key {
			count++
		}
	}
	return count
}

// envValue returns the value of key (last occurrence) or "".
func envValue(env []string, key string) string {
	value := ""
	for _, kv := range env {
		if name, v, ok := strings.Cut(kv, "="); ok && name == key {
			value = v
		}
	}
	return value
}

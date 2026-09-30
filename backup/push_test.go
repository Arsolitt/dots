package main

import (
	"reflect"
	"testing"
)

func TestBackupArgs(t *testing.T) {
	cfg := &Config{
		Host:        "mac",
		ExcludeSets: map[string][]string{"project": {"**/node_modules", "**/dist"}},
	}
	target := &Target{
		Name:        "projects",
		Path:        "~/projects",
		Tags:        []string{"projects", "data"},
		Exclude:     []string{"cache"},
		ExcludeSets: []string{"project"},
	}

	got := backupArgs(cfg, target, "/Users/x/projects", false)
	want := []string{
		"backup", "/Users/x/projects",
		"--host", "mac",
		"--tag", "projects", "--tag", "data",
		"--exclude", "cache", "--exclude", "**/node_modules", "--exclude", "**/dist",
		"--retry-lock", "5m",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("backupArgs = %v, want %v", got, want)
	}

	dry := backupArgs(cfg, target, "/Users/x/projects", true)
	if !hasFlag(dry, "--dry-run") {
		t.Errorf("dry run missing --dry-run: %v", dry)
	}
	if countFlag(dry, "--host") != 1 {
		t.Errorf("--host must appear exactly once: %v", dry)
	}
	if !hasPair(dry, "--host", "mac") {
		t.Errorf("--host mac missing: %v", dry)
	}
}

// TestForgetArgsStaysRepoWide guards the retention scope: a host filter here
// would leave other machines' lineages (and legacy host names) untouched.
func TestForgetArgsStaysRepoWide(t *testing.T) {
	got := forgetArgs("data", Retention{KeepLast: 2, KeepDaily: 7})
	want := []string{
		"forget", "--group-by", "host,tags", "--tag", "data",
		"--keep-last", "2", "--keep-daily", "7",
		"--retry-lock", "5m",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("forgetArgs = %v, want %v", got, want)
	}
	if countFlag(got, "--host") != 0 {
		t.Errorf("retention must not filter by host: %v", got)
	}

	empty := forgetArgs("media", Retention{})
	want = []string{"forget", "--group-by", "host,tags", "--tag", "media", "--retry-lock", "5m"}
	if !reflect.DeepEqual(empty, want) {
		t.Errorf("forgetArgs(empty policy) = %v, want %v", empty, want)
	}
}

// hasFlag reports whether name is present.
func hasFlag(args []string, name string) bool {
	for _, arg := range args {
		if arg == name {
			return true
		}
	}
	return false
}

// hasPair reports whether name is followed by value.
func hasPair(args []string, name, value string) bool {
	for i := 0; i+1 < len(args); i++ {
		if args[i] == name && args[i+1] == value {
			return true
		}
	}
	return false
}

// countFlag counts occurrences of a flag name.
func countFlag(args []string, name string) int {
	count := 0
	for _, arg := range args {
		if arg == name {
			count++
		}
	}
	return count
}

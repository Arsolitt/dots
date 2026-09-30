package main

import (
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"testing"
)

const testConfig = `
repository       = "sftp:test:/repo"
password_command = "echo testpass"
notify           = "failures"

[schedule]
push_time     = "12:00"
prune_weekday = "sunday"
prune_time    = "13:00"

[exclude_sets]
project = ["**/node_modules", "**/dist"]

[retention.data]
keep_daily = 7

[retention.configs]
keep_last = 1

[[targets]]
name         = "projects"
path         = "~/projects"
tags         = ["projects", "data"]
exclude      = ["cache"]
exclude_sets = ["project"]

[[targets]]
name = "kube"
path = "~/.kube"
tags = ["kube", "configs"]
`

func writeTempConfig(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}
	return path
}

func TestLoadConfigDefaults(t *testing.T) {
	cfg, err := LoadConfig(writeTempConfig(t, testConfig))
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}
	wantHost := "linux"
	if runtime.GOOS == "darwin" {
		wantHost = "mac"
	}
	if cfg.Host != wantHost {
		t.Errorf("Host = %q, want %q", cfg.Host, wantHost)
	}
	if cfg.Notify != "failures" {
		t.Errorf("Notify = %q, want failures", cfg.Notify)
	}
	if cfg.Compression != "auto" {
		t.Errorf("Compression = %q, want auto", cfg.Compression)
	}
	if !strings.HasSuffix(cfg.CacheDir, filepath.Join(".cache", "backup")) {
		t.Errorf("CacheDir = %q, want ~/.cache/backup", cfg.CacheDir)
	}
	if !strings.HasSuffix(cfg.StateDir, filepath.Join(".local", "state", "backup")) {
		t.Errorf("StateDir = %q, want ~/.local/state/backup", cfg.StateDir)
	}
	if cfg.Repository != "sftp:test:/repo" {
		t.Errorf("Repository = %q", cfg.Repository)
	}
	if cfg.Schedule.PushTime != "12:00" || cfg.Schedule.PruneWeekday != "sunday" {
		t.Errorf("Schedule = %+v", cfg.Schedule)
	}
	if len(cfg.Targets) != 2 {
		t.Fatalf("got %d targets, want 2", len(cfg.Targets))
	}
}

func TestLoadConfigExplicitHostWins(t *testing.T) {
	cfg, err := LoadConfig(writeTempConfig(t, "host = \"custom-repo\"\n"+testConfig))
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}
	if cfg.Host != "custom-repo" {
		t.Errorf("Host = %q, want custom-repo", cfg.Host)
	}
}

func TestTargetHelpers(t *testing.T) {
	cfg, err := LoadConfig(writeTempConfig(t, testConfig))
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}
	projects, err := cfg.TargetByName("projects")
	if err != nil {
		t.Fatalf("TargetByName: %v", err)
	}
	if got := projects.Category(cfg); got != "data" {
		t.Errorf("Category = %q, want data", got)
	}
	wantExcludes := []string{"cache", "**/node_modules", "**/dist"}
	if got := projects.AllExcludes(cfg); !reflect.DeepEqual(got, wantExcludes) {
		t.Errorf("AllExcludes = %v, want %v", got, wantExcludes)
	}
	kube, err := cfg.TargetByName("kube")
	if err != nil {
		t.Fatalf("TargetByName(kube): %v", err)
	}
	if got := kube.Category(cfg); got != "configs" {
		t.Errorf("kube Category = %q, want configs", got)
	}
	if got := kube.AllExcludes(cfg); len(got) != 0 {
		t.Errorf("kube AllExcludes = %v, want none", got)
	}
	if _, err := cfg.TargetByName("nope"); err == nil {
		t.Error("TargetByName(nope) = nil error, want failure")
	}
}

func TestSelectTargets(t *testing.T) {
	cfg, err := LoadConfig(writeTempConfig(t, testConfig))
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}
	all, err := selectTargets(cfg, nil)
	if err != nil {
		t.Fatalf("selectTargets(nil): %v", err)
	}
	if names := targetNames(all); !reflect.DeepEqual(names, []string{"projects", "kube"}) {
		t.Errorf("all targets = %v", names)
	}
	picked, err := selectTargets(cfg, []string{"kube", "kube"})
	if err != nil {
		t.Fatalf("selectTargets: %v", err)
	}
	if names := targetNames(picked); !reflect.DeepEqual(names, []string{"kube"}) {
		t.Errorf("picked targets = %v", names)
	}
	if _, err := selectTargets(cfg, []string{"ghost"}); err == nil {
		t.Error("selectTargets(ghost) = nil error, want failure")
	}
}

func TestExpandPath(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	if got := ExpandPath("~/projects"); got != filepath.Join(home, "projects") {
		t.Errorf("ExpandPath(~/projects) = %q", got)
	}
	if got := ExpandPath("~"); got != home {
		t.Errorf("ExpandPath(~) = %q", got)
	}
	if got := ExpandPath("/absolute/path"); got != "/absolute/path" {
		t.Errorf("ExpandPath(/absolute/path) = %q", got)
	}
	if got := ExpandPath("relative"); got != "relative" {
		t.Errorf("ExpandPath(relative) = %q", got)
	}
}

func TestValidateRejectsBadConfigs(t *testing.T) {
	const validTarget = `
[retention.data]
keep_daily = 1

[[targets]]
name = "a"
path = "/a"
tags = ["a", "data"]
`
	cases := []struct {
		name   string
		config string
	}{
		{"missing repository", validTarget},
		{"empty name", "repository = \"r\"\n" + `
[retention.data]
keep_daily = 1

[[targets]]
name = ""
path = "/a"
tags = ["a", "data"]
`},
		{"duplicate names", "repository = \"r\"\n" + `
[retention.data]
keep_daily = 1

[[targets]]
name = "a"
path = "/a"
tags = ["a", "data"]

[[targets]]
name = "a"
path = "/b"
tags = ["a", "data"]
`},
		{"no tags", "repository = \"r\"\n" + `
[retention.data]
keep_daily = 1

[[targets]]
name = "a"
path = "/a"
`},
		{"no retention tag", "repository = \"r\"\n" + `
[retention.data]
keep_daily = 1

[[targets]]
name = "a"
path = "/a"
tags = ["other"]
`},
		{"two retention tags", "repository = \"r\"\n" + `
[retention.data]
keep_daily = 1

[retention.configs]
keep_last = 1

[[targets]]
name = "a"
path = "/a"
tags = ["data", "configs"]
`},
		{"unknown exclude set", "repository = \"r\"\n" + `
[retention.data]
keep_daily = 1

[[targets]]
name = "a"
path = "/a"
tags = ["a", "data"]
exclude_sets = ["ghost"]
`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := LoadConfig(writeTempConfig(t, tc.config)); err == nil {
				t.Fatal("LoadConfig succeeded, want validation error")
			}
		})
	}
	// The same shape with a repository is accepted.
	if _, err := LoadConfig(writeTempConfig(t, "repository = \"r\"\n"+validTarget)); err != nil {
		t.Fatalf("valid config rejected: %v", err)
	}
}

func TestPasswordCommandPerOS(t *testing.T) {
	configWithPasswords := func(darwin, linux string) string {
		return `
repository = "sftp:test:/repo"
password_command = "base-command"
password_command_darwin = "` + darwin + `"
password_command_linux = "` + linux + `"

[retention.data]
keep_daily = 1

[[targets]]
name = "a"
path = "/a"
tags = ["a", "data"]
`
	}
	thisPlatform := "linux-command"
	if runtime.GOOS == "darwin" {
		thisPlatform = "darwin-command"
	}

	// Both overrides set: the one for this platform wins.
	cfg, err := LoadConfig(writeTempConfig(t, configWithPasswords("darwin-command", "linux-command")))
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}
	if cfg.PasswordCommand != thisPlatform {
		t.Errorf("PasswordCommand = %q, want %q", cfg.PasswordCommand, thisPlatform)
	}

	// No overrides: the shared command stays.
	cfg, err = LoadConfig(writeTempConfig(t, configWithPasswords("", "")))
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}
	if cfg.PasswordCommand != "base-command" {
		t.Errorf("PasswordCommand = %q, want base-command", cfg.PasswordCommand)
	}

	// Only the other platform's override is set: it must be ignored here.
	otherDarwin, otherLinux := "darwin-command", ""
	if runtime.GOOS == "darwin" {
		otherDarwin, otherLinux = "", "linux-command"
	}
	cfg, err = LoadConfig(writeTempConfig(t, configWithPasswords(otherDarwin, otherLinux)))
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}
	if cfg.PasswordCommand != "base-command" {
		t.Errorf("PasswordCommand = %q on %s, want base-command", cfg.PasswordCommand, runtime.GOOS)
	}
}

func TestExtractConfigFlag(t *testing.T) {
	t.Setenv("BACKUP_CONFIG", "")
	path, rest, err := extractConfigFlag([]string{"push", "--dry-run"})
	if err != nil {
		t.Fatalf("extractConfigFlag: %v", err)
	}
	if path != DefaultConfigPath() {
		t.Errorf("path = %q, want default", path)
	}
	if !reflect.DeepEqual(rest, []string{"push", "--dry-run"}) {
		t.Errorf("rest = %v", rest)
	}

	path, rest, err = extractConfigFlag([]string{"--config", "/tmp/c.toml", "pull", "--yes"})
	if err != nil {
		t.Fatalf("extractConfigFlag: %v", err)
	}
	if path != "/tmp/c.toml" || !reflect.DeepEqual(rest, []string{"pull", "--yes"}) {
		t.Errorf("got path=%q rest=%v", path, rest)
	}

	path, rest, err = extractConfigFlag([]string{"snapshots", "--config=/tmp/d.toml"})
	if err != nil {
		t.Fatalf("extractConfigFlag: %v", err)
	}
	if path != "/tmp/d.toml" || !reflect.DeepEqual(rest, []string{"snapshots"}) {
		t.Errorf("got path=%q rest=%v", path, rest)
	}

	if _, _, err := extractConfigFlag([]string{"push", "--config"}); err == nil {
		t.Error("extractConfigFlag(--config without value) = nil error, want failure")
	}

	t.Setenv("BACKUP_CONFIG", "/tmp/env.toml")
	path, _, err = extractConfigFlag([]string{"push"})
	if err != nil {
		t.Fatalf("extractConfigFlag: %v", err)
	}
	if path != "/tmp/env.toml" {
		t.Errorf("path = %q, want /tmp/env.toml", path)
	}
}

func TestDispatchWithoutConfig(t *testing.T) {
	var out, errOut strings.Builder
	if err := run([]string{"version"}, &out, &errOut); err != nil {
		t.Fatalf("version: %v", err)
	}
	if got := strings.TrimSpace(out.String()); got != "backup 0.1.0" {
		t.Errorf("version output = %q", got)
	}
	out.Reset()
	if err := run([]string{"frobnicate"}, &out, &errOut); err == nil {
		t.Error("unknown command = nil error, want failure")
	}
	if !strings.Contains(errOut.String(), "Использование") {
		t.Errorf("usage not printed: %q", errOut.String())
	}
	errOut.Reset()
	if err := run(nil, &out, &errOut); err == nil {
		t.Error("no command = nil error, want failure")
	}
}

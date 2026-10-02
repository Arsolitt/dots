package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/BurntSushi/toml"
)

// Config mirrors config.toml — the single source of truth for targets,
// excludes, retention and scheduling.
type Config struct {
	Repository            string               `toml:"repository"`
	PasswordCommand       string               `toml:"password_command"`
	PasswordCommandDarwin string               `toml:"password_command_darwin"`
	PasswordCommandLinux  string               `toml:"password_command_linux"`
	Host                  string               `toml:"host"`
	Compression           string               `toml:"compression"`
	Notify                string               `toml:"notify"`
	CacheDir              string               `toml:"cache_dir"`
	StateDir              string               `toml:"state_dir"`
	LimitUpload           int                  `toml:"limit_upload_kib"`
	Schedule              Schedule             `toml:"schedule"`
	ExcludeSets           map[string][]string  `toml:"exclude_sets"`
	Retention             map[string]Retention `toml:"retention"`
	Targets               []Target             `toml:"targets"`
}

// Target is one backed-up path with its snapshot tags and exclusions.
type Target struct {
	Name        string   `toml:"name"`
	Path        string   `toml:"path"`
	Tags        []string `toml:"tags"`
	Exclude     []string `toml:"exclude"`
	ExcludeSets []string `toml:"exclude_sets"`
}

// Retention is the restic forget policy of one retention category.
type Retention struct {
	KeepLast    int `toml:"keep_last"`
	KeepDaily   int `toml:"keep_daily"`
	KeepWeekly  int `toml:"keep_weekly"`
	KeepMonthly int `toml:"keep_monthly"`
	KeepYearly  int `toml:"keep_yearly"`
}

// Schedule mirrors the [schedule] section of config.toml.
type Schedule struct {
	PushTime     string `toml:"push_time"`
	PruneWeekday string `toml:"prune_weekday"`
	PruneTime    string `toml:"prune_time"`
}

// DefaultConfigPath is used when neither --config nor PBACKUP_CONFIG is set.
func DefaultConfigPath() string {
	return ExpandPath("~/.config/pbackup/config.toml")
}

// LoadConfig reads, defaults and validates the configuration file.
func LoadConfig(path string) (*Config, error) {
	var cfg Config
	if _, err := toml.DecodeFile(path, &cfg); err != nil {
		return nil, fmt.Errorf("config %s: %w", path, err)
	}
	cfg.applyDefaults()
	if err := cfg.Validate(); err != nil {
		return nil, fmt.Errorf("config %s: %w", path, err)
	}
	return &cfg, nil
}

func (cfg *Config) applyDefaults() {
	if cfg.Host == "" {
		if runtime.GOOS == "darwin" {
			cfg.Host = "mac"
		} else {
			cfg.Host = "linux"
		}
	}
	if cfg.Notify == "" {
		cfg.Notify = "failures"
	}
	if cfg.Compression == "" {
		cfg.Compression = "auto"
	}
	if cfg.CacheDir == "" {
		cfg.CacheDir = ExpandPath("~/.cache/pbackup")
	}
	if cfg.StateDir == "" {
		cfg.StateDir = ExpandPath("~/.local/state/pbackup")
	}
	cfg.CacheDir = ExpandPath(cfg.CacheDir)
	cfg.StateDir = ExpandPath(cfg.StateDir)
	cfg.resolvePasswordCommand()
}

// resolvePasswordCommand lets the platform-specific override win. A scheduled
// run has no login session, so a machine may need a password command that does
// not depend on an unlocked agent or a pinentry prompt.
func (cfg *Config) resolvePasswordCommand() {
	switch runtime.GOOS {
	case "darwin":
		if cfg.PasswordCommandDarwin != "" {
			cfg.PasswordCommand = cfg.PasswordCommandDarwin
		}
	case "linux":
		if cfg.PasswordCommandLinux != "" {
			cfg.PasswordCommand = cfg.PasswordCommandLinux
		}
	}
}

// Validate enforces the invariants the commands rely on.
func (cfg *Config) Validate() error {
	if strings.TrimSpace(cfg.Repository) == "" {
		return fmt.Errorf("repository is not set")
	}
	seen := make(map[string]bool, len(cfg.Targets))
	for i := range cfg.Targets {
		t := &cfg.Targets[i]
		if strings.TrimSpace(t.Name) == "" {
			return fmt.Errorf("target #%d has an empty name", i+1)
		}
		if seen[t.Name] {
			return fmt.Errorf("duplicate target name %q", t.Name)
		}
		seen[t.Name] = true
		if len(t.Tags) == 0 {
			return fmt.Errorf("target %q has no tags", t.Name)
		}
		if category := t.Category(cfg); category == "" {
			return fmt.Errorf("target %q has no tag present in [retention]", t.Name)
		}
		for _, name := range t.ExcludeSets {
			if _, ok := cfg.ExcludeSets[name]; !ok {
				return fmt.Errorf("target %q references unknown exclude set %q", t.Name, name)
			}
		}
	}
	for _, t := range cfg.Targets {
		count := 0
		for _, tag := range t.Tags {
			if _, ok := cfg.Retention[tag]; ok {
				count++
			}
		}
		if count > 1 {
			return fmt.Errorf("target %q matches %d retention categories, want exactly one", t.Name, count)
		}
	}
	return nil
}

// TargetByName resolves a target by its config name.
func (cfg *Config) TargetByName(name string) (*Target, error) {
	for i := range cfg.Targets {
		if cfg.Targets[i].Name == name {
			return &cfg.Targets[i], nil
		}
	}
	return nil, fmt.Errorf("unknown target %q", name)
}

// Category is the retention category of the target: the single tag that has a
// [retention] section. Validate guarantees it exists and is unambiguous.
func (t *Target) Category(cfg *Config) string {
	for _, tag := range t.Tags {
		if _, ok := cfg.Retention[tag]; ok {
			return tag
		}
	}
	return ""
}

// AllExcludes returns the exclude patterns of a target: its own patterns first,
// then the patterns of every referenced exclude set, in config order.
func (t *Target) AllExcludes(cfg *Config) []string {
	patterns := make([]string, 0, len(t.Exclude))
	patterns = append(patterns, t.Exclude...)
	for _, name := range t.ExcludeSets {
		patterns = append(patterns, cfg.ExcludeSets[name]...)
	}
	return patterns
}

// selectTargets maps positional arguments to targets; no arguments means all
// targets in config order. Duplicates are collapsed.
func selectTargets(cfg *Config, names []string) ([]*Target, error) {
	if len(names) == 0 {
		targets := make([]*Target, 0, len(cfg.Targets))
		for i := range cfg.Targets {
			targets = append(targets, &cfg.Targets[i])
		}
		return targets, nil
	}
	targets := make([]*Target, 0, len(names))
	seen := make(map[string]bool, len(names))
	for _, name := range names {
		if seen[name] {
			continue
		}
		seen[name] = true
		t, err := cfg.TargetByName(name)
		if err != nil {
			return nil, err
		}
		targets = append(targets, t)
	}
	return targets, nil
}

// ExpandPath expands a leading "~" to the current user's home directory.
func ExpandPath(path string) string {
	if path != "~" && !strings.HasPrefix(path, "~/") {
		return path
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return path
	}
	if path == "~" {
		return home
	}
	return filepath.Join(home, path[2:])
}

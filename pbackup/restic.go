package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

// retryLock is passed to every command that takes a repository lock.
const retryLock = "5m"

// Snapshot is the subset of `restic snapshots --json` this tool relies on.
type Snapshot struct {
	ShortID string    `json:"short_id"`
	Host    string    `json:"hostname"`
	Time    time.Time `json:"time"`
	Tags    []string  `json:"tags"`
	Paths   []string  `json:"paths"`
}

// TagSet renders the snapshot tags as a sorted, de-duplicated, comma-joined
// string. Untagged snapshots render as "".
func (s Snapshot) TagSet() string {
	return tagSet(s.Tags)
}

// HasTag reports whether the snapshot carries the given tag.
func (s Snapshot) HasTag(tag string) bool {
	for _, t := range s.Tags {
		if t == tag {
			return true
		}
	}
	return false
}

// HasTags reports whether the snapshot carries every given tag.
func (s Snapshot) HasTags(tags []string) bool {
	for _, tag := range tags {
		if !s.HasTag(tag) {
			return false
		}
	}
	return true
}

// tagSet is TagSet for a plain tag slice; the prune registry uses it too.
func tagSet(tags []string) string {
	if len(tags) == 0 {
		return ""
	}
	unique := make(map[string]bool, len(tags))
	sorted := make([]string, 0, len(tags))
	for _, tag := range tags {
		if unique[tag] {
			continue
		}
		unique[tag] = true
		sorted = append(sorted, tag)
	}
	sort.Strings(sorted)
	return strings.Join(sorted, ",")
}

// Restic runs the restic binary from PATH with a controlled environment.
// The machine identity travels on the command line as --host instead of
// through RESTIC_HOST: restic treats that variable as the default snapshot
// filter, which would silently hide every other machine.
type Restic struct {
	Repository      string
	PasswordCommand string
	Compression     string
	LimitUpload     int
	CacheDir        string
	Out             io.Writer
	ExtraEnv        []string
}

// newRestic builds a Restic from the configuration.
func newRestic(cfg *Config, out io.Writer) *Restic {
	return &Restic{
		Repository:      cfg.Repository,
		PasswordCommand: cfg.PasswordCommand,
		Compression:     cfg.Compression,
		LimitUpload:     cfg.LimitUpload,
		CacheDir:        cfg.CacheDir,
		Out:             out,
	}
}

func (r *Restic) writer() io.Writer {
	if r.Out == nil {
		return io.Discard
	}
	return r.Out
}

// resticCacheDir is the restic-specific subdirectory of the configured cache.
func (r *Restic) resticCacheDir() string {
	if r.CacheDir == "" {
		return ""
	}
	return filepath.Join(r.CacheDir, "restic")
}

// env is the child environment: the full process environment (restic shells
// out to ssh/sftp/pass, so PATH and friends must survive) with the RESTIC_*
// variables of this run appended as overrides. Later entries win, so ExtraEnv
// has the last word.
func (r *Restic) env() []string {
	env := os.Environ()
	env = append(env, r.overrideEnv()...)
	env = append(env, r.ExtraEnv...)
	return dedupEnv(env)
}

// overrideEnv lists the RESTIC_* variables this run sets.
func (r *Restic) overrideEnv() []string {
	var env []string
	add := func(key, value string) {
		if value != "" {
			env = append(env, key+"="+value)
		}
	}
	add("RESTIC_REPOSITORY", r.Repository)
	add("RESTIC_PASSWORD_COMMAND", r.PasswordCommand)
	add("RESTIC_COMPRESSION", r.Compression)
	add("RESTIC_CACHE_DIR", r.resticCacheDir())
	return env
}

// dedupEnv removes duplicate keys, keeping the last value at the position of
// the first occurrence. Entries without "=" are preserved as-is.
func dedupEnv(env []string) []string {
	index := make(map[string]int, len(env))
	out := make([]string, 0, len(env))
	for _, kv := range env {
		key, _, ok := strings.Cut(kv, "=")
		if !ok {
			out = append(out, kv)
			continue
		}
		if at, dup := index[key]; dup {
			out[at] = kv
			continue
		}
		index[key] = len(out)
		out = append(out, kv)
	}
	return out
}

// withLimitUpload appends --limit-upload for the configured rate.
func (r *Restic) withLimitUpload(args []string) []string {
	if r.LimitUpload <= 0 {
		return args
	}
	full := make([]string, 0, len(args)+2)
	full = append(full, args...)
	full = append(full, "--limit-upload", strconv.Itoa(r.LimitUpload))
	return full
}

func (r *Restic) command(args ...string) *exec.Cmd {
	cmd := exec.Command("restic", args...)
	cmd.Env = r.env()
	return cmd
}

// Run executes restic with stdout and stderr streamed to Out.
func (r *Restic) Run(args ...string) error {
	full := r.withLimitUpload(args)
	cmd := r.command(full...)
	cmd.Stdout = r.writer()
	cmd.Stderr = r.writer()
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("restic %s: %w", strings.Join(full, " "), err)
	}
	return nil
}

// Output executes restic and captures stdout; stderr is streamed to Out and the
// tail of it is embedded in the returned error.
func (r *Restic) Output(args ...string) ([]byte, error) {
	var stdout, stderr bytes.Buffer
	cmd := r.command(args...)
	cmd.Stdout = &stdout
	cmd.Stderr = io.MultiWriter(&stderr, r.writer())
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("restic %s: %w: %s", strings.Join(args, " "), err, lastLines(stderr.String(), 3))
	}
	return stdout.Bytes(), nil
}

// Snapshots lists snapshots matching the given restic filters. Without filters
// every host is returned: the machine identity is never exported as
// RESTIC_HOST, so restic applies no implicit host filter.
func (r *Restic) Snapshots(filters ...string) ([]Snapshot, error) {
	args := append([]string{"snapshots", "--json"}, filters...)
	data, err := r.Output(args...)
	if err != nil {
		return nil, err
	}
	if len(bytes.TrimSpace(data)) == 0 {
		return nil, nil
	}
	var snapshots []Snapshot
	if err := json.Unmarshal(data, &snapshots); err != nil {
		return nil, fmt.Errorf("restic snapshots --json: %w", err)
	}
	return snapshots, nil
}

// tagFilter renders tags the way restic wants them on the command line.
func tagFilter(tags []string) string {
	return strings.Join(tags, ",")
}

// newestSnapshotFor returns the newest snapshot carrying every given tag.
func newestSnapshotFor(snapshots []Snapshot, tags []string) *Snapshot {
	var newest *Snapshot
	for i := range snapshots {
		if !snapshots[i].HasTags(tags) {
			continue
		}
		if newest == nil || snapshots[i].Time.After(newest.Time) {
			newest = &snapshots[i]
		}
	}
	return newest
}

// lastLines returns at most n trailing non-empty lines of s.
func lastLines(s string, n int) string {
	trimmed := strings.TrimRight(s, "\n")
	if trimmed == "" {
		return ""
	}
	lines := strings.Split(trimmed, "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
}

// resticCommandLine renders an argument vector for previews and logs.
func resticCommandLine(args []string) string {
	return "restic " + strings.Join(args, " ")
}

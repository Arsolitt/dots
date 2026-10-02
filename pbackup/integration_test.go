package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// TestIntegrationLocalRepo exercises push, prune, check and pull against a
// throwaway local restic repository. It never touches the real repository and
// never depends on HOME.
func TestIntegrationLocalRepo(t *testing.T) {
	for _, tool := range []string{"restic", "rsync"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skipf("%s not installed", tool)
		}
	}
	clearRESTICHost(t)

	root := t.TempDir()
	source := filepath.Join(root, "data")
	writeFixture(t, source)
	repository := filepath.Join(root, "repo")
	if err := os.MkdirAll(repository, 0o755); err != nil {
		t.Fatalf("mkdir repo: %v", err)
	}

	cfg := &Config{
		Repository:      repository,
		PasswordCommand: "echo testpass",
		Host:            "gtest",
		Compression:     "auto",
		Notify:          notifyOff,
		CacheDir:        filepath.Join(root, "cache"),
		StateDir:        filepath.Join(root, "state"),
		Retention:       map[string]Retention{"data": {KeepLast: 2}},
		Targets: []Target{{
			Name: "fixture",
			Path: source,
			Tags: []string{"fixture", "data"},
		}},
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("Validate: %v", err)
	}

	var out bytes.Buffer
	restic := newRestic(cfg, &out)
	if err := runInit(cfg, nil, &out, &out); err != nil {
		t.Fatalf("runInit: %v\n%s", err, out.String())
	}
	if !strings.Contains(out.String(), "✅ Репозиторий инициализирован") {
		t.Errorf("init output:\n%s", out.String())
	}
	out.Reset()
	if err := runInit(cfg, nil, &out, &out); err != nil {
		t.Fatalf("runInit(second): %v\n%s", err, out.String())
	}
	if !strings.Contains(out.String(), "✅ Репозиторий уже инициализирован") {
		t.Errorf("second init must be a no-op:\n%s", out.String())
	}

	// push creates exactly one snapshot carrying every target tag.
	out.Reset()
	if err := runPush(cfg, nil, &out, &out); err != nil {
		t.Fatalf("runPush: %v\n%s", err, out.String())
	}
	if !strings.Contains(out.String(), "🎉 Все бэкапы выполнены успешно!") {
		t.Errorf("push output missing success line:\n%s", out.String())
	}
	snapshots, err := restic.Snapshots()
	if err != nil {
		t.Fatalf("Snapshots: %v", err)
	}
	if len(snapshots) != 1 {
		t.Fatalf("got %d snapshots, want 1\n%s", len(snapshots), out.String())
	}
	if !snapshots[0].HasTags([]string{"fixture", "data"}) {
		t.Errorf("snapshot tags = %v, want fixture+data", snapshots[0].Tags)
	}
	if snapshots[0].Host != "gtest" {
		t.Errorf("snapshot host = %q, want gtest", snapshots[0].Host)
	}

	// Nothing is stale while the config still knows the tag set.
	out.Reset()
	if err := runPrune(cfg, nil, &out, &out); err != nil {
		t.Fatalf("runPrune: %v\n%s", err, out.String())
	}
	if !strings.Contains(out.String(), "Устаревших снапшотов не найдено") {
		t.Errorf("prune output:\n%s", out.String())
	}
	if strings.Contains(out.String(), "Превью forget") {
		t.Errorf("prune previewed a forget for an empty stale set:\n%s", out.String())
	}

	out.Reset()
	if err := runCheck(cfg, []string{"--read-data-subset", "1%"}, &out, &out); err != nil {
		t.Fatalf("runCheck: %v\n%s", err, out.String())
	}
	out.Reset()
	if err := runStatus(cfg, nil, &out, &out); err != nil {
		t.Fatalf("runStatus: %v\n%s", err, out.String())
	}
	if line := statusLine(t, out.String(), "Проверка:"); !strings.HasSuffix(line, " (успешно)") {
		t.Errorf("successful check not marked in status: %q", line)
	}

	out.Reset()
	if err := runSnapshots(cfg, nil, &out, &out); err != nil {
		t.Fatalf("runSnapshots: %v\n%s", err, out.String())
	}
	if !strings.Contains(out.String(), snapshots[0].ShortID) {
		t.Errorf("snapshots table misses the snapshot id:\n%s", out.String())
	}

	// pull restores into a fresh directory and the bytes must match.
	destination := filepath.Join(root, "restored")
	pullCfg := &Config{
		Repository:      cfg.Repository,
		PasswordCommand: cfg.PasswordCommand,
		Host:            cfg.Host,
		Compression:     cfg.Compression,
		Notify:          notifyOff,
		CacheDir:        cfg.CacheDir,
		StateDir:        cfg.StateDir,
		Retention:       cfg.Retention,
		Targets: []Target{{
			Name: "fixture",
			Path: destination,
			Tags: []string{"fixture", "data"},
		}},
	}
	if err := pullCfg.Validate(); err != nil {
		t.Fatalf("Validate(pull): %v", err)
	}
	out.Reset()
	if err := runPull(pullCfg, []string{"--yes"}, &out, &out); err != nil {
		t.Fatalf("runPull: %v\n%s", err, out.String())
	}
	compareTrees(t, source, destination)
	if _, err := os.Stat(filepath.Join(cfg.CacheDir, "restore", "fixture")); !os.IsNotExist(err) {
		t.Errorf("restore cache survived a successful pull: %v", err)
	}

	// The "data" category is not rescued, so no extra snapshot appeared.
	snapshots, err = restic.Snapshots()
	if err != nil {
		t.Fatalf("Snapshots: %v", err)
	}
	if len(snapshots) != 1 {
		t.Errorf("got %d snapshots after pull, want 1", len(snapshots))
	}

	state, err := LoadState(cfg.StateDir)
	if err != nil {
		t.Fatalf("LoadState: %v", err)
	}
	if state.LastPush.IsZero() || state.LastPull.IsZero() || state.LastCheck.IsZero() {
		t.Errorf("state = %+v, want push/pull/check timestamps", state)
	}
	if !state.LastPushOK {
		t.Error("LastPushOK = false after a successful push")
	}

	// A snapshot of another machine must be visible to the divergence check:
	// the machine identity travels as --host, never as RESTIC_HOST.
	if err := restic.Run("backup", source, "--host", "other", "--tag", "fixture", "--tag", "data"); err != nil {
		t.Fatalf("foreign backup: %v\n%s", err, out.String())
	}
	all, err := restic.Snapshots()
	if err != nil {
		t.Fatalf("Snapshots: %v", err)
	}
	if len(all) != 2 {
		t.Errorf("Snapshots returned %d snapshots, want 2", len(all))
	}
	local, err := restic.Snapshots("--host", cfg.Host)
	if err != nil {
		t.Fatalf("Snapshots(local): %v", err)
	}
	if len(local) != 1 {
		t.Errorf("Snapshots(gtest) returned %d snapshots, want 1", len(local))
	}

	out.Reset()
	if err := runPush(cfg, []string{"--no-forget"}, &out, &out); err != nil {
		t.Fatalf("runPush after foreign backup: %v\n%s", err, out.String())
	}
	if !strings.Contains(out.String(), "⚠️ репозиторий содержит более свежие снапшоты машины other") {
		t.Errorf("divergence warning missing:\n%s", out.String())
	}

	// A rescue snapshot tagged manual matches every target tag and is the
	// newest snapshot, yet pull must still restore the plain one.
	out.Reset()
	if err := runPull(pullCfg, []string{"--yes"}, &out, &out); err != nil {
		t.Fatalf("runPull(second): %v\n%s", err, out.String())
	}
	plainID := plannedSnapshotID(t, out.String())

	if err := restic.Run(rescueArgs(cfg, &cfg.Targets[0], source)...); err != nil {
		t.Fatalf("rescue snapshot: %v\n%s", err, out.String())
	}
	rescues, err := restic.Snapshots("--tag", "manual")
	if err != nil {
		t.Fatalf("Snapshots(manual): %v", err)
	}
	if len(rescues) != 1 {
		t.Fatalf("got %d manual snapshots, want 1", len(rescues))
	}
	if !rescues[0].HasTags([]string{"fixture", "data"}) {
		t.Fatalf("rescue snapshot tags = %v, want the target tags too", rescues[0].Tags)
	}
	if rescues[0].Host != cfg.Host {
		t.Errorf("rescue snapshot host = %q, want %q", rescues[0].Host, cfg.Host)
	}

	// The rescue point is the newest snapshot matching the tags, but status
	// must still report the last real backup.
	out.Reset()
	if err := runStatus(cfg, nil, &out, &out); err != nil {
		t.Fatalf("runStatus: %v\n%s", err, out.String())
	}
	if row := statusLine(t, out.String(), "fixture"); strings.Contains(row, rescues[0].ShortID) {
		t.Errorf("status reports the rescue point as the newest backup: %q", row)
	} else if !strings.Contains(row, plainID) {
		t.Errorf("status row %q does not mention the plain snapshot %s", row, plainID)
	}

	out.Reset()
	if err := runPull(pullCfg, []string{"--yes"}, &out, &out); err != nil {
		t.Fatalf("runPull(third): %v\n%s", err, out.String())
	}
	if planned := plannedSnapshotID(t, out.String()); planned != plainID {
		t.Errorf("pull planned snapshot %s, want the plain %s (manual %s must be skipped)", planned, plainID, rescues[0].ShortID)
	}

	// Pull is cross-machine: without --from the newest snapshot wins even when
	// it belongs to another host; with --from only that host is considered.
	if err := restic.Run("backup", source, "--host", "other", "--tag", "fixture", "--tag", "data"); err != nil {
		t.Fatalf("newer foreign backup: %v\n%s", err, out.String())
	}
	foreignNewest, err := newestOfHost(restic, "other", "fixture", "data")
	if err != nil {
		t.Fatalf("newestOfHost: %v", err)
	}
	out.Reset()
	if err := runPull(pullCfg, []string{"--yes"}, &out, &out); err != nil {
		t.Fatalf("runPull(cross-host): %v\n%s", err, out.String())
	}
	if planned := plannedSnapshotID(t, out.String()); planned != foreignNewest {
		t.Errorf("pull planned %s, want the newest foreign snapshot %s", planned, foreignNewest)
	}
	out.Reset()
	if err := runPull(pullCfg, []string{"--yes", "--from", cfg.Host}, &out, &out); err != nil {
		t.Fatalf("runPull(--from): %v\n%s", err, out.String())
	}
	if planned := plannedSnapshotID(t, out.String()); planned != plainID {
		t.Errorf("pull --from %s planned %s, want the local %s", cfg.Host, planned, plainID)
	}

	// Stale snapshots of another host are found only with --host.
	if err := restic.Run("backup", source, "--host", "legacy-host", "--tag", "obsolete", "--tag", "data"); err != nil {
		t.Fatalf("legacy stale backup: %v\n%s", err, out.String())
	}
	legacy, err := newestOfHost(restic, "legacy-host", "obsolete", "data")
	if err != nil {
		t.Fatalf("newestOfHost(legacy): %v", err)
	}
	out.Reset()
	if err := runPrune(cfg, nil, &out, &out); err != nil {
		t.Fatalf("runPrune: %v\n%s", err, out.String())
	}
	if strings.Contains(out.String(), legacy) {
		t.Errorf("default prune scanned another host:\n%s", out.String())
	}
	if !strings.Contains(out.String(), "Устаревших снапшотов не найдено") {
		t.Errorf("local prune found stale snapshots:\n%s", out.String())
	}
	out.Reset()
	if err := runPrune(cfg, []string{"--host", "legacy-host"}, &out, &out); err != nil {
		t.Fatalf("runPrune(--host): %v\n%s", err, out.String())
	}
	if !strings.Contains(out.String(), legacy) {
		t.Errorf("prune --host legacy-host did not list %s:\n%s", legacy, out.String())
	}

	// A successful prune marks the prune and the check row as successful.
	out.Reset()
	if err := runPrune(cfg, []string{"--apply"}, &out, &out); err != nil {
		t.Fatalf("runPrune(--apply): %v\n%s", err, out.String())
	}
	pruned, err := LoadState(cfg.StateDir)
	if err != nil {
		t.Fatalf("LoadState: %v", err)
	}
	if pruned.LastPrune.IsZero() || !pruned.LastPruneOK {
		t.Errorf("state after a successful prune = %+v, want a timestamp and ok", pruned)
	}
	out.Reset()
	if err := runStatus(cfg, nil, &out, &out); err != nil {
		t.Fatalf("runStatus: %v\n%s", err, out.String())
	}
	for _, prefix := range []string{"Последний pull:", "Очистка:", "Проверка:"} {
		if line := statusLine(t, out.String(), prefix); !strings.HasSuffix(line, " (успешно)") {
			t.Errorf("%s row = %q, want the success marker", prefix, line)
		}
	}

	// A pull that finds nothing to restore is recorded as a failure.
	ghostCfg := &Config{
		Repository:      cfg.Repository,
		PasswordCommand: cfg.PasswordCommand,
		Host:            cfg.Host,
		Compression:     cfg.Compression,
		Notify:          notifyOff,
		CacheDir:        cfg.CacheDir,
		StateDir:        cfg.StateDir,
		Retention:       cfg.Retention,
		Targets: []Target{{
			Name: "ghost",
			Path: filepath.Join(root, "ghost-dest"),
			Tags: []string{"ghost", "data"},
		}},
	}
	if err := ghostCfg.Validate(); err != nil {
		t.Fatalf("Validate(ghost): %v", err)
	}
	out.Reset()
	if err := runPull(ghostCfg, []string{"--yes"}, &out, &out); err == nil {
		t.Fatalf("pull without any snapshot succeeded, want failure\n%s", out.String())
	}
	ghosted, err := LoadState(cfg.StateDir)
	if err != nil {
		t.Fatalf("LoadState: %v", err)
	}
	if ghosted.LastPull.IsZero() {
		t.Error("failed pull did not stamp LastPull")
	}
	if ghosted.LastPullOK {
		t.Error("LastPullOK = true after a failed pull")
	}
	if _, err := os.Stat(filepath.Join(root, "ghost-dest")); !os.IsNotExist(err) {
		t.Errorf("failed pull created its destination: %v", err)
	}
	out.Reset()
	if err := runStatus(cfg, nil, &out, &out); err != nil {
		t.Fatalf("runStatus: %v\n%s", err, out.String())
	}
	if line := statusLine(t, out.String(), "Последний pull:"); !strings.HasSuffix(line, " (с ошибками)") {
		t.Errorf("pull row = %q, want the failure marker", line)
	}

	// A prune whose integrity check fails keeps its timestamp but is marked failed.
	out.Reset()
	if err := runPrune(cfg, []string{"--apply", "--read-data-subset", "not-a-subset"}, &out, &out); err == nil {
		t.Fatalf("prune with an invalid --read-data-subset succeeded, want failure\n%s", out.String())
	}
	afterBadPrune, err := LoadState(cfg.StateDir)
	if err != nil {
		t.Fatalf("LoadState: %v", err)
	}
	if afterBadPrune.LastPrune.IsZero() {
		t.Error("failed prune did not stamp LastPrune")
	}
	if afterBadPrune.LastPruneOK {
		t.Error("LastPruneOK = true after a failed prune")
	}
	out.Reset()
	if err := runStatus(cfg, nil, &out, &out); err != nil {
		t.Fatalf("runStatus: %v\n%s", err, out.String())
	}
	if line := statusLine(t, out.String(), "Очистка:"); !strings.HasSuffix(line, " (с ошибками)") {
		t.Errorf("prune row = %q, want the failure marker", line)
	}

	// A failed check keeps its timestamp but is marked as failed.
	brokenCfg := *cfg
	brokenCfg.Repository = filepath.Join(root, "missing-repo")

	// A dry run against a broken repository must fail loudly and change nothing.
	before, err := LoadState(cfg.StateDir)
	if err != nil {
		t.Fatalf("LoadState: %v", err)
	}
	out.Reset()
	if err := runPush(&brokenCfg, []string{"--dry-run"}, &out, &out); err == nil {
		t.Fatalf("dry-run push against a broken repository succeeded, want failure\n%s", out.String())
	}
	if !strings.Contains(out.String(), "❌ ОШИБКА при бэкапе") {
		t.Errorf("dry-run failure not reported:\n%s", out.String())
	}
	after, err := LoadState(cfg.StateDir)
	if err != nil {
		t.Fatalf("LoadState: %v", err)
	}
	if !after.LastPush.Equal(before.LastPush) || after.LastPushOK != before.LastPushOK {
		t.Errorf("dry run changed the push state: %+v -> %+v", before, after)
	}

	out.Reset()
	if err := runCheck(&brokenCfg, nil, &out, &out); err == nil {
		t.Fatalf("runCheck on a missing repository succeeded, want failure\n%s", out.String())
	}
	broken, err := LoadState(cfg.StateDir)
	if err != nil {
		t.Fatalf("LoadState: %v", err)
	}
	if broken.LastCheck.IsZero() {
		t.Error("failed check did not record its timestamp")
	}
	if broken.LastCheckOK {
		t.Error("LastCheckOK = true after a failed check")
	}
	out.Reset()
	if err := runStatus(cfg, nil, &out, &out); err != nil {
		t.Fatalf("runStatus: %v\n%s", err, out.String())
	}
	if line := statusLine(t, out.String(), "Проверка:"); !strings.HasSuffix(line, " (с ошибками)") {
		t.Errorf("failed check not marked in status: %q", line)
	}
}

// clearRESTICHost removes an ambient RESTIC_HOST: the CLI must not depend on
// it, and a leftover value would silently filter every restic listing.
func clearRESTICHost(t *testing.T) {
	t.Helper()
	previous, had := os.LookupEnv("RESTIC_HOST")
	if err := os.Unsetenv("RESTIC_HOST"); err != nil {
		t.Fatalf("unsetenv RESTIC_HOST: %v", err)
	}
	t.Cleanup(func() {
		if had {
			_ = os.Setenv("RESTIC_HOST", previous)
		}
	})
}

// newestOfHost returns the id of the newest snapshot of one host that carries
// every given tag.
func newestOfHost(restic *Restic, host string, tags ...string) (string, error) {
	snapshots, err := restic.Snapshots("--host", host, "--tag", tagFilter(tags))
	if err != nil {
		return "", err
	}
	newest := newestSnapshotFor(snapshots, tags)
	if newest == nil {
		return "", fmt.Errorf("no snapshot for host %s with tags %v", host, tags)
	}
	return newest.ShortID, nil
}

// statusLine returns the status output line starting with prefix.
func statusLine(t *testing.T, output, prefix string) string {
	t.Helper()
	for _, line := range strings.Split(output, "\n") {
		if strings.HasPrefix(line, prefix) {
			return strings.TrimRight(line, " ")
		}
	}
	t.Fatalf("no %q line in status output:\n%s", prefix, output)
	return ""
}

// plannedSnapshotID extracts the snapshot id from pull's plan output.
func plannedSnapshotID(t *testing.T, output string) string {
	t.Helper()
	const marker = "снапшот: "
	at := strings.LastIndex(output, marker)
	if at < 0 {
		t.Fatalf("no planned snapshot in pull output:\n%s", output)
	}
	rest := output[at+len(marker):]
	if end := strings.IndexByte(rest, '\n'); end >= 0 {
		rest = rest[:end]
	}
	return strings.TrimSpace(rest)
}

// writeFixture creates a small tree with nested directories.
func writeFixture(t *testing.T, dir string) {
	t.Helper()
	files := map[string]string{
		"notes.txt":       "hello backup\n",
		"sub/data.json":   `{"ok":true}`,
		"sub/deep/one.md": "# one\n",
	}
	for name, content := range files {
		path := filepath.Join(dir, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatalf("mkdir %s: %v", filepath.Dir(path), err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatalf("write %s: %v", path, err)
		}
	}
}

// compareTrees asserts that two directory trees hold identical files.
func compareTrees(t *testing.T, want, got string) {
	t.Helper()
	wantFiles := treeContents(t, want)
	gotFiles := treeContents(t, got)
	if !reflect.DeepEqual(wantFiles, gotFiles) {
		t.Errorf("restored tree mismatch:\nwant %v\ngot  %v", wantFiles, gotFiles)
	}
}

// treeContents maps relative file paths to their contents.
func treeContents(t *testing.T, root string) map[string]string {
	t.Helper()
	files := make(map[string]string)
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		files[relative] = string(data)
		return nil
	})
	if err != nil {
		t.Fatalf("walk %s: %v", root, err)
	}
	return files
}

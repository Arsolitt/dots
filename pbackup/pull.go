package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// Rescue modes for pull: snapshot the current destination before overwriting it.
const (
	rescueConfigs = "configs"
	rescueAlways  = "always"
	rescueNever   = "never"
)

const pullUsage = `Использование: pbackup pull [--yes] [--from HOST] [--verify] [--keep-cache] [--rescue MODE] [цель...]

Восстанавливает снапшоты в пути, заданные в конфиге.

  --yes          не спрашивать подтверждение
  --from HOST    взять снапшоты указанной машины
  --verify       проверять содержимое при восстановлении (restic restore --verify)
  --keep-cache   не удалять временный каталог восстановления
  --rescue MODE  страховочный снапшот текущего состояния: configs|always|never
                 (по умолчанию configs — только категория configs)
`

// stdinReader is the source of the interactive confirmation.
var stdinReader io.Reader = os.Stdin

func runPull(cfg *Config, args []string, out, errOut io.Writer) error {
	fs := flag.NewFlagSet("pull", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() { fmt.Fprint(errOut, pullUsage) }
	assumeYes := fs.Bool("yes", false, "не спрашивать подтверждение")
	from := fs.String("from", "", "машина-источник")
	verify := fs.Bool("verify", false, "проверять содержимое")
	keepCache := fs.Bool("keep-cache", false, "не удалять временный каталог")
	rescue := fs.String("rescue", rescueConfigs, "режим страховочного снапшота")
	if err := fs.Parse(args); err != nil {
		return err
	}
	switch *rescue {
	case rescueConfigs, rescueAlways, rescueNever:
	default:
		fmt.Fprint(errOut, pullUsage)
		return fmt.Errorf("неизвестный режим --rescue: %q", *rescue)
	}
	targets, err := selectTargets(cfg, fs.Args())
	if err != nil {
		return err
	}
	if len(targets) == 0 {
		return errors.New("в конфиге не описано ни одной цели")
	}
	restic := newRestic(cfg, out)

	type targetPlan struct {
		target   *Target
		snapshot *Snapshot
	}
	plans := make([]targetPlan, 0, len(targets))
	for _, target := range targets {
		// No host filter unless --from is given: pulling another machine's
		// snapshots onto this one is the whole point.
		filters := []string{"--tag", tagFilter(target.Tags)}
		if *from != "" {
			filters = append(filters, "--host", *from)
		}
		snapshots, err := restic.Snapshots(filters...)
		if err != nil {
			return err
		}
		plans = append(plans, targetPlan{target: target, snapshot: newestSnapshotFor(nonRescueSnapshots(snapshots), target.Tags)})
	}

	fmt.Fprintln(out, "⚠️  ВНИМАНИЕ! ⚠️")
	fmt.Fprintln(out, "Вы собираетесь восстановить данные из бэкапа.")
	fmt.Fprintln(out, "Существующие файлы будут ПЕРЕЗАПИСАНЫ.")
	fmt.Fprintln(out)
	fmt.Fprintln(out, "План восстановления:")
	for _, plan := range plans {
		destination := ExpandPath(plan.target.Path)
		if plan.snapshot == nil {
			fmt.Fprintf(out, "  %s → %s: ⚠️ снапшот не найден\n", plan.target.Name, destination)
			continue
		}
		fmt.Fprintf(out, "  %s → %s\n", plan.target.Name, destination)
		fmt.Fprintf(out, "      теги: %s; машина: %s; время: %s; снапшот: %s\n",
			plan.snapshot.TagSet(), plan.snapshot.Host,
			plan.snapshot.Time.Local().Format("2006-01-02 15:04:05"), plan.snapshot.ShortID)
	}
	fmt.Fprintln(out)

	if !*assumeYes {
		fmt.Fprint(out, "Вы уверены, что хотите продолжить? (Введите 'yes' для подтверждения): ")
		answer, err := bufio.NewReader(stdinReader).ReadString('\n')
		if err != nil && !errors.Is(err, io.EOF) {
			return err
		}
		if !strings.EqualFold(strings.TrimSpace(answer), "yes") {
			fmt.Fprintln(out, "Операция отменена.")
			return nil
		}
	}

	fmt.Fprintln(out, "Запуск восстановления...")
	failed := make([]string, 0, len(plans))
	for _, plan := range plans {
		if plan.snapshot == nil {
			fmt.Fprintf(out, "❌ ОШИБКА при восстановлении: %s (снапшот не найден)\n", plan.target.Name)
			failed = append(failed, plan.target.Name)
			continue
		}
		if err := pullTarget(cfg, restic, plan.target, plan.snapshot, *verify, *keepCache, *rescue, out); err != nil {
			fmt.Fprintf(out, "❌ ОШИБКА при восстановлении: %s (%v)\n", plan.target.Name, err)
			failed = append(failed, plan.target.Name)
			continue
		}
		fmt.Fprintf(out, "✅ Успешно: %s\n", plan.target.Name)
	}

	fmt.Fprintln(out, "=== Восстановление завершено ===")
	updateState(cfg, errOut, func(state *State) {
		state.LastPull = time.Now()
		state.LastPullOK = len(failed) == 0
	})
	for _, name := range failed {
		_ = logLine(cfg.StateDir, "pull: FAILED %s", name)
	}
	_ = logLine(cfg.StateDir, "pull: целей=%d, ошибок=%d", len(plans), len(failed))
	if len(failed) > 0 {
		fmt.Fprintf(out, "⚠️ Всего ошибок: %d\n", len(failed))
		notifyFailure(cfg, "Восстановление", fmt.Sprintf("Ошибки (%d): %s", len(failed), strings.Join(failed, ", ")))
		return fmt.Errorf("восстановление завершилось с ошибками: %s", strings.Join(failed, ", "))
	}
	fmt.Fprintln(out, "🎉 Все данные успешно восстановлены!")
	notifySuccess(cfg, "Восстановление", fmt.Sprintf("Успешно: %d целей", len(plans)))
	return nil
}

// pullTarget rescues the current state, restores the snapshot into the cache
// directory and rsyncs the payload onto the configured destination.
func pullTarget(cfg *Config, restic *Restic, target *Target, snapshot *Snapshot, verify, keepCache bool, rescueMode string, out io.Writer) error {
	destination := ExpandPath(target.Path)

	if rescueEnabled(cfg, target, rescueMode) {
		if _, err := os.Stat(destination); err == nil {
			fmt.Fprintf(out, "--- Страховочный снапшот: %s ---\n", target.Name)
			if err := restic.Run(rescueArgs(cfg, target, destination)...); err != nil {
				return fmt.Errorf("страховочный снапшот: %w", err)
			}
		} else if !os.IsNotExist(err) {
			return err
		}
	}

	dir := filepath.Join(ExpandPath(cfg.CacheDir), "restore", target.Name)
	if err := os.RemoveAll(dir); err != nil {
		return err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	restoreArgs := []string{"restore", snapshot.ShortID, "--target", dir, "--overwrite", "if-changed"}
	if verify {
		restoreArgs = append(restoreArgs, "--verify")
	}
	restoreArgs = append(restoreArgs, "--retry-lock", retryLock)
	if err := restic.Run(restoreArgs...); err != nil {
		return err
	}

	payload, err := restorePayloadPath(dir, *snapshot)
	if err != nil {
		return err
	}
	info, err := os.Stat(payload)
	if err != nil {
		return fmt.Errorf("восстановленный путь не найден: %s", payload)
	}
	if err := syncToDestination(payload, destination, info.IsDir(), out); err != nil {
		return err
	}

	if !keepCache {
		if err := os.RemoveAll(dir); err != nil {
			fmt.Fprintf(out, "⚠️ не удалось очистить кэш %s: %v\n", dir, err)
		}
	}
	return nil
}

// rescueArgs is the safety snapshot taken before a destination is overwritten.
// It carries the target tags plus `manual`, which marks it as a rescue point.
func rescueArgs(cfg *Config, target *Target, destination string) []string {
	args := []string{"backup", destination, "--host", cfg.Host, "--tag", "manual"}
	for _, tag := range target.Tags {
		args = append(args, "--tag", tag)
	}
	return append(args, "--retry-lock", retryLock)
}

// nonRescueSnapshots drops rescue points from a snapshot list. Snapshots tagged
// `manual` are what pull saves before overwriting a destination, so they are
// never a restore source and never count as a target's newest backup.
func nonRescueSnapshots(snapshots []Snapshot) []Snapshot {
	sources := make([]Snapshot, 0, len(snapshots))
	for _, snapshot := range snapshots {
		if snapshot.HasTag("manual") {
			continue
		}
		sources = append(sources, snapshot)
	}
	return sources
}

// rescueEnabled decides whether the current destination is snapshotted first.
func rescueEnabled(cfg *Config, target *Target, mode string) bool {
	switch mode {
	case rescueAlways:
		return true
	case rescueNever:
		return false
	default:
		return target.Category(cfg) == "configs"
	}
}

// restorePayloadPath maps the first backed-up path of a snapshot to its
// location inside the restore target directory.
func restorePayloadPath(dir string, snapshot Snapshot) (string, error) {
	if len(snapshot.Paths) == 0 {
		return "", fmt.Errorf("снапшот %s не содержит путей", snapshot.ShortID)
	}
	return filepath.Join(dir, strings.TrimPrefix(snapshot.Paths[0], "/")), nil
}

// syncToDestination copies the restored payload onto the destination path.
func syncToDestination(src, destination string, isDir bool, out io.Writer) error {
	archive := rsyncArchiveFlag()
	if isDir {
		if err := os.MkdirAll(destination, 0o755); err != nil {
			return err
		}
		return runRsync(archive, src+string(os.PathSeparator), destination+string(os.PathSeparator), out)
	}
	if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
		return err
	}
	return runRsync(archive, src, destination, out)
}

// rsyncArchiveFlag keeps ACLs on Linux and extended attributes on macOS.
func rsyncArchiveFlag() string {
	if runtime.GOOS == "darwin" {
		return "-aE"
	}
	return "-aX"
}

func runRsync(archive, src, destination string, out io.Writer) error {
	cmd := exec.Command("rsync", archive, src, destination)
	cmd.Stdout = out
	cmd.Stderr = out
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("rsync %s %s %s: %w", archive, src, destination, err)
	}
	return nil
}

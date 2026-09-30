package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

const pushUsage = `Использование: backup push [--dry-run] [--no-forget] [--no-lint] [цель...]

Создаёт снапшоты всех (или указанных) целей и применяет политику хранения.

  --dry-run    показать, что будет сделано, ничего не менять
  --no-forget  не применять политику хранения
  --no-lint    не проверять коллизии имён файлов (регистр/Unicode)
`

func runPush(cfg *Config, args []string, out, errOut io.Writer) error {
	fs := flag.NewFlagSet("push", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() { fmt.Fprint(errOut, pushUsage) }
	dryRun := fs.Bool("dry-run", false, "ничего не менять")
	noForget := fs.Bool("no-forget", false, "не применять политику хранения")
	noLint := fs.Bool("no-lint", false, "пропустить проверку коллизий имён")
	if err := fs.Parse(args); err != nil {
		return err
	}
	targets, err := selectTargets(cfg, fs.Args())
	if err != nil {
		return err
	}
	if len(targets) == 0 {
		return errors.New("в конфиге не описано ни одной цели")
	}
	names := targetNames(targets)
	now := time.Now()
	restic := newRestic(cfg, out)

	// 1) Guard against files that collide on a case-insensitive filesystem:
	// such a snapshot cannot be restored faithfully on macOS.
	if !*noLint {
		collisions, err := lintCollisions(cfg, targets)
		if err != nil {
			return fmt.Errorf("проверка коллизий имён: %w", err)
		}
		if len(collisions) > 0 {
			printCollisions(out, collisions)
			return errors.New("найдены коллизии имён файлов (регистр/Unicode); исправьте их или запустите с --no-lint")
		}
	}

	// 2) Another machine may have pushed newer data that this one has not seen;
	// this requires listing every host, which is the default now that the
	// machine identity travels as --host and not as RESTIC_HOST.
	state, err := LoadState(cfg.StateDir)
	if err != nil {
		fmt.Fprintf(errOut, "⚠️ не удалось прочитать состояние: %v\n", err)
		state = &State{}
	}
	snapshots, err := restic.Snapshots()
	if err != nil {
		fmt.Fprintf(errOut, "⚠️ не удалось получить список снапшотов: %v\n", err)
	} else if foreign := newerForeignSnapshot(snapshots, cfg.Host, state.LastPush); foreign != nil {
		fmt.Fprintf(out, "⚠️ репозиторий содержит более свежие снапшоты машины %s (%s) — возможно, правки не синкануты на эту машину\n",
			foreign.Host, foreign.Time.Local().Format("2006-01-02 15:04"))
	}

	// 3) Backup every selected target; a failure never aborts the others.
	failed := make([]string, 0, len(targets))
	for _, target := range targets {
		path := ExpandPath(target.Path)
		fmt.Fprintf(out, "--- Начинаю бэкап: %s ---\n", target.Name)
		if _, err := os.Stat(path); err != nil {
			fmt.Fprintf(out, "⚠️ Пропускаю %s: путь недоступен: %s\n", target.Name, path)
			continue
		}
		if err := restic.Run(backupArgs(cfg, target, path, *dryRun)...); err != nil {
			fmt.Fprintf(out, "❌ ОШИБКА при бэкапе: %s\n", target.Name)
			failed = append(failed, target.Name)
			continue
		}
		fmt.Fprintf(out, "✅ Успешно: %s\n", target.Name)
	}

	// 4) Retention runs per category, never per target: snapshots of the same
	// category share one policy.
	if !*noForget {
		categories := selectedCategories(cfg, targets)
		fmt.Fprintln(out, "Очистка (forget/prune):")
		for _, category := range categories {
			if len(retentionFlags(cfg.Retention[category])) == 0 {
				fmt.Fprintf(out, "⚠️ для категории %s не заданы правила хранения, пропускаю\n", category)
				continue
			}
			args := forgetArgs(category, cfg.Retention[category])
			if *dryRun {
				fmt.Fprintf(out, "🔍 DRY-RUN: %s\n", resticCommandLine(append(args, "--dry-run")))
				continue
			}
			if err := restic.Run(args...); err != nil {
				fmt.Fprintf(out, "❌ ОШИБКА при очистке: %s\n", category)
				failed = append(failed, "forget:"+category)
				continue
			}
			fmt.Fprintf(out, "✅ Очищено: %s\n", category)
		}
	}

	// 5) State and notifications. A dry run must leave no trace, yet still
	// report failures honestly.
	if *dryRun {
		fmt.Fprintln(out, "🔍 DRY-RUN: репозиторий и состояние не изменялись.")
		if len(failed) > 0 {
			fmt.Fprintf(out, "⚠️ Всего ошибок: %d\n", len(failed))
			return fmt.Errorf("бэкап завершился с ошибками: %s", strings.Join(failed, ", "))
		}
		return nil
	}
	updateState(cfg, errOut, func(state *State) {
		state.LastPush = now
		state.LastPushOK = len(failed) == 0
	})
	for _, name := range failed {
		_ = logLine(cfg.StateDir, "push: FAILED %s", name)
	}
	_ = logLine(cfg.StateDir, "push: targets=%s, ошибок=%d", strings.Join(names, ","), len(failed))
	if len(failed) > 0 {
		fmt.Fprintf(out, "⚠️ Всего ошибок: %d\n", len(failed))
		notifyFailure(cfg, "Бэкап", fmt.Sprintf("Ошибки (%d): %s", len(failed), strings.Join(failed, ", ")))
		return fmt.Errorf("бэкап завершился с ошибками: %s", strings.Join(failed, ", "))
	}
	fmt.Fprintln(out, "🎉 Все бэкапы выполнены успешно!")
	notifySuccess(cfg, "Бэкап", fmt.Sprintf("Успешно: %s", strings.Join(names, ", ")))
	return nil
}

// backupArgs is the restic invocation for one target. The machine identity is
// passed explicitly: RESTIC_HOST is never exported, because restic would then
// treat it as the default filter for snapshot listings.
func backupArgs(cfg *Config, target *Target, path string, dryRun bool) []string {
	args := []string{"backup", path, "--host", cfg.Host}
	for _, tag := range target.Tags {
		args = append(args, "--tag", tag)
	}
	for _, pattern := range target.AllExcludes(cfg) {
		args = append(args, "--exclude", pattern)
	}
	if dryRun {
		args = append(args, "--dry-run")
	}
	return append(args, "--retry-lock", retryLock)
}

// forgetArgs is the retention command of one category. It deliberately carries
// no host filter: retention must thin every machine's lineage, including host
// values left over from before a migration.
func forgetArgs(category string, retention Retention) []string {
	args := []string{"forget", "--group-by", "host,tags", "--tag", category}
	args = append(args, retentionFlags(retention)...)
	return append(args, "--retry-lock", retryLock)
}

// targetNames returns the target names in order.
func targetNames(targets []*Target) []string {
	names := make([]string, 0, len(targets))
	for _, target := range targets {
		names = append(names, target.Name)
	}
	return names
}

// selectedCategories returns the distinct retention categories of the targets.
func selectedCategories(cfg *Config, targets []*Target) []string {
	seen := make(map[string]bool, len(targets))
	categories := make([]string, 0, len(targets))
	for _, target := range targets {
		category := target.Category(cfg)
		if category == "" || seen[category] {
			continue
		}
		seen[category] = true
		categories = append(categories, category)
	}
	sort.Strings(categories)
	return categories
}

// retentionFlags renders the keep-* flags of a policy; zero counters are
// omitted because restic reads them as "keep none".
func retentionFlags(retention Retention) []string {
	var flags []string
	add := func(name string, value int) {
		if value > 0 {
			flags = append(flags, name, strconv.Itoa(value))
		}
	}
	add("--keep-last", retention.KeepLast)
	add("--keep-daily", retention.KeepDaily)
	add("--keep-weekly", retention.KeepWeekly)
	add("--keep-monthly", retention.KeepMonthly)
	add("--keep-yearly", retention.KeepYearly)
	return flags
}

// newerForeignSnapshot returns the newest snapshot of another host that was
// taken after the given moment; with a zero moment every foreign snapshot counts.
func newerForeignSnapshot(snapshots []Snapshot, host string, after time.Time) *Snapshot {
	var newest *Snapshot
	for i := range snapshots {
		snapshot := snapshots[i]
		if snapshot.Host == host {
			continue
		}
		if !after.IsZero() && !snapshot.Time.After(after) {
			continue
		}
		if newest == nil || snapshot.Time.After(newest.Time) {
			newest = &snapshots[i]
		}
	}
	return newest
}

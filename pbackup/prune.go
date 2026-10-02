package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

const pruneUsage = `Использование: pbackup prune [--apply] [--read-data-subset PCT] [--host NAME]

Удаляет снапшоты текущей машины, чьи теги больше не описаны в конфиге.
Снапшоты без тегов и снапшоты с тегом manual не трогаются никогда.

  --apply                    выполнить удаление (по умолчанию только показать)
  --read-data-subset PCT     доля проверяемых данных для restic check (по умолчанию 1%,
                             действует только вместе с --apply)
  --host NAME                сканировать снапшоты другого хоста (например, старого
                             имени машины); по умолчанию — текущая машина
`

func runPrune(cfg *Config, args []string, out, errOut io.Writer) error {
	fs := flag.NewFlagSet("prune", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() { fmt.Fprint(errOut, pruneUsage) }
	apply := fs.Bool("apply", false, "выполнить удаление")
	readDataSubset := fs.String("read-data-subset", "1%", "доля данных для проверки")
	host := fs.String("host", "", "хост, чьи снапшоты сканировать")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() > 0 {
		fmt.Fprint(errOut, pruneUsage)
		return fmt.Errorf("лишние аргументы: %v", fs.Args())
	}

	scope := cfg.Host
	if *host != "" {
		scope = *host
	}
	restic := newRestic(cfg, out)
	// Only one machine's snapshots are considered at a time: another host's
	// config must never decide which snapshots are obsolete.
	snapshots, err := restic.Snapshots("--host", scope)
	if err != nil {
		return err
	}
	stale := staleSnapshots(snapshots, tagRegistry(cfg))
	if len(stale) == 0 {
		fmt.Fprintln(out, "✅ Устаревших снапшотов не найдено.")
	} else {
		fmt.Fprintf(out, "Найдено %d устаревших снапшотов:\n", len(stale))
		for _, snapshot := range stale {
			fmt.Fprintf(out, "  %s  %s  %s  [%s]\n", snapshot.ShortID,
				snapshot.Time.Local().Format("2006-01-02 15:04"), snapshot.Host, snapshot.TagSet())
		}
	}

	if !*apply {
		if flagSet(fs, "read-data-subset") {
			fmt.Fprintln(errOut, "⚠️ --read-data-subset действует только вместе с --apply и проигнорирован")
		}
		fmt.Fprintln(out)
		fmt.Fprintln(out, "🔍 DRY-RUN (ничего не удаляется).")
		if len(stale) > 0 {
			ids := staleIDs(stale)
			forgetArgs := append([]string{"forget"}, ids...)
			forgetArgs = append(forgetArgs, "--dry-run", "--prune")
			fmt.Fprintf(out, "Превью forget: %s\n", resticCommandLine(forgetArgs))
			if err := restic.Run(forgetArgs...); err != nil {
				return err
			}
		}
		fmt.Fprintln(out)
		fmt.Fprintln(out, "Для реального удаления запустите: pbackup prune --apply")
		return nil
	}

	if len(stale) > 0 {
		fmt.Fprintln(out, "⏳ forget + prune...")
		forgetArgs := append([]string{"forget"}, staleIDs(stale)...)
		forgetArgs = append(forgetArgs, "--prune", "--retry-lock", retryLock)
		if err := restic.Run(forgetArgs...); err != nil {
			notifyFailure(cfg, "Cleanup", "ОШИБКА при forget/prune")
			return fmt.Errorf("forget/prune: %w", err)
		}
	}
	// The deletion is done; whether the run as a whole succeeded depends on the
	// integrity check below, so the verdict is written later.
	updateState(cfg, errOut, func(state *State) {
		state.LastPrune = time.Now()
		state.LastPruneOK = false
	})

	fmt.Fprintln(out, "🔍 Проверка целостности репозитория (restic check)...")
	if err := restic.Run("check", "--retry-lock", retryLock, "--read-data-subset", *readDataSubset); err != nil {
		recordCheck(cfg, errOut, false)
		_ = logLine(cfg.StateDir, "prune: удалено=%d, check ОШИБКА", len(stale))
		notifyFailure(cfg, "Cleanup", "ОШИБКА: restic check не прошёл")
		return fmt.Errorf("check: %w", err)
	}
	recordCheck(cfg, errOut, true)
	updateState(cfg, errOut, func(state *State) { state.LastPruneOK = true })

	_ = logLine(cfg.StateDir, "prune: удалено=%d, проверено=%s", len(stale), *readDataSubset)
	fmt.Fprintln(out, "🎉 Cleanup завершён.")
	notifySuccess(cfg, "Cleanup", fmt.Sprintf("Удалено снапшотов: %d", len(stale)))
	return nil
}

// staleSnapshots selects snapshots whose tag set is no longer known to the
// config. Untagged and `manual` snapshots are always kept: they are the
// hand-made rescue points.
func staleSnapshots(snapshots []Snapshot, registry map[string]bool) []Snapshot {
	var stale []Snapshot
	for _, snapshot := range snapshots {
		tags := snapshot.TagSet()
		if tags == "" || snapshot.HasTag("manual") {
			continue
		}
		if registry[tags] {
			continue
		}
		stale = append(stale, snapshot)
	}
	return stale
}

// tagRegistry is the set of tag sets the current config still produces.
func tagRegistry(cfg *Config) map[string]bool {
	registry := make(map[string]bool, len(cfg.Targets))
	for i := range cfg.Targets {
		registry[tagSet(cfg.Targets[i].Tags)] = true
	}
	return registry
}

// staleIDs extracts the snapshot ids for a forget invocation.
func staleIDs(snapshots []Snapshot) []string {
	ids := make([]string, 0, len(snapshots))
	for _, snapshot := range snapshots {
		ids = append(ids, snapshot.ShortID)
	}
	return ids
}

// flagSet reports whether the named flag was given on the command line.
func flagSet(fs *flag.FlagSet, name string) bool {
	given := false
	fs.Visit(func(f *flag.Flag) {
		if f.Name == name {
			given = true
		}
	})
	return given
}

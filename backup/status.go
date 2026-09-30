package main

import (
	"flag"
	"fmt"
	"io"
	"sort"
	"text/tabwriter"
	"time"
)

const (
	statusUsage = `Использование: backup status

Показывает состояние последних запусков и сводку по репозиторию.
`

	snapshotsUsage = `Использование: backup snapshots [--all]

Список снапшотов (по умолчанию только текущей машины).

  --all  показать снапшоты всех машин
`
)

func runStatus(cfg *Config, args []string, out, errOut io.Writer) error {
	fs := flag.NewFlagSet("status", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() { fmt.Fprint(errOut, statusUsage) }
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() > 0 {
		fmt.Fprint(errOut, statusUsage)
		return fmt.Errorf("лишние аргументы: %v", fs.Args())
	}

	state, err := LoadState(cfg.StateDir)
	if err != nil {
		return err
	}
	fmt.Fprintf(out, "Хост:            %s\n", cfg.Host)
	fmt.Fprintf(out, "Репозиторий:     %s\n", cfg.Repository)
	fmt.Fprintf(out, "Последний push:  %s%s\n", formatTime(state.LastPush), resultSuffix(state.LastPush, state.LastPushOK))
	fmt.Fprintf(out, "Последний pull:  %s%s\n", formatTime(state.LastPull), resultSuffix(state.LastPull, state.LastPullOK))
	fmt.Fprintf(out, "Очистка:         %s%s\n", formatTime(state.LastPrune), resultSuffix(state.LastPrune, state.LastPruneOK))
	fmt.Fprintf(out, "Проверка:        %s%s\n", formatTime(state.LastCheck), resultSuffix(state.LastCheck, state.LastCheckOK))

	snapshots, err := newRestic(cfg, out).Snapshots()
	if err != nil {
		return err
	}
	fmt.Fprintf(out, "Всего снапшотов: %d\n", len(snapshots))
	if len(snapshots) == 0 {
		return nil
	}

	fmt.Fprintln(out)
	fmt.Fprintln(out, "Свежий снапшот по целям:")
	writer := tabwriter.NewWriter(out, 0, 0, 2, ' ', 0)
	fmt.Fprintln(writer, "ЦЕЛЬ\tВРЕМЯ\tМАШИНА\tСНАПШОТ")
	// Rescue points are excluded: the newest real backup is what matters here.
	data := nonRescueSnapshots(snapshots)
	for i := range cfg.Targets {
		target := &cfg.Targets[i]
		newest := newestSnapshotFor(data, target.Tags)
		if newest == nil {
			fmt.Fprintf(writer, "%s\t—\t—\t—\n", target.Name)
			continue
		}
		fmt.Fprintf(writer, "%s\t%s\t%s\t%s\n", target.Name,
			newest.Time.Local().Format("2006-01-02 15:04"), newest.Host, newest.ShortID)
	}
	return writer.Flush()
}

func runSnapshots(cfg *Config, args []string, out, errOut io.Writer) error {
	fs := flag.NewFlagSet("snapshots", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() { fmt.Fprint(errOut, snapshotsUsage) }
	all := fs.Bool("all", false, "показать снапшоты всех машин")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() > 0 {
		fmt.Fprint(errOut, snapshotsUsage)
		return fmt.Errorf("лишние аргументы: %v", fs.Args())
	}

	var (
		snapshots []Snapshot
		err       error
	)
	if *all {
		snapshots, err = newRestic(cfg, out).Snapshots()
	} else {
		snapshots, err = newRestic(cfg, out).Snapshots("--host", cfg.Host)
	}
	if err != nil {
		return err
	}
	if len(snapshots) == 0 {
		fmt.Fprintln(out, "Снапшотов не найдено.")
		return nil
	}
	sortSnapshotsNewestFirst(snapshots)

	writer := tabwriter.NewWriter(out, 0, 0, 2, ' ', 0)
	fmt.Fprintln(writer, "ВРЕМЯ\tМАШИНА\tТЕГИ\tСНАПШОТ")
	for _, snapshot := range snapshots {
		fmt.Fprintf(writer, "%s\t%s\t%s\t%s\n",
			snapshot.Time.Local().Format("2006-01-02 15:04"), snapshot.Host, snapshotTags(snapshot), snapshot.ShortID)
	}
	return writer.Flush()
}

// formatTime renders a state timestamp, or "никогда" when it was never set.
func formatTime(moment time.Time) string {
	if moment.IsZero() {
		return "никогда"
	}
	return moment.Local().Format("2006-01-02 15:04:05")
}

// resultSuffix annotates a state timestamp with the outcome of that run:
// an unset timestamp carries no verdict.
func resultSuffix(moment time.Time, ok bool) string {
	if moment.IsZero() {
		return ""
	}
	if ok {
		return " (успешно)"
	}
	return " (с ошибками)"
}

// sortSnapshotsNewestFirst orders snapshots by time, newest first.
func sortSnapshotsNewestFirst(snapshots []Snapshot) {
	sort.Slice(snapshots, func(i, j int) bool { return snapshots[i].Time.After(snapshots[j].Time) })
}

// snapshotTags renders tags for the compact table.
func snapshotTags(snapshot Snapshot) string {
	if tags := snapshot.TagSet(); tags != "" {
		return tags
	}
	return "—"
}

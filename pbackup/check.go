package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

const checkUsage = `Использование: pbackup check [--read-data-subset PCT]

Проверяет целостность репозитория (restic check).

  --read-data-subset PCT  дополнительно прочитать долю данных (например 1%, 5%)
`

func runCheck(cfg *Config, args []string, out, errOut io.Writer) error {
	fs := flag.NewFlagSet("check", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() { fmt.Fprint(errOut, checkUsage) }
	readDataSubset := fs.String("read-data-subset", "", "доля проверяемых данных")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() > 0 {
		fmt.Fprint(errOut, checkUsage)
		return fmt.Errorf("лишние аргументы: %v", fs.Args())
	}

	restic := newRestic(cfg, out)
	checkArgs := []string{"check", "--retry-lock", retryLock}
	if *readDataSubset != "" {
		checkArgs = append(checkArgs, "--read-data-subset", *readDataSubset)
	}
	fmt.Fprintln(out, "🔍 Проверка целостности репозитория (restic check)...")
	if err := restic.Run(checkArgs...); err != nil {
		recordCheck(cfg, errOut, false)
		_ = logLine(cfg.StateDir, "check: ОШИБКА")
		notifyFailure(cfg, "Проверка бэкапа", "ОШИБКА: restic check не прошёл")
		return fmt.Errorf("check: %w", err)
	}

	recordCheck(cfg, errOut, true)
	_ = logLine(cfg.StateDir, "check: ok")
	fmt.Fprintln(out, "✅ Проверка репозитория прошла успешно.")
	return nil
}

// recordCheck stores when a repository check ran and whether it passed.
func recordCheck(cfg *Config, errOut io.Writer, ok bool) {
	updateState(cfg, errOut, func(state *State) {
		state.LastCheck = time.Now()
		state.LastCheckOK = ok
	})
}

package main

import (
	"flag"
	"fmt"
	"io"
)

const unlockUsage = `Использование: pbackup unlock

Снимает устаревшие блокировки репозитория, оставленные убитыми процессами
restic. Живые блокировки не затрагиваются: restic обновляет свой замок каждые
5 минут, а замок с мёртвым PID снимается сразу.

push, prune и check делают это сами перед эксклюзивной операцией; команда
нужна, когда замок мешает прямо сейчас.
`

func runUnlock(cfg *Config, args []string, out, errOut io.Writer) error {
	fs := flag.NewFlagSet("unlock", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() { fmt.Fprint(errOut, unlockUsage) }
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() > 0 {
		fmt.Fprint(errOut, unlockUsage)
		return fmt.Errorf("лишние аргументы: %v", fs.Args())
	}

	restic := newRestic(cfg, out)
	removed, err := restic.Unlock()
	if err != nil {
		_ = logLine(cfg.StateDir, "unlock: ОШИБКА")
		return fmt.Errorf("unlock: %w", err)
	}
	if removed == 0 {
		fmt.Fprintln(out, "✅ Устаревших блокировок нет.")
		return nil
	}
	fmt.Fprintf(out, "🔓 Снято устаревших блокировок: %d\n", removed)
	_ = logLine(cfg.StateDir, "unlock: снято=%d", removed)
	return nil
}

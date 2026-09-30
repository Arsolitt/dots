package main

import (
	"flag"
	"fmt"
	"io"
)

const initUsage = `Использование: backup init

Инициализирует репозиторий restic, заданный в конфиге. Если репозиторий уже
существует, команда ничего не делает и завершается успешно.
`

func runInit(cfg *Config, args []string, out, errOut io.Writer) error {
	fs := flag.NewFlagSet("init", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() { fmt.Fprint(errOut, initUsage) }
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() > 0 {
		fmt.Fprint(errOut, initUsage)
		return fmt.Errorf("лишние аргументы: %v", fs.Args())
	}

	restic := newRestic(cfg, out)
	fmt.Fprintln(out, "Проверка репозитория...")
	// The probe stays quiet: a missing repository is the normal path here.
	if _, err := newRestic(cfg, io.Discard).Output("cat", "config"); err == nil {
		fmt.Fprintln(out, "✅ Репозиторий уже инициализирован")
		return nil
	}

	fmt.Fprintln(out, "Репозиторий не найден — создаю новый.")
	if err := restic.Run("init"); err != nil {
		return fmt.Errorf("инициализация репозитория: %w", err)
	}
	fmt.Fprintf(out, "✅ Репозиторий инициализирован: %s\n", cfg.Repository)
	fmt.Fprintln(out, "⚠️  Пароль (password_command) — единственный ключ к этим данным: без него бэкап не восстановить.")
	notifySuccess(cfg, "Бэкап", fmt.Sprintf("Репозиторий инициализирован: %s", cfg.Repository))
	return nil
}

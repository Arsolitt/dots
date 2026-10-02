package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/Arsolitt/dots/pbackup/internal/lint"
	"github.com/Arsolitt/dots/pbackup/internal/schedule"
)

const version = "0.1.0"

const mainUsage = `pbackup — обёртка над restic для домашних бэкапов.

Использование: pbackup [--config PATH] <команда> [флаги] [аргументы]

Команды:
  init        инициализировать репозиторий (no-op, если он уже есть)
  push        создать снапшоты и применить политику хранения
  pull        восстановить данные из снапшотов
  prune       удалить снапшоты с устаревшими тегами
  check       проверить целостность репозитория
  snapshots   список снапшотов
  status      состояние последних запусков
  cache       кэш восстановления (clean|path)
  lint        проверка коллизий имён файлов (регистр/Unicode)
  schedule    расписание (render|install|uninstall|status) [push|prune]
  version     версия
  help        эта справка

Глобальные флаги:
  --config PATH  конфиг (по умолчанию $PBACKUP_CONFIG или ~/.config/pbackup/config.toml)
`

func main() {
	err := run(os.Args[1:], os.Stdout, os.Stderr)
	if err == nil {
		return
	}
	if errors.Is(err, flag.ErrHelp) {
		os.Exit(0)
	}
	fmt.Fprintf(os.Stderr, "pbackup: %v\n", err)
	os.Exit(1)
}

// run is the whole CLI minus process exit, which keeps it testable.
func run(args []string, out, errOut io.Writer) error {
	configPath, rest, err := extractConfigFlag(args)
	if err != nil {
		return err
	}
	if len(rest) == 0 {
		fmt.Fprint(errOut, mainUsage)
		return errors.New("команда не указана")
	}
	command, commandArgs := rest[0], rest[1:]
	switch command {
	case "help", "-h", "--help":
		fmt.Fprint(out, mainUsage)
		return nil
	case "version":
		fmt.Fprintln(out, "pbackup "+version)
		return nil
	case "push", "pull", "prune", "check", "snapshots", "status", "cache", "lint", "schedule", "init":
		// Known commands below; they all need the configuration.
	default:
		fmt.Fprint(errOut, mainUsage)
		return fmt.Errorf("неизвестная команда: %q", command)
	}

	cfg, err := LoadConfig(configPath)
	if err != nil {
		return err
	}
	switch command {
	case "init":
		return runInit(cfg, commandArgs, out, errOut)
	case "push":
		return runPush(cfg, commandArgs, out, errOut)
	case "pull":
		return runPull(cfg, commandArgs, out, errOut)
	case "prune":
		return runPrune(cfg, commandArgs, out, errOut)
	case "check":
		return runCheck(cfg, commandArgs, out, errOut)
	case "snapshots":
		return runSnapshots(cfg, commandArgs, out, errOut)
	case "status":
		return runStatus(cfg, commandArgs, out, errOut)
	case "cache":
		return runCache(cfg, commandArgs, out, errOut)
	case "lint":
		return runLint(cfg, commandArgs, out, errOut)
	case "schedule":
		return runSchedule(cfg, commandArgs, out, errOut)
	}
	fmt.Fprint(errOut, mainUsage)
	return fmt.Errorf("неизвестная команда: %q", command)
}

// extractConfigFlag pulls the global --config flag out of the argument list.
func extractConfigFlag(args []string) (string, []string, error) {
	path := os.Getenv("PBACKUP_CONFIG")
	rest := make([]string, 0, len(args))
	for i := 0; i < len(args); i++ {
		arg := args[i]
		switch {
		case arg == "--":
			rest = append(rest, args[i:]...)
			i = len(args)
		case arg == "--config":
			if i+1 >= len(args) {
				return "", nil, errors.New("--config требует путь к файлу")
			}
			path = args[i+1]
			i++
		case strings.HasPrefix(arg, "--config="):
			path = strings.TrimPrefix(arg, "--config=")
		default:
			rest = append(rest, arg)
		}
	}
	if path == "" {
		path = DefaultConfigPath()
	}
	return path, rest, nil
}

const lintUsage = `Использование: pbackup lint [цель...]

Ищет имена файлов, которые совпадают без учёта регистра или после Unicode-
нормализации: такой снапшот нельзя достоверно восстановить на macOS.
`

func runLint(cfg *Config, args []string, out, errOut io.Writer) error {
	fs := flag.NewFlagSet("lint", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() { fmt.Fprint(errOut, lintUsage) }
	if err := fs.Parse(args); err != nil {
		return err
	}
	targets, err := selectTargets(cfg, fs.Args())
	if err != nil {
		return err
	}
	collisions, err := lintCollisions(cfg, targets)
	if err != nil {
		return fmt.Errorf("проверка коллизий имён: %w", err)
	}
	if len(collisions) == 0 {
		fmt.Fprintln(out, "✅ Коллизий имён не найдено.")
		return nil
	}
	for _, collision := range collisions {
		fmt.Fprintf(out, "%s: %s: %s (%s)\n", collision.Target, collision.Dir,
			strings.Join(collision.Names, ", "), collision.Kind)
	}
	return errors.New("найдены коллизии имён файлов (регистр/Unicode)")
}

const scheduleUsage = `Использование: pbackup schedule <render|install|uninstall|status> [push|prune]

Без указания задачи команда работает с обеими: push и еженедельный prune
(launchd на macOS, systemd timer на Linux). Время берётся из [schedule].
render ничего не устанавливает — это сухой прогон.
`

func runSchedule(cfg *Config, args []string, out, errOut io.Writer) error {
	fs := flag.NewFlagSet("schedule", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() { fmt.Fprint(errOut, scheduleUsage) }
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() == 0 {
		fmt.Fprint(errOut, scheduleUsage)
		return errors.New("не указано действие")
	}
	action := fs.Arg(0)
	switch action {
	case "render", "install", "uninstall", "status":
	default:
		fmt.Fprint(errOut, scheduleUsage)
		return fmt.Errorf("неизвестное действие: %q", action)
	}

	jobNames := []string{"push", "prune"}
	explicit := fs.NArg() > 1
	if explicit {
		jobNames = []string{fs.Arg(1)}
	}

	var failed []string
	for _, jobName := range jobNames {
		if !explicit {
			fmt.Fprintf(out, "=== %s ===\n", jobName)
		}
		job, err := scheduleJob(cfg, jobName)
		if err != nil {
			fmt.Fprintf(errOut, "❌ ОШИБКА расписания: %s (%v)\n", jobName, err)
			failed = append(failed, jobName)
			continue
		}
		if err := scheduleAction(action, job, out); err != nil {
			fmt.Fprintf(errOut, "❌ ОШИБКА расписания: %s (%v)\n", jobName, err)
			failed = append(failed, jobName)
		}
	}
	if len(failed) > 0 {
		return fmt.Errorf("расписание: ошибки для %s", strings.Join(failed, ", "))
	}
	return nil
}

// scheduleAction runs one schedule action for one job.
func scheduleAction(action string, job schedule.Job, out io.Writer) error {
	switch action {
	case "render":
		path, content, err := schedule.Render(job)
		if err != nil {
			return fmt.Errorf("рендер расписания: %w", err)
		}
		fmt.Fprintf(out, "Путь: %s\n%s", path, content)
		if !strings.HasSuffix(content, "\n") {
			fmt.Fprintln(out)
		}
		return nil
	case "install":
		if err := schedule.Install(job); err != nil {
			return fmt.Errorf("установка расписания: %w", err)
		}
		fmt.Fprintf(out, "✅ Расписание установлено: %s\n", job.Name)
		return nil
	case "uninstall":
		if err := schedule.Uninstall(job.Name); err != nil {
			return fmt.Errorf("удаление расписания: %w", err)
		}
		fmt.Fprintf(out, "✅ Расписание удалено: %s\n", job.Name)
		return nil
	case "status":
		status, err := schedule.Status(job.Name)
		if err != nil {
			return fmt.Errorf("статус расписания: %w", err)
		}
		fmt.Fprintln(out, status)
		return nil
	}
	return fmt.Errorf("неизвестное действие: %q", action)
}

// scheduleJob describes the launchd/systemd job of the given task.
func scheduleJob(cfg *Config, name string) (schedule.Job, error) {
	var (
		calendar schedule.Calendar
		args     []string
	)
	switch name {
	case "push":
		hour, minute, err := parseTimeOfDay(cfg.Schedule.PushTime)
		if err != nil {
			return schedule.Job{}, fmt.Errorf("schedule.push_time: %w", err)
		}
		calendar = schedule.Calendar{Hour: hour, Minute: minute, Weekday: -1}
		args = []string{"push"}
	case "prune":
		hour, minute, err := parseTimeOfDay(cfg.Schedule.PruneTime)
		if err != nil {
			return schedule.Job{}, fmt.Errorf("schedule.prune_time: %w", err)
		}
		weekday, err := parseWeekday(cfg.Schedule.PruneWeekday)
		if err != nil {
			return schedule.Job{}, fmt.Errorf("schedule.prune_weekday: %w", err)
		}
		calendar = schedule.Calendar{Hour: hour, Minute: minute, Weekday: weekday}
		args = []string{"prune", "--apply"}
	default:
		return schedule.Job{}, fmt.Errorf("неизвестная задача расписания: %q (push|prune)", name)
	}

	binary, err := os.Executable()
	if err != nil {
		return schedule.Job{}, err
	}
	return schedule.Job{
		Name:     "pbackup-" + name,
		Binary:   binary,
		Args:     args,
		LogPath:  filepath.Join(ExpandPath(cfg.StateDir), "schedule.log"),
		PathEnv:  schedulePathEnv(),
		Calendar: calendar,
	}, nil
}

// schedulePathEnv is the PATH handed to launchd/systemd, which do not inherit
// the login shell environment that restic and pass need.
func schedulePathEnv() string {
	if path := os.Getenv("PATH"); path != "" {
		return path
	}
	return "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
}

// parseTimeOfDay parses "15:04".
func parseTimeOfDay(value string) (int, int, error) {
	parsed, err := time.Parse("15:04", strings.TrimSpace(value))
	if err != nil {
		return 0, 0, fmt.Errorf("ожидается ЧЧ:ММ, получено %q", value)
	}
	return parsed.Hour(), parsed.Minute(), nil
}

// weekdayNumbers maps config day names to the schedule package numbering.
var weekdayNumbers = map[string]int{
	"sunday":    0,
	"monday":    1,
	"tuesday":   2,
	"wednesday": 3,
	"thursday":  4,
	"friday":    5,
	"saturday":  6,
}

// parseWeekday parses a config day name; 0 is Sunday, 6 is Saturday.
func parseWeekday(value string) (int, error) {
	name := strings.ToLower(strings.TrimSpace(value))
	if name == "" {
		return 0, errors.New("день недели не задан")
	}
	day, ok := weekdayNumbers[name]
	if !ok {
		return 0, fmt.Errorf("неизвестный день недели: %q", value)
	}
	return day, nil
}

// lintTrees describes the selected targets for the lint package.
func lintTrees(cfg *Config, targets []*Target) []lint.Tree {
	trees := make([]lint.Tree, 0, len(targets))
	for _, target := range targets {
		trees = append(trees, lint.Tree{
			Name:     target.Name,
			Root:     ExpandPath(target.Path),
			Excludes: target.AllExcludes(cfg),
		})
	}
	return trees
}

// lintCollisions runs the case/Unicode collision check over the targets.
func lintCollisions(cfg *Config, targets []*Target) ([]lint.Collision, error) {
	return lint.Check(lintTrees(cfg, targets))
}

// printCollisions prints one line per collision: "<target>: <dir>: <names>".
func printCollisions(out io.Writer, collisions []lint.Collision) {
	for _, collision := range collisions {
		fmt.Fprintf(out, "%s: %s: %s\n", collision.Target, collision.Dir, strings.Join(collision.Names, ", "))
	}
}

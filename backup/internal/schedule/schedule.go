// Package schedule installs and inspects the user-level jobs that run the
// backup CLI on a timer: a daily push and a weekly prune.
//
// On macOS a job is a launchd LaunchAgent
// (~/Library/LaunchAgents/com.arsolitt.<name>.plist). On Linux a job is a
// systemd user service plus timer (~/.config/systemd/user/<name>.service and
// <name>.timer). The exported functions dispatch on runtime.GOOS; rendering
// has no side effects so a job can be previewed and tested without touching
// the service manager.
package schedule

import (
	"encoding/xml"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

const (
	labelPrefix = "com.arsolitt."
	filePerm    = 0o644
	dirPerm     = 0o755
)

// weekdays maps Calendar.Weekday (0 = Sunday) to the three-letter form used
// in systemd OnCalendar expressions.
var weekdays = [...]string{"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}

// Calendar describes when a job runs. Weekday is -1 for every day and
// otherwise 0 (Sunday) through 6 (Saturday).
type Calendar struct {
	Hour    int
	Minute  int
	Weekday int
}

// Job is one scheduled unit owned by the backup CLI.
//
// Binary and LogPath may start with "~/" for the current user's home
// directory. PathEnv is exported to the job so restic and its helpers (pass,
// sftp) are found despite the minimal launchd/systemd environment.
type Job struct {
	Name     string
	Binary   string
	Args     []string
	LogPath  string
	PathEnv  string
	Calendar Calendar
}

// Render returns the path and content Install would write, without touching
// the filesystem. On macOS the path is the LaunchAgent plist. On Linux the
// path is the timer unit and content holds the service unit followed by the
// timer unit, each introduced by a "# --- <path> ---" header.
func Render(j Job) (string, string, error) {
	switch runtime.GOOS {
	case "darwin":
		content, err := renderLaunchd(j)
		if err != nil {
			return "", "", err
		}
		path, err := launchdPath(j.Name)
		if err != nil {
			return "", "", err
		}
		return path, content, nil
	case "linux":
		service, timer, err := renderSystemd(j)
		if err != nil {
			return "", "", err
		}
		dir, err := systemdDir()
		if err != nil {
			return "", "", err
		}
		servicePath := filepath.Join(dir, j.Name+".service")
		timerPath := filepath.Join(dir, j.Name+".timer")
		return timerPath, unitHeader(servicePath) + service + "\n" +
			unitHeader(timerPath) + timer, nil
	default:
		return "", "", fmt.Errorf("schedule: unsupported platform %q", runtime.GOOS)
	}
}

// Install writes the job's unit file(s) and loads them into the user's
// service manager.
func Install(j Job) error {
	switch runtime.GOOS {
	case "darwin":
		return installLaunchd(j)
	case "linux":
		return installSystemd(j)
	default:
		return fmt.Errorf("schedule: unsupported platform %q", runtime.GOOS)
	}
}

// Uninstall stops and removes the named job. A job that is not installed is
// not an error.
func Uninstall(name string) error {
	if err := validateName(name); err != nil {
		return err
	}
	switch runtime.GOOS {
	case "darwin":
		_, _ = runCommand("launchctl", "bootout", launchdDomain()+"/"+label(name))
		path, err := launchdPath(name)
		if err != nil {
			return err
		}
		return removeFile(path)
	case "linux":
		_, _ = runCommand("systemctl", "--user", "disable", "--now", name+".timer")
		dir, err := systemdDir()
		if err != nil {
			return err
		}
		for _, path := range []string{
			filepath.Join(dir, name+".service"),
			filepath.Join(dir, name+".timer"),
		} {
			if err := removeFile(path); err != nil {
				return err
			}
		}
		if _, err := runCommand("systemctl", "--user", "daemon-reload"); err != nil {
			return fmt.Errorf("schedule: daemon-reload: %w", err)
		}
		return nil
	default:
		return fmt.Errorf("schedule: unsupported platform %q", runtime.GOOS)
	}
}

// Status returns the platform service manager's view of the named job. A job
// that is not loaded is reported as an error on macOS; on Linux the systemd
// listing is annotated when the timer is not installed.
func Status(name string) (string, error) {
	if err := validateName(name); err != nil {
		return "", err
	}
	switch runtime.GOOS {
	case "darwin":
		return statusLaunchd(name)
	case "linux":
		return statusSystemd(name)
	default:
		return "", fmt.Errorf("schedule: unsupported platform %q", runtime.GOOS)
	}
}

// renderLaunchd renders the LaunchAgent plist for j. It never executes
// launchctl and never writes to disk.
func renderLaunchd(j Job) (string, error) {
	j = j.normalized()
	if err := j.validate(); err != nil {
		return "", err
	}

	var b strings.Builder
	b.WriteString(`<?xml version="1.0" encoding="UTF-8"?>` + "\n")
	b.WriteString(`<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">` + "\n")
	b.WriteString("<plist version=\"1.0\">\n")
	b.WriteString("<dict>\n")
	plistString(&b, 1, "Label", label(j.Name))
	plistStringArray(&b, 1, "ProgramArguments", append([]string{j.Binary}, j.Args...))
	plistCalendar(&b, 1, j.Calendar)
	plistEnvironment(&b, 1, j.PathEnv)
	plistString(&b, 1, "StandardOutPath", j.LogPath)
	plistString(&b, 1, "StandardErrorPath", j.LogPath)
	plistBool(&b, 1, "RunAtLoad", false)
	b.WriteString("</dict>\n</plist>\n")
	return b.String(), nil
}

// renderSystemd renders the .service and .timer unit bodies for j. It never
// executes systemctl and never writes to disk.
func renderSystemd(j Job) (string, string, error) {
	j = j.normalized()
	if err := j.validate(); err != nil {
		return "", "", err
	}

	execStart := systemdQuote(j.Binary)
	for _, arg := range j.Args {
		execStart += " " + systemdQuote(arg)
	}

	var service strings.Builder
	service.WriteString("[Service]\n")
	service.WriteString("Type=oneshot\n")
	service.WriteString("ExecStart=" + execStart + "\n")
	service.WriteString("Environment=" + systemdQuote("PATH="+j.PathEnv) + "\n")
	service.WriteString("StandardOutput=" + systemdQuote("append:"+j.LogPath) + "\n")
	service.WriteString("StandardError=" + systemdQuote("append:"+j.LogPath) + "\n")

	var timer strings.Builder
	timer.WriteString("[Timer]\n")
	timer.WriteString("OnCalendar=" + onCalendar(j.Calendar) + "\n")
	timer.WriteString("Persistent=true\n")
	timer.WriteString("\n[Install]\n")
	timer.WriteString("WantedBy=timers.target\n")

	return service.String(), timer.String(), nil
}

// onCalendar formats c as a systemd OnCalendar expression: "*-*-* HH:MM:00"
// for daily jobs and "Sun *-*-* HH:MM:00" for weekly jobs.
func onCalendar(c Calendar) string {
	day := "*-*-*"
	if c.Weekday >= 0 {
		day = weekdays[c.Weekday] + " *-*-*"
	}
	return fmt.Sprintf("%s %02d:%02d:00", day, c.Hour, c.Minute)
}

// unitHeader introduces a unit file inside Render's combined Linux content.
func unitHeader(path string) string { return "# --- " + path + " ---\n" }

// systemdQuote quotes value for a systemd command or assignment line when it
// contains characters systemd would otherwise split or interpret.
func systemdQuote(value string) string {
	if value == "" {
		return `""`
	}
	if !strings.ContainsAny(value, " \t\"'\\") {
		return value
	}
	var b strings.Builder
	b.WriteByte('"')
	for i := 0; i < len(value); i++ {
		if value[i] == '"' || value[i] == '\\' {
			b.WriteByte('\\')
		}
		b.WriteByte(value[i])
	}
	b.WriteByte('"')
	return b.String()
}

func plistString(b *strings.Builder, depth int, key, value string) {
	plistKey(b, depth, key)
	indent(b, depth)
	b.WriteString("<string>")
	escapeXML(b, value)
	b.WriteString("</string>\n")
}

func plistStringArray(b *strings.Builder, depth int, key string, values []string) {
	plistKey(b, depth, key)
	indent(b, depth)
	b.WriteString("<array>\n")
	for _, value := range values {
		indent(b, depth+1)
		b.WriteString("<string>")
		escapeXML(b, value)
		b.WriteString("</string>\n")
	}
	indent(b, depth)
	b.WriteString("</array>\n")
}

func plistInteger(b *strings.Builder, depth int, key string, value int) {
	plistKey(b, depth, key)
	indent(b, depth)
	fmt.Fprintf(b, "<integer>%d</integer>\n", value)
}

func plistBool(b *strings.Builder, depth int, key string, value bool) {
	plistKey(b, depth, key)
	indent(b, depth)
	if value {
		b.WriteString("<true/>\n")
	} else {
		b.WriteString("<false/>\n")
	}
}

func plistCalendar(b *strings.Builder, depth int, c Calendar) {
	plistKey(b, depth, "StartCalendarInterval")
	indent(b, depth)
	b.WriteString("<dict>\n")
	plistInteger(b, depth+1, "Hour", c.Hour)
	plistInteger(b, depth+1, "Minute", c.Minute)
	if c.Weekday >= 0 {
		plistInteger(b, depth+1, "Weekday", c.Weekday)
	}
	indent(b, depth)
	b.WriteString("</dict>\n")
}

func plistEnvironment(b *strings.Builder, depth int, pathEnv string) {
	plistKey(b, depth, "EnvironmentVariables")
	indent(b, depth)
	b.WriteString("<dict>\n")
	plistString(b, depth+1, "PATH", pathEnv)
	indent(b, depth)
	b.WriteString("</dict>\n")
}

func plistKey(b *strings.Builder, depth int, key string) {
	indent(b, depth)
	b.WriteString("<key>")
	escapeXML(b, key)
	b.WriteString("</key>\n")
}

func indent(b *strings.Builder, depth int) {
	b.WriteString(strings.Repeat("\t", depth))
}

// escapeXML writes s escaped for XML character data. A strings.Builder never
// fails, so EscapeText cannot return a write error here.
func escapeXML(b *strings.Builder, s string) {
	_ = xml.EscapeText(b, []byte(s))
}

// installLaunchd writes the LaunchAgent plist and bootstraps it into the
// current user's launchd domain.
func installLaunchd(j Job) error {
	j = j.normalized()
	content, err := renderLaunchd(j)
	if err != nil {
		return err
	}
	path, err := launchdPath(j.Name)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(j.LogPath), dirPerm); err != nil {
		return fmt.Errorf("schedule: create log directory: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(path), dirPerm); err != nil {
		return fmt.Errorf("schedule: create LaunchAgents directory: %w", err)
	}
	// A job that was bootstrapped before would otherwise keep running the old
	// plist with the old schedule.
	_, _ = runCommand("launchctl", "bootout", launchdDomain()+"/"+label(j.Name))
	if err := os.WriteFile(path, []byte(content), filePerm); err != nil {
		return fmt.Errorf("schedule: write %s: %w", path, err)
	}
	if _, err := runCommand("launchctl", "bootstrap", launchdDomain(), path); err != nil {
		return fmt.Errorf("schedule: bootstrap %s: %w", label(j.Name), err)
	}
	return nil
}

// statusLaunchd reports the loaded job from launchctl.
func statusLaunchd(name string) (string, error) {
	out, err := runCommand("launchctl", "print", launchdDomain()+"/"+label(name))
	if err != nil {
		return out, fmt.Errorf("schedule: launchd job %s is not loaded: %w", label(name), err)
	}
	return out, nil
}

// installSystemd writes the .service and .timer units, reloads systemd and
// enables the timer.
func installSystemd(j Job) error {
	j = j.normalized()
	service, timer, err := renderSystemd(j)
	if err != nil {
		return err
	}
	dir, err := systemdDir()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(j.LogPath), dirPerm); err != nil {
		return fmt.Errorf("schedule: create log directory: %w", err)
	}
	if err := os.MkdirAll(dir, dirPerm); err != nil {
		return fmt.Errorf("schedule: create systemd user directory: %w", err)
	}
	servicePath := filepath.Join(dir, j.Name+".service")
	timerPath := filepath.Join(dir, j.Name+".timer")
	if err := os.WriteFile(servicePath, []byte(service), filePerm); err != nil {
		return fmt.Errorf("schedule: write %s: %w", servicePath, err)
	}
	if err := os.WriteFile(timerPath, []byte(timer), filePerm); err != nil {
		return fmt.Errorf("schedule: write %s: %w", timerPath, err)
	}
	if _, err := runCommand("systemctl", "--user", "daemon-reload"); err != nil {
		return fmt.Errorf("schedule: daemon-reload: %w", err)
	}
	if _, err := runCommand("systemctl", "--user", "enable", "--now", j.Name+".timer"); err != nil {
		return fmt.Errorf("schedule: enable %s: %w", j.Name+".timer", err)
	}
	return nil
}

// statusSystemd reports the timer listing and notes when the unit is missing.
func statusSystemd(name string) (string, error) {
	unit := name + ".timer"
	out, err := runCommand("systemctl", "--user", "list-timers", unit, "--no-pager")
	if err != nil {
		return out, fmt.Errorf("schedule: systemd timer %s: %w", unit, err)
	}
	dir, err := systemdDir()
	if err == nil {
		if _, statErr := os.Stat(filepath.Join(dir, unit)); errors.Is(statErr, os.ErrNotExist) {
			out += "\n⚠️ Таймер " + unit + " не установлен"
		}
	}
	return out, nil
}

func launchdPath(name string) (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("schedule: resolve home directory: %w", err)
	}
	return filepath.Join(home, "Library", "LaunchAgents", label(name)+".plist"), nil
}

func systemdDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("schedule: resolve home directory: %w", err)
	}
	return filepath.Join(home, ".config", "systemd", "user"), nil
}

func label(name string) string { return labelPrefix + name }

func launchdDomain() string { return fmt.Sprintf("gui/%d", os.Getuid()) }

// normalized expands a leading "~" in the paths that must be absolute inside
// unit files.
func (j Job) normalized() Job {
	j.Binary = expandHome(j.Binary)
	j.LogPath = expandHome(j.LogPath)
	return j
}

func expandHome(path string) string {
	if path != "~" && !strings.HasPrefix(path, "~/") {
		return path
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return path
	}
	if path == "~" {
		return home
	}
	return filepath.Join(home, path[2:])
}

func (j Job) validate() error {
	if err := validateName(j.Name); err != nil {
		return err
	}
	if j.Binary == "" {
		return fmt.Errorf("schedule: job %q: binary must not be empty", j.Name)
	}
	if j.LogPath == "" {
		return fmt.Errorf("schedule: job %q: log path must not be empty", j.Name)
	}
	if j.PathEnv == "" {
		return fmt.Errorf("schedule: job %q: PATH environment must not be empty", j.Name)
	}
	if j.Calendar.Hour < 0 || j.Calendar.Hour > 23 {
		return fmt.Errorf("schedule: job %q: hour %d out of range 0-23", j.Name, j.Calendar.Hour)
	}
	if j.Calendar.Minute < 0 || j.Calendar.Minute > 59 {
		return fmt.Errorf("schedule: job %q: minute %d out of range 0-59", j.Name, j.Calendar.Minute)
	}
	if j.Calendar.Weekday < -1 || j.Calendar.Weekday > 6 {
		return fmt.Errorf("schedule: job %q: weekday %d out of range -1..6", j.Name, j.Calendar.Weekday)
	}
	return nil
}

func validateName(name string) error {
	if name == "" {
		return errors.New("schedule: job name must not be empty")
	}
	if name == "." || name == ".." || strings.ContainsAny(name, `/\`) {
		return fmt.Errorf("schedule: invalid job name %q", name)
	}
	return nil
}

func removeFile(path string) error {
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("schedule: remove %s: %w", path, err)
	}
	return nil
}

// runCommand executes name with args and returns its combined output. On
// failure the error carries the command line and whatever output it produced.
func runCommand(name string, args ...string) (string, error) {
	out, err := exec.Command(name, args...).CombinedOutput()
	trimmed := strings.TrimSpace(string(out))
	if err != nil {
		if trimmed != "" {
			return trimmed, fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, trimmed)
		}
		return "", fmt.Errorf("%s %s: %w", name, strings.Join(args, " "), err)
	}
	return trimmed, nil
}

package main

import (
	"strings"
	"testing"
)

func scheduleTestConfig(t *testing.T) *Config {
	t.Helper()
	return &Config{
		Host:     "mac",
		Notify:   notifyOff,
		StateDir: t.TempDir(),
		Schedule: Schedule{PushTime: "12:00", PruneWeekday: "sunday", PruneTime: "13:00"},
	}
}

// TestScheduleRenderBothJobs checks the default form: render touches both
// jobs and writes nothing (render is the dry run).
func TestScheduleRenderBothJobs(t *testing.T) {
	cfg := scheduleTestConfig(t)
	var out, errOut strings.Builder
	if err := runSchedule(cfg, []string{"render"}, &out, &errOut); err != nil {
		t.Fatalf("runSchedule(render): %v\n%s", err, errOut.String())
	}
	rendered := out.String()
	for _, want := range []string{"=== push ===", "=== prune ===", "pbackup-push", "pbackup-prune", "schedule.log"} {
		if !strings.Contains(rendered, want) {
			t.Errorf("render output misses %q:\n%s", want, rendered)
		}
	}
	if strings.Contains(errOut.String(), "ОШИБКА") {
		t.Errorf("unexpected error output:\n%s", errOut.String())
	}
}

// TestScheduleRenderSingleJob keeps the explicit form working.
func TestScheduleRenderSingleJob(t *testing.T) {
	cfg := scheduleTestConfig(t)
	var out, errOut strings.Builder
	if err := runSchedule(cfg, []string{"render", "prune"}, &out, &errOut); err != nil {
		t.Fatalf("runSchedule(render prune): %v\n%s", err, errOut.String())
	}
	rendered := out.String()
	if strings.Contains(rendered, "=== push ===") || strings.Contains(rendered, "pbackup-push") {
		t.Errorf("explicit prune render must not touch push:\n%s", rendered)
	}
	if !strings.Contains(rendered, "pbackup-prune") {
		t.Errorf("prune job missing:\n%s", rendered)
	}
}

func TestScheduleRejectsUnknownJobAndAction(t *testing.T) {
	cfg := scheduleTestConfig(t)
	var out, errOut strings.Builder
	if err := runSchedule(cfg, []string{"render", "bogus"}, &out, &errOut); err == nil {
		t.Error("unknown job accepted, want failure")
	}
	out.Reset()
	errOut.Reset()
	if err := runSchedule(cfg, []string{"bogus"}, &out, &errOut); err == nil {
		t.Error("unknown action accepted, want failure")
	}
	if !strings.Contains(errOut.String(), "Использование") {
		t.Errorf("usage not printed:\n%s", errOut.String())
	}
}

func TestScheduleJobCalendars(t *testing.T) {
	cfg := scheduleTestConfig(t)
	push, err := scheduleJob(cfg, "push")
	if err != nil {
		t.Fatalf("scheduleJob(push): %v", err)
	}
	if push.Calendar.Hour != 12 || push.Calendar.Minute != 0 || push.Calendar.Weekday != -1 {
		t.Errorf("push calendar = %+v, want 12:00 daily", push.Calendar)
	}
	if push.PathEnv == "" || push.LogPath == "" || push.Binary == "" {
		t.Errorf("push job = %+v, want binary, log path and PATH env", push)
	}
	prune, err := scheduleJob(cfg, "prune")
	if err != nil {
		t.Fatalf("scheduleJob(prune): %v", err)
	}
	if prune.Calendar.Hour != 13 || prune.Calendar.Minute != 0 || prune.Calendar.Weekday != 0 {
		t.Errorf("prune calendar = %+v, want Sunday 13:00", prune.Calendar)
	}
	if strings.Join(prune.Args, " ") != "prune --apply" {
		t.Errorf("prune args = %v, want prune --apply", prune.Args)
	}
	if _, err := scheduleJob(cfg, "bogus"); err == nil {
		t.Error("unknown job accepted, want failure")
	}
}

func TestScheduleTimeParsing(t *testing.T) {
	hour, minute, err := parseTimeOfDay("07:05")
	if err != nil {
		t.Fatalf("parseTimeOfDay: %v", err)
	}
	if hour != 7 || minute != 5 {
		t.Errorf("parseTimeOfDay(07:05) = %d:%d", hour, minute)
	}
	if _, _, err := parseTimeOfDay("7:05"); err != nil {
		t.Errorf("parseTimeOfDay(7:05) rejected: %v", err)
	}
	if _, _, err := parseTimeOfDay("25:00"); err == nil {
		t.Error("parseTimeOfDay(25:00) accepted, want failure")
	}
	if _, _, err := parseTimeOfDay(""); err == nil {
		t.Error("parseTimeOfDay(\"\") accepted, want failure")
	}
	day, err := parseWeekday("Sunday")
	if err != nil || day != 0 {
		t.Errorf("parseWeekday(Sunday) = %d, %v", day, err)
	}
	day, err = parseWeekday("saturday")
	if err != nil || day != 6 {
		t.Errorf("parseWeekday(saturday) = %d, %v", day, err)
	}
	if _, err := parseWeekday("среда"); err == nil {
		t.Error("unknown weekday accepted, want failure")
	}
	if _, err := parseWeekday(""); err == nil {
		t.Error("empty weekday accepted, want failure")
	}
}

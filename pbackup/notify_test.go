package main

import (
	"testing"
)

func TestEscapeNotify(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"plain", "hello", "hello"},
		{"quotes", `say "hi"`, `say \"hi\"`},
		{"backslash", `back\slash`, `back\\slash`},
		{"mixed", `a "b" \c`, `a \"b\" \\c`},
		{"cyrillic", `ошибка "бэкапа"`, `ошибка \"бэкапа\"`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := escapeNotify(tc.in); got != tc.want {
				t.Errorf("escapeNotify(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

func TestAppleScriptString(t *testing.T) {
	got := appleScriptString(`say "hi"`)
	if want := `"say \"hi\""`; got != want {
		t.Errorf("appleScriptString = %q, want %q", got, want)
	}
}

func TestNotifyDisabledModes(t *testing.T) {
	// No notification must be attempted in these cases, so no external
	// command is allowed to run.
	off := &Config{Notify: notifyOff, Host: "mac"}
	if notifyEnabledForFailure(off) {
		t.Error("failure notification enabled while off")
	}
	if notifyEnabledForSuccess(off) {
		t.Error("success notification enabled while off")
	}
	failures := &Config{Notify: notifyFailures, Host: "mac"}
	if !notifyEnabledForFailure(failures) {
		t.Error("failure notification disabled in failures mode")
	}
	if notifyEnabledForSuccess(failures) {
		t.Error("success notification enabled in failures mode")
	}
	always := &Config{Notify: notifyAlways, Host: "mac"}
	if !notifyEnabledForFailure(always) || !notifyEnabledForSuccess(always) {
		t.Error("always mode must notify on both outcomes")
	}
	var nilConfig *Config
	if notifyEnabledForFailure(nilConfig) || notifyEnabledForSuccess(nilConfig) {
		t.Error("nil config must not notify")
	}
}

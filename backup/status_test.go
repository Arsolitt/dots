package main

import (
	"testing"
	"time"
)

func TestResultSuffix(t *testing.T) {
	moment := time.Now()
	cases := []struct {
		name   string
		moment time.Time
		ok     bool
		want   string
	}{
		{"never ran", time.Time{}, true, ""},
		{"succeeded", moment, true, " (успешно)"},
		{"failed", moment, false, " (с ошибками)"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := resultSuffix(tc.moment, tc.ok); got != tc.want {
				t.Errorf("resultSuffix(%v, %v) = %q, want %q", tc.moment, tc.ok, got, tc.want)
			}
		})
	}
}

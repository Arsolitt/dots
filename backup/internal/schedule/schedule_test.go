package schedule

import (
	"encoding/xml"
	"runtime"
	"strings"
	"testing"
)

func testJob() Job {
	return Job{
		Name:    "push",
		Binary:  "/opt/homebrew/bin/backup",
		Args:    []string{"backup"},
		LogPath: "/var/log/backup/push.log",
		PathEnv: "/opt/homebrew/bin:/usr/bin:/bin",
		Calendar: Calendar{
			Hour:    12,
			Minute:  0,
			Weekday: -1,
		},
	}
}

func assertWellFormedXML(t *testing.T, content string) {
	t.Helper()
	var doc struct{ XMLName xml.Name }
	if err := xml.Unmarshal([]byte(content), &doc); err != nil {
		t.Fatalf("plist is not well-formed XML: %v\n%s", err, content)
	}
}

func TestRenderLaunchdDaily(t *testing.T) {
	content, err := renderLaunchd(testJob())
	if err != nil {
		t.Fatalf("renderLaunchd: %v", err)
	}

	for _, want := range []string{
		"<key>Label</key>\n\t<string>com.arsolitt.push</string>",
		"<key>ProgramArguments</key>\n\t<array>\n" +
			"\t\t<string>/opt/homebrew/bin/backup</string>\n" +
			"\t\t<string>backup</string>\n\t</array>",
		"<key>StartCalendarInterval</key>\n\t<dict>\n" +
			"\t\t<key>Hour</key>\n\t\t<integer>12</integer>\n" +
			"\t\t<key>Minute</key>\n\t\t<integer>0</integer>\n\t</dict>",
		"<key>EnvironmentVariables</key>\n\t<dict>\n" +
			"\t\t<key>PATH</key>\n" +
			"\t\t<string>/opt/homebrew/bin:/usr/bin:/bin</string>\n\t</dict>",
		"<key>StandardOutPath</key>\n\t<string>/var/log/backup/push.log</string>",
		"<key>StandardErrorPath</key>\n\t<string>/var/log/backup/push.log</string>",
		"<key>RunAtLoad</key>\n\t<false/>",
	} {
		if !strings.Contains(content, want) {
			t.Errorf("plist missing %q\n--- plist ---\n%s", want, content)
		}
	}
	if strings.Contains(content, "Weekday") {
		t.Errorf("daily plist must not pin a weekday:\n%s", content)
	}
	assertWellFormedXML(t, content)
}

func TestRenderLaunchdWeekly(t *testing.T) {
	job := testJob()
	job.Calendar = Calendar{Hour: 13, Minute: 30, Weekday: 3}

	content, err := renderLaunchd(job)
	if err != nil {
		t.Fatalf("renderLaunchd: %v", err)
	}
	for _, want := range []string{
		"\t\t<key>Hour</key>\n\t\t<integer>13</integer>",
		"\t\t<key>Minute</key>\n\t\t<integer>30</integer>",
		"\t\t<key>Weekday</key>\n\t\t<integer>3</integer>",
	} {
		if !strings.Contains(content, want) {
			t.Errorf("plist missing %q\n--- plist ---\n%s", want, content)
		}
	}
	assertWellFormedXML(t, content)
}

func TestRenderLaunchdEscapesPaths(t *testing.T) {
	job := testJob()
	job.Binary = "/tmp/a&b/backup"
	job.LogPath = "/tmp/a & b/<push>.log"

	content, err := renderLaunchd(job)
	if err != nil {
		t.Fatalf("renderLaunchd: %v", err)
	}
	for _, want := range []string{
		"<string>/tmp/a&amp;b/backup</string>",
		"<string>/tmp/a &amp; b/&lt;push&gt;.log</string>",
	} {
		if !strings.Contains(content, want) {
			t.Errorf("plist missing %q\n--- plist ---\n%s", want, content)
		}
	}
	assertWellFormedXML(t, content)
}

func TestRenderLaunchdExpandsHome(t *testing.T) {
	t.Setenv("HOME", "/home/tester")

	job := testJob()
	job.Binary = "~/bin/backup"
	job.LogPath = "~/.local/state/backup/logs/push.log"

	content, err := renderLaunchd(job)
	if err != nil {
		t.Fatalf("renderLaunchd: %v", err)
	}
	for _, want := range []string{
		"<string>/home/tester/bin/backup</string>",
		"<string>/home/tester/.local/state/backup/logs/push.log</string>",
	} {
		if !strings.Contains(content, want) {
			t.Errorf("plist missing %q\n--- plist ---\n%s", want, content)
		}
	}
}

func TestRenderSystemdDaily(t *testing.T) {
	service, timer, err := renderSystemd(testJob())
	if err != nil {
		t.Fatalf("renderSystemd: %v", err)
	}

	wantService := "[Service]\n" +
		"Type=oneshot\n" +
		"ExecStart=/opt/homebrew/bin/backup backup\n" +
		"Environment=PATH=/opt/homebrew/bin:/usr/bin:/bin\n" +
		"StandardOutput=append:/var/log/backup/push.log\n" +
		"StandardError=append:/var/log/backup/push.log\n"
	if service != wantService {
		t.Errorf("service unit = %q, want %q", service, wantService)
	}

	wantTimer := "[Timer]\n" +
		"OnCalendar=*-*-* 12:00:00\n" +
		"Persistent=true\n" +
		"\n[Install]\n" +
		"WantedBy=timers.target\n"
	if timer != wantTimer {
		t.Errorf("timer unit = %q, want %q", timer, wantTimer)
	}
}

func TestRenderSystemdQuotesArgs(t *testing.T) {
	job := testJob()
	job.Binary = "/opt/backup dir/backup"
	job.Args = []string{"backup", "--tag", "my tag"}

	service, _, err := renderSystemd(job)
	if err != nil {
		t.Fatalf("renderSystemd: %v", err)
	}
	want := `ExecStart="/opt/backup dir/backup" backup --tag "my tag"` + "\n"
	if !strings.Contains(service, want) {
		t.Errorf("service unit missing %q\n%s", want, service)
	}
}

func TestRenderSystemdOnCalendar(t *testing.T) {
	cases := []struct {
		name    string
		weekday int
		want    string
	}{
		{"daily", -1, "OnCalendar=*-*-* 09:05:00\n"},
		{"sunday", 0, "OnCalendar=Sun *-*-* 09:05:00\n"},
		{"monday", 1, "OnCalendar=Mon *-*-* 09:05:00\n"},
		{"wednesday", 3, "OnCalendar=Wed *-*-* 09:05:00\n"},
		{"saturday", 6, "OnCalendar=Sat *-*-* 09:05:00\n"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			job := testJob()
			job.Calendar = Calendar{Hour: 9, Minute: 5, Weekday: tc.weekday}

			_, timer, err := renderSystemd(job)
			if err != nil {
				t.Fatalf("renderSystemd: %v", err)
			}
			if !strings.Contains(timer, tc.want) {
				t.Errorf("timer unit missing %q\n%s", tc.want, timer)
			}
		})
	}
}

func TestRenderRejectsInvalidJobs(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(*Job)
	}{
		{"empty name", func(j *Job) { j.Name = "" }},
		{"slash in name", func(j *Job) { j.Name = "push/prune" }},
		{"empty binary", func(j *Job) { j.Binary = "" }},
		{"empty log path", func(j *Job) { j.LogPath = "" }},
		{"empty path env", func(j *Job) { j.PathEnv = "" }},
		{"hour above range", func(j *Job) { j.Calendar.Hour = 24 }},
		{"negative hour", func(j *Job) { j.Calendar.Hour = -1 }},
		{"minute above range", func(j *Job) { j.Calendar.Minute = 60 }},
		{"weekday above range", func(j *Job) { j.Calendar.Weekday = 7 }},
		{"weekday below range", func(j *Job) { j.Calendar.Weekday = -2 }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			job := testJob()
			tc.mutate(&job)

			if _, err := renderLaunchd(job); err == nil {
				t.Errorf("renderLaunchd accepted an invalid job")
			}
			if _, _, err := renderSystemd(job); err == nil {
				t.Errorf("renderSystemd accepted an invalid job")
			}
		})
	}
}

func TestRenderDispatchesOnPlatform(t *testing.T) {
	path, content, err := Render(testJob())
	switch runtime.GOOS {
	case "darwin":
		if err != nil {
			t.Fatalf("Render: %v", err)
		}
		if !strings.HasSuffix(path, "/Library/LaunchAgents/com.arsolitt.push.plist") {
			t.Errorf("path = %q, want a LaunchAgent plist", path)
		}
		if !strings.HasPrefix(content, "<?xml") {
			t.Errorf("content is not a plist:\n%s", content)
		}
	case "linux":
		if err != nil {
			t.Fatalf("Render: %v", err)
		}
		if !strings.HasSuffix(path, "/.config/systemd/user/push.timer") {
			t.Errorf("path = %q, want the systemd timer unit", path)
		}
		for _, want := range []string{"[Service]", "[Timer]", "OnCalendar="} {
			if !strings.Contains(content, want) {
				t.Errorf("content missing %q:\n%s", want, content)
			}
		}
	default:
		if err == nil {
			t.Fatalf("Render on %s: want an unsupported platform error", runtime.GOOS)
		}
	}
}

// Only invalid jobs reach Install here: validation runs before any launchctl
// or systemctl call, so no service manager is touched.
func TestInstallRejectsInvalidJob(t *testing.T) {
	for _, job := range []Job{
		{Name: ""},
		{Name: "push/prune"},
		{Name: "push", Binary: "/bin/backup", LogPath: ""},
	} {
		if err := Install(job); err == nil {
			t.Errorf("Install(%+v) = nil, want error", job)
		}
	}
}

func TestStatusRejectsInvalidName(t *testing.T) {
	for _, name := range []string{"", "..", "push/prune"} {
		if _, err := Status(name); err == nil {
			t.Errorf("Status(%q) = nil error, want error", name)
		}
	}
}

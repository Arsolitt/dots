package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// State is the persisted bookkeeping of the last runs.
type State struct {
	LastPush    time.Time `json:"last_push"`
	LastPull    time.Time `json:"last_pull"`
	LastPrune   time.Time `json:"last_prune"`
	LastCheck   time.Time `json:"last_check"`
	LastPushOK  bool      `json:"last_push_ok"`
	LastPullOK  bool      `json:"last_pull_ok"`
	LastPruneOK bool      `json:"last_prune_ok"`
	LastCheckOK bool      `json:"last_check_ok"`
}

func statePath(stateDir string) string {
	return filepath.Join(stateDir, "state.json")
}

// LoadState reads the state file; a missing file yields the zero state.
func LoadState(stateDir string) (*State, error) {
	if stateDir == "" {
		return &State{}, nil
	}
	data, err := os.ReadFile(statePath(stateDir))
	if err != nil {
		if os.IsNotExist(err) {
			return &State{}, nil
		}
		return nil, err
	}
	var state State
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, fmt.Errorf("state file %s: %w", statePath(stateDir), err)
	}
	return &state, nil
}

// SaveState atomically replaces the state file with mode 0600.
func SaveState(stateDir string, state *State) error {
	if stateDir == "" {
		return nil
	}
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	tmp, err := os.CreateTemp(stateDir, "state.json.tmp*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if err := tmp.Chmod(0o600); err != nil {
		tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpName, statePath(stateDir))
}

// updateState loads, mutates and saves the state, warning on I/O problems.
func updateState(cfg *Config, errOut io.Writer, mutate func(*State)) {
	state, err := LoadState(cfg.StateDir)
	if err != nil {
		fmt.Fprintf(errOut, "⚠️ не удалось прочитать состояние: %v\n", err)
		state = &State{}
	}
	mutate(state)
	if err := SaveState(cfg.StateDir, state); err != nil {
		fmt.Fprintf(errOut, "⚠️ не удалось сохранить состояние: %v\n", err)
	}
}

// logLine appends one timestamped line to <StateDir>/log.
func logLine(stateDir, format string, args ...any) error {
	if stateDir == "" {
		return nil
	}
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		return err
	}
	f, err := os.OpenFile(filepath.Join(stateDir, "log"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = fmt.Fprintf(f, "%s %s\n", time.Now().Format(time.RFC3339), fmt.Sprintf(format, args...))
	return err
}

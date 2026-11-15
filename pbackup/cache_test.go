package main

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestRemoveTreeReadOnlyDirs(t *testing.T) {
	root := t.TempDir()
	readonly := filepath.Join(root, "k8s", "1.35.0-linux-amd64")
	if err := os.MkdirAll(readonly, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(readonly, "etcd"), []byte("binary"), 0o555); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(readonly, 0o555); err != nil {
		t.Fatal(err)
	}
	if err := removeTree(root); err != nil {
		t.Fatalf("removeTree: %v", err)
	}
	if _, err := os.Stat(root); !os.IsNotExist(err) {
		t.Fatalf("tree still exists: %v", err)
	}
}

func TestCleanRestoreCacheReadOnlyDirs(t *testing.T) {
	cacheDir := t.TempDir()
	target := filepath.Join(cacheDir, "restore", "projects")
	readonly := filepath.Join(target, "home", "arsolitt", "k8s")
	if err := os.MkdirAll(readonly, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(readonly, "etcd"), []byte("binary"), 0o555); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(readonly, 0o555); err != nil {
		t.Fatal(err)
	}
	out := &bytes.Buffer{}
	if err := cleanRestoreCache(cacheDir, out); err != nil {
		t.Fatalf("cleanRestoreCache: %v", err)
	}
	if _, err := os.Stat(target); !os.IsNotExist(err) {
		t.Fatalf("restore cache directory survived the cleanup: %v", err)
	}
}

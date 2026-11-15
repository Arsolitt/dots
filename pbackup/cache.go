package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

const cacheUsage = `Использование: pbackup cache <clean|path>

  clean  удалить временные каталоги восстановления
  path   показать используемые пути кэша
`

func runCache(cfg *Config, args []string, out, errOut io.Writer) error {
	fs := flag.NewFlagSet("cache", flag.ContinueOnError)
	fs.SetOutput(errOut)
	fs.Usage = func() { fmt.Fprint(errOut, cacheUsage) }
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() == 0 {
		fmt.Fprint(errOut, cacheUsage)
		return fmt.Errorf("не указано действие")
	}
	cacheDir := ExpandPath(cfg.CacheDir)
	switch action := fs.Arg(0); action {
	case "clean":
		return cleanRestoreCache(cacheDir, out)
	case "path":
		fmt.Fprintf(out, "Кэш:              %s\n", cacheDir)
		fmt.Fprintf(out, "Кэш restic:       %s\n", filepath.Join(cacheDir, "restic"))
		fmt.Fprintf(out, "Восстановление:   %s\n", filepath.Join(cacheDir, "restore"))
		fmt.Fprintf(out, "Состояние:        %s\n", ExpandPath(cfg.StateDir))
		return nil
	default:
		fmt.Fprint(errOut, cacheUsage)
		return fmt.Errorf("неизвестное действие: %q", action)
	}
}

// cleanRestoreCache removes every per-target restore directory.
func cleanRestoreCache(cacheDir string, out io.Writer) error {
	root := filepath.Join(cacheDir, "restore")
	entries, err := os.ReadDir(root)
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Fprintf(out, "Нечего чистить: %s не существует.\n", root)
			return nil
		}
		return err
	}
	removed := 0
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		path := filepath.Join(root, entry.Name())
		if err := removeTree(path); err != nil {
			return err
		}
		fmt.Fprintf(out, "Удалено: %s\n", path)
		removed++
	}
	fmt.Fprintf(out, "Очищено каталогов: %d\n", removed)
	return nil
}

// removeTree deletes a restore cache tree. Snapshots preserve read-only
// directory modes (0555), so a plain os.RemoveAll cannot unlink their children
// and leaves the tree behind; chmod the directories writable first. Both the
// next pull and `pbackup cache clean` then start from an empty tree instead of
// inheriting the previous attempt's cache.
func removeTree(dir string) error {
	if err := os.RemoveAll(dir); err == nil {
		return nil
	}
	_ = os.Chmod(dir, 0o700)
	_ = filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err == nil && info.IsDir() {
			_ = os.Chmod(path, 0o700)
		}
		return nil
	})
	return os.RemoveAll(dir)
}

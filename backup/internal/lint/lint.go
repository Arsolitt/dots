// Package lint detects directory contents that cannot coexist on a
// case-insensitive filesystem such as the macOS APFS.
//
// Backup targets live on macOS (APFS: case-insensitive and
// normalization-insensitive) and on Linux (ext4/XFS: neither). A snapshot may
// therefore contain sibling entries such as "Makefile" and "makefile", or the
// precomposed and the decomposed spelling of the same Unicode name. restic
// backs those up happily on Linux, but restoring them on macOS silently merges
// or drops one of the entries. Check reports such directories so the problem is
// visible before the snapshot is taken and before a restore is attempted on the
// other platform.
package lint

import (
	"errors"
	"fmt"
	"io/fs"
	"path"
	"path/filepath"
	"sort"
	"strings"
	"unicode/utf8"

	"golang.org/x/text/cases"
	"golang.org/x/text/unicode/norm"
)

// Tree is a single backup target to inspect.
type Tree struct {
	Name     string   // target name, copied into Collision.Target
	Root     string   // root directory of the target
	Excludes []string // exclude patterns, matched relative to Root
}

// Collision describes sibling directory entries that cannot coexist on a
// case-insensitive filesystem.
type Collision struct {
	Target string   // Tree.Name of the tree the directory belongs to
	Dir    string   // directory holding the entries: Root itself or a path below it
	Kind   string   // "case" for case-only differences, "unicode" for NFC-equivalent names
	Names  []string // the conflicting entry names, sorted
}

// fold is the case-folding Caser used to group names. cases.Fold is stateless
// and safe for concurrent use, so one shared Caser suffices.
var fold = cases.Fold()

// Check walks every tree and returns all collisions, ordered by target, then by
// directory, then by names. Trees whose root does not exist are skipped, and
// missing or unreadable entries never fail the check.
func Check(trees []Tree) ([]Collision, error) {
	var collisions []Collision
	for _, tree := range trees {
		found, err := checkTree(tree)
		if err != nil {
			return nil, err
		}
		collisions = append(collisions, found...)
	}
	sortCollisions(collisions)
	return collisions, nil
}

// CheckNames reports the collisions among the entry names of one directory. It
// is the pure core of Check; Target and Dir are left empty.
//
// Names are grouped by the case fold of their NFC form, i.e. by what a
// case-insensitive, normalization-insensitive filesystem treats as one name. A
// group of two or more distinct names is a collision: "unicode" when the names
// differ only in normalization, "case" otherwise. Names that are not valid
// UTF-8 are compared verbatim — they cannot be normalized, and since every
// folded key is valid UTF-8 they can never collide with normalizable names.
func CheckNames(names []string) []Collision {
	type entry struct {
		name string
		nfc  string
	}

	groups := make(map[string]map[string]entry) // group key -> name -> entry
	for _, name := range names {
		e := entry{name: name, nfc: name}
		key := name
		if utf8.ValidString(name) {
			e.nfc = norm.NFC.String(name)
			key = fold.String(e.nfc)
		}
		group := groups[key]
		if group == nil {
			group = make(map[string]entry)
			groups[key] = group
		}
		group[e.name] = e
	}

	var collisions []Collision
	for _, group := range groups {
		if len(group) < 2 {
			continue
		}
		entries := make([]entry, 0, len(group))
		for _, e := range group {
			entries = append(entries, e)
		}
		sort.Slice(entries, func(i, j int) bool { return entries[i].name < entries[j].name })

		c := Collision{Kind: "unicode", Names: make([]string, len(entries))}
		for i, e := range entries {
			c.Names[i] = e.name
			if e.nfc != entries[0].nfc {
				c.Kind = "case"
			}
		}
		collisions = append(collisions, c)
	}
	sortCollisions(collisions)
	return collisions
}

// checkTree walks one tree and reports its collisions. Excluded entries are
// absent from the snapshot, so they cannot collide and are skipped entirely; an
// excluded directory hides its whole subtree.
func checkTree(tree Tree) ([]Collision, error) {
	entries, err := walkEntries(tree.Root, tree.Excludes)
	if err != nil {
		return nil, fmt.Errorf("lint: %s: %w", tree.Name, err)
	}

	var collisions []Collision
	for dir, names := range entries {
		for _, c := range CheckNames(names) {
			c.Target = tree.Name
			c.Dir = dir
			collisions = append(collisions, c)
		}
	}
	sortCollisions(collisions)
	return collisions, nil
}

// walkEntries returns the entry names of every directory of the tree, keyed by
// directory path. It walks with filepath.WalkDir, which does not follow
// symlinks: a symlinked directory contributes its name, never the contents of
// its target.
func walkEntries(root string, excludes []string) (map[string][]string, error) {
	root = filepath.Clean(root)
	entries := make(map[string][]string)

	err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			// A missing root, an unreadable directory or a single unreadable
			// entry are all skipped: linting must never be the reason a backup
			// aborts. Any other error is unexpected and reported.
			if errors.Is(err, fs.ErrNotExist) || errors.Is(err, fs.ErrPermission) {
				if d != nil && d.IsDir() {
					return fs.SkipDir
				}
				return nil
			}
			return err
		}
		if p == root {
			return nil // the root is not one of its own entries
		}
		rel, err := filepath.Rel(root, p)
		if err != nil {
			return nil
		}
		if matchesAny(excludes, filepath.ToSlash(rel), d.Name()) {
			if d.IsDir() {
				return fs.SkipDir
			}
			return nil
		}
		dir := filepath.Dir(p)
		entries[dir] = append(entries[dir], d.Name())
		return nil
	})
	if err != nil {
		return nil, err
	}
	return entries, nil
}

// matchesAny reports whether any exclude pattern matches the entry.
func matchesAny(patterns []string, rel, base string) bool {
	for _, pattern := range patterns {
		if matchExclude(pattern, rel, base) {
			return true
		}
	}
	return false
}

// matchExclude approximates restic's exclude matching for the pattern shapes
// this project's config uses. Argument rel is the slash-separated path of the
// entry relative to the tree root and base is its basename.
//
//   - "cache" — no slash: matched against the basename at any depth.
//   - "**/node_modules" — the "**/" prefix with a slash-free remainder is the
//     same basename match.
//   - "**/minecraft/*.tar.gz" — the "**/" prefix with a remainder that does
//     contain a slash: the remainder is matched against the trailing segments
//     of rel.
//   - anything else, e.g. "foo/bar" — path.Match against the whole rel.
//
// A pattern that is not a valid path.Match pattern simply never matches.
func matchExclude(pattern, rel, base string) bool {
	if rest, ok := strings.CutPrefix(pattern, "**/"); ok {
		if !strings.Contains(rest, "/") {
			return matchName(rest, base)
		}
		segments := strings.Split(rest, "/")
		relSegments := strings.Split(rel, "/")
		if len(relSegments) < len(segments) {
			return false
		}
		return matchName(rest, strings.Join(relSegments[len(relSegments)-len(segments):], "/"))
	}
	if !strings.Contains(pattern, "/") {
		return matchName(pattern, base)
	}
	return matchName(pattern, rel)
}

// matchName reports whether name matches pattern; invalid patterns match
// nothing.
func matchName(pattern, name string) bool {
	ok, err := path.Match(pattern, name)
	return err == nil && ok
}

// sortCollisions orders collisions by target, directory, kind and names, so the
// result does not depend on map iteration order.
func sortCollisions(collisions []Collision) {
	sort.Slice(collisions, func(i, j int) bool {
		a, b := collisions[i], collisions[j]
		if a.Target != b.Target {
			return a.Target < b.Target
		}
		if a.Dir != b.Dir {
			return a.Dir < b.Dir
		}
		if a.Kind != b.Kind {
			return a.Kind < b.Kind
		}
		return lessNames(a.Names, b.Names)
	})
}

// lessNames reports whether a sorts before b.
func lessNames(a, b []string) bool {
	for i := 0; i < len(a) && i < len(b); i++ {
		if a[i] != b[i] {
			return a[i] < b[i]
		}
	}
	return len(a) < len(b)
}

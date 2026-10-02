package lint

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// The precomposed and the decomposed spelling of the Cyrillic short I. macOS
// APFS treats them as the same name, so this pair must never be stored as two
// sibling entries.
const (
	precomposedShortI = "\u0439"
	decomposedShortI  = "\u0438\u0306"
)

func TestCheckNamesCaseCollision(t *testing.T) {
	got := CheckNames([]string{"Foo", "foo"})
	want := []Collision{{Kind: "case", Names: []string{"Foo", "foo"}}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("CheckNames = %#v, want %#v", got, want)
	}
}

func TestCheckNamesUnicodeCollision(t *testing.T) {
	got := CheckNames([]string{precomposedShortI, decomposedShortI})
	want := []Collision{{Kind: "unicode", Names: []string{decomposedShortI, precomposedShortI}}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("CheckNames = %#v, want %#v", got, want)
	}
}

func TestCheckNamesDistinctNames(t *testing.T) {
	if got := CheckNames([]string{"alpha", "Beta", "gamma.txt"}); len(got) != 0 {
		t.Fatalf("CheckNames = %#v, want no collisions", got)
	}
}

func TestCheckNamesEmpty(t *testing.T) {
	if got := CheckNames(nil); len(got) != 0 {
		t.Fatalf("CheckNames(nil) = %#v, want no collisions", got)
	}
	if got := CheckNames([]string{}); len(got) != 0 {
		t.Fatalf("CheckNames(empty) = %#v, want no collisions", got)
	}
}

// Invalid UTF-8 cannot be normalized or folded; two such names must not be
// merged into a bogus "unicode" collision.
func TestCheckNamesInvalidUTF8(t *testing.T) {
	if got := CheckNames([]string{"\xff\xfe", "\xfe\xff"}); len(got) != 0 {
		t.Fatalf("CheckNames = %#v, want no collisions", got)
	}
}

func TestCheckNamesDeterministicOrder(t *testing.T) {
	got := CheckNames([]string{"foo", decomposedShortI, "Foo", precomposedShortI})
	want := []Collision{
		{Kind: "case", Names: []string{"Foo", "foo"}},
		{Kind: "unicode", Names: []string{decomposedShortI, precomposedShortI}},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("CheckNames = %#v, want %#v", got, want)
	}
}

func TestMatchExclude(t *testing.T) {
	tests := []struct {
		name    string
		pattern string
		rel     string
		base    string
		want    bool
	}{
		{"bare name at root", "cache", "cache", "cache", true},
		{"bare name at depth", "cache", "kube/cache", "cache", true},
		{"bare name does not match other names", "cache", "kube/cached", "cached", false},
		{"glob basename at depth", "*.pyc", "pkg/module.pyc", "module.pyc", true},
		{"glob basename does not cross separator", "*.pyc", "pkg/__pycache__", "__pycache__", false},
		{"doublestar basename at depth", "**/node_modules", "app/web/node_modules", "node_modules", true},
		{"doublestar basename ignores inner children", "**/node_modules", "app/web/node_modules", "web", false},
		{"doublestar dotfile glob", "**/.stignore.*", "sub/.stignore.swp", ".stignore.swp", true},
		{"doublestar dotfile glob misses other names", "**/.stignore.*", "sub/notes.txt", "notes.txt", false},
		{"doublestar pyc glob", "**/*.pyc", "pkg/__pycache__/module.cpython-312.pyc", "module.cpython-312.pyc", true},
		{"doublestar dist dir", "**/dist", "frontend/dist", "dist", true},
		{"doublestar dist dir keeps children", "**/dist", "frontend/dist/app.js", "app.js", false},
		{"tail segments at depth", "**/minecraft/*.tar.gz", "worlds/minecraft/save.tar.gz", "save.tar.gz", true},
		{"tail segments at root", "**/minecraft/*.tar.gz", "minecraft/save.tar.gz", "save.tar.gz", true},
		{"tail segments require the whole tail", "**/minecraft/*.tar.gz", "minecraft/sub/save.tar.gz", "save.tar.gz", false},
		{"tail segments require the minecraft directory", "**/minecraft/*.tar.gz", "other/save.tar.gz", "save.tar.gz", false},
		{"tail segments match the directory itself", "**/minecraft/*.tar.gz", "minecraft", "minecraft", false},
		{"path pattern is anchored at the root", "foo/bar", "foo/bar", "bar", true},
		{"path pattern does not match deeper paths", "foo/bar", "x/foo/bar", "bar", false},
		{"invalid pattern never matches", "[", "anything", "anything", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := matchExclude(tt.pattern, tt.rel, tt.base); got != tt.want {
				t.Fatalf("matchExclude(%q, %q, %q) = %v, want %v", tt.pattern, tt.rel, tt.base, got, tt.want)
			}
		})
	}
}

func TestCheckCleanTree(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "alpha.txt"))
	writeFile(t, filepath.Join(root, "Beta.txt"))
	writeFile(t, filepath.Join(root, "nested", "sub", "gamma.bin"))

	got, err := Check([]Tree{{Name: "clean", Root: root}})
	if err != nil {
		t.Fatalf("Check: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("Check = %#v, want no collisions", got)
	}
}

func TestCheckMissingRoot(t *testing.T) {
	root := filepath.Join(t.TempDir(), "does-not-exist")

	got, err := Check([]Tree{{Name: "gone", Root: root, Excludes: []string{"**/node_modules"}}})
	if err != nil {
		t.Fatalf("Check: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("Check = %#v, want no collisions", got)
	}
}

func TestWalkEntriesExcludesPruneSubtrees(t *testing.T) {
	root := t.TempDir()
	// Included.
	writeFile(t, filepath.Join(root, "notes.txt"))
	writeFile(t, filepath.Join(root, "keep", "data.bin"))
	writeFile(t, filepath.Join(root, "minecraft", "notes.txt"))
	writeFile(t, filepath.Join(root, "nested", "keepme.txt"))
	writeFile(t, filepath.Join(root, "source", "app.py"))
	// Excluded; every one of these must be missing from the result, including
	// the contents of excluded directories.
	writeFile(t, filepath.Join(root, ".stignore.swp"))
	writeFile(t, filepath.Join(root, "cache", "blob"))
	writeFile(t, filepath.Join(root, "dumps", "big.pyc"))
	writeFile(t, filepath.Join(root, "frontend", "dist", "app.js"))
	writeFile(t, filepath.Join(root, "minecraft", "world.tar.gz"))
	writeFile(t, filepath.Join(root, "nested", "cache", "blob"))
	writeFile(t, filepath.Join(root, "nested", "node_modules", "pkg", "index.js"))

	excludes := []string{"cache", "**/node_modules", "**/dist", "**/*.pyc", "**/.stignore.*", "**/minecraft/*.tar.gz"}
	got, err := walkEntries(root, excludes)
	if err != nil {
		t.Fatalf("walkEntries: %v", err)
	}

	want := map[string][]string{
		root:                             {"dumps", "frontend", "keep", "minecraft", "nested", "notes.txt", "source"},
		filepath.Join(root, "keep"):      {"data.bin"},
		filepath.Join(root, "minecraft"): {"notes.txt"},
		filepath.Join(root, "nested"):    {"keepme.txt"},
		filepath.Join(root, "source"):    {"app.py"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("walkEntries = %#v, want %#v", got, want)
	}
}

func TestWalkEntriesSkipsUnreadableDir(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("permission checks do not apply to root")
	}
	root := t.TempDir()
	locked := filepath.Join(root, "locked")
	writeFile(t, filepath.Join(locked, "inside.txt"))
	if err := os.Chmod(locked, 0o000); err != nil {
		t.Fatalf("chmod: %v", err)
	}
	t.Cleanup(func() { os.Chmod(locked, 0o700) }) // let t.TempDir remove the tree

	got, err := walkEntries(root, nil)
	if err != nil {
		t.Fatalf("walkEntries: %v", err)
	}
	if want := []string{"locked"}; !reflect.DeepEqual(got[root], want) {
		t.Fatalf("entries of root = %#v, want %#v", got[root], want)
	}
	if _, ok := got[locked]; ok {
		t.Fatalf("unreadable directory was walked: %#v", got)
	}
}

// TestCheckReportsCollisions only runs on a case-sensitive filesystem: the
// macOS APFS used for day to day development cannot store the very collisions
// this test needs. The collision logic itself is covered by the CheckNames
// tests.
func TestCheckReportsCollisions(t *testing.T) {
	root := t.TempDir()
	if !caseSensitiveFS(t, root) {
		t.Skip("filesystem is not case-sensitive, cannot create the collision")
	}
	sub := filepath.Join(root, "sub")
	writeFile(t, filepath.Join(sub, "Foo"))
	writeFile(t, filepath.Join(sub, "foo"))
	writeFile(t, filepath.Join(sub, precomposedShortI))
	writeFile(t, filepath.Join(sub, decomposedShortI))
	writeFile(t, filepath.Join(root, "clean.txt"))

	got, err := Check([]Tree{{Name: "projects", Root: root}})
	if err != nil {
		t.Fatalf("Check: %v", err)
	}
	want := []Collision{
		{Target: "projects", Dir: sub, Kind: "case", Names: []string{"Foo", "foo"}},
		{Target: "projects", Dir: sub, Kind: "unicode", Names: []string{decomposedShortI, precomposedShortI}},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Check = %#v, want %#v", got, want)
	}
}

// caseSensitiveFS reports whether dir lives on a case-sensitive filesystem.
func caseSensitiveFS(t *testing.T, dir string) bool {
	t.Helper()
	probe := filepath.Join(dir, "case-probe")
	if err := os.WriteFile(probe, nil, 0o644); err != nil {
		t.Fatalf("write case probe: %v", err)
	}
	t.Cleanup(func() { os.Remove(probe) })

	_, err := os.Lstat(filepath.Join(dir, "CASE-PROBE"))
	return os.IsNotExist(err)
}

// writeFile creates path, including its parents, with a dummy body.
func writeFile(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", filepath.Dir(path), err)
	}
	if err := os.WriteFile(path, []byte("test"), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

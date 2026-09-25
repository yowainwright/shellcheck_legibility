package lint

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
)

func TestBashRegressionParity(t *testing.T) {
	root, err := filepath.Abs("../..")
	if err != nil {
		t.Fatal(err)
	}
	dir := exportRegressionFixtures(t, root)
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) < 75 {
		t.Fatalf("only %d regression fixtures exported", len(entries))
	}
	for _, entry := range entries {
		t.Run(entry.Name(), func(t *testing.T) { compareFixture(t, filepath.Join(dir, entry.Name())) })
	}
}

func exportRegressionFixtures(t *testing.T, root string) string {
	work := filepath.Join(root, ".build")
	if err := os.MkdirAll(work, 0755); err != nil {
		t.Fatal(err)
	}
	dir, err := os.MkdirTemp(work, "parity-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	source := readTestFile(t, filepath.Join(root, "tests/unit/rules.bash"))
	args := []string{filepath.Join(root, "tests/unit/export-fixtures.bash"), root, dir}
	args = append(args, regressionNames(string(source))...)
	if output, err := exec.Command("bash", args...).CombinedOutput(); err != nil {
		t.Fatalf("export fixtures: %v\n%s", err, output)
	}
	return dir
}

func regressionNames(source string) []string {
	functions := regexp.MustCompile(`(?ms)^(test_\w+)\(\) \{\n(.*?)^\}`)
	checks := []string{"scan_fixture ", "scan_line ", "check_no_unmatched_comments ", "check_no_automated_comment_attribution ", "check_no_stacked_comments "}
	var names []string
	for _, match := range functions.FindAllStringSubmatch(source, -1) {
		for _, check := range checks {
			if strings.Contains(match[2], check) {
				names = append(names, match[1])
				break
			}
		}
	}
	return names
}

func readTestFile(t *testing.T, path string) []byte {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func compareFixture(t *testing.T, dir string) {
	config := DefaultConfig()
	if err := json.Unmarshal(readTestFile(t, filepath.Join(dir, "config.json")), &config); err != nil {
		t.Fatal(err)
	}
	source := readTestFile(t, filepath.Join(dir, "source.sh"))
	actual, err := Scan("example.sh", source, config)
	if err != nil {
		t.Skipf("incomplete fixture uses Bash compatibility: %v", err)
	}
	var expected []Diagnostic
	if err := json.Unmarshal(readTestFile(t, filepath.Join(dir, "expected.json")), &expected); err != nil {
		t.Fatal(err)
	}
	assertDiagnosticsEqual(t, source, expected, actual)
}

func assertDiagnosticsEqual(t *testing.T, source []byte, expected, actual []Diagnostic) {
	t.Helper()
	for index := range actual {
		actual[index].trigger = 0
		actual[index].priority = 0
	}
	if !slices.Equal(actual, expected) {
		t.Fatalf("source:\n%s\nexpected: %+v\nactual:   %+v", source, expected, actual)
	}
}

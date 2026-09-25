package app

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"

	"github.com/yowainwright/shellcheck_legibility/internal/lint"
)

type resultCache struct {
	dir     string
	context []byte
}
type cacheEntry struct {
	Key         string
	Diagnostics []lint.Diagnostic
}

func newCache(dir string, config lint.Config) resultCache {
	if dir == "" || os.MkdirAll(dir, 0700) != nil {
		return resultCache{}
	}
	executable, err := os.Executable()
	if err != nil {
		return resultCache{}
	}
	engine, err := os.ReadFile(executable)
	if err != nil {
		return resultCache{}
	}
	encoded, err := json.Marshal(config)
	if err != nil {
		return resultCache{}
	}
	hash := sha256.New()
	hash.Write(engine)
	hash.Write(encoded)
	return resultCache{dir, hash.Sum(nil)}
}

func (c resultCache) key(path string, data []byte) string {
	if c.dir == "" {
		return ""
	}
	absolute, err := filepath.Abs(path)
	if err != nil {
		return ""
	}
	hash := sha256.New()
	hash.Write(c.context)
	hash.Write([]byte(absolute + "\x00" + path + "\x00"))
	hash.Write(data)
	return hex.EncodeToString(hash.Sum(nil))
}

func (c resultCache) read(key string) ([]lint.Diagnostic, bool) {
	if key == "" {
		return nil, false
	}
	data, err := os.ReadFile(filepath.Join(c.dir, key))
	if err != nil {
		return nil, false
	}
	var entry cacheEntry
	if json.Unmarshal(data, &entry) != nil || entry.Key != key || entry.Diagnostics == nil {
		return nil, false
	}
	return entry.Diagnostics, true
}

func (c resultCache) write(key string, diagnostics []lint.Diagnostic) {
	if key == "" {
		return
	}
	file, err := os.CreateTemp(c.dir, ".pending-")
	if err != nil {
		return
	}
	defer os.Remove(file.Name())
	if diagnostics == nil {
		diagnostics = []lint.Diagnostic{}
	}
	err = json.NewEncoder(file).Encode(cacheEntry{key, diagnostics})
	closeError := file.Close()
	if err != nil || closeError != nil {
		return
	}
	_ = os.Rename(file.Name(), filepath.Join(c.dir, key))
}

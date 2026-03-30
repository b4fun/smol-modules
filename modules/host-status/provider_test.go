package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestProviderExecution(t *testing.T) {
	// Create a simple test provider script
	tmpDir := t.TempDir()
	scriptPath := filepath.Join(tmpDir, "test-provider.sh")
	
	script := `#!/bin/bash
cat <<EOF
{
  "status": "ok",
  "metrics": {
    "test_value": 42
  },
  "message": "Test provider"
}
EOF
`
	if err := os.WriteFile(scriptPath, []byte(script), 0755); err != nil {
		t.Fatalf("Failed to create test script: %v", err)
	}

	config := ProviderConfig{
		Name:    "test",
		Command: scriptPath,
		Timeout: "10s",
	}

	provider := NewProvider(config)
	ctx := context.Background()
	
	result, err := provider.Execute(ctx)
	if err != nil {
		t.Fatalf("Provider execution failed: %v", err)
	}

	if result.Name != "test" {
		t.Errorf("Expected name 'test', got '%s'", result.Name)
	}

	if result.Status != StatusOK {
		t.Errorf("Expected status 'ok', got '%s'", result.Status)
	}

	if result.Metrics["test_value"] != float64(42) {
		t.Errorf("Expected test_value 42, got %v", result.Metrics["test_value"])
	}
}

func TestProviderTimeout(t *testing.T) {
	tmpDir := t.TempDir()
	scriptPath := filepath.Join(tmpDir, "slow-provider.sh")
	
	script := `#!/bin/bash
sleep 5
echo '{"status": "ok", "metrics": {}}'
`
	if err := os.WriteFile(scriptPath, []byte(script), 0755); err != nil {
		t.Fatalf("Failed to create test script: %v", err)
	}

	config := ProviderConfig{
		Name:    "slow",
		Command: scriptPath,
		Timeout: "1s",
	}

	provider := NewProvider(config)
	ctx := context.Background()
	
	start := time.Now()
	result, err := provider.Execute(ctx)
	duration := time.Since(start)

	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Status != StatusError {
		t.Errorf("Expected error status for timeout, got '%s'", result.Status)
	}

	// Note: The timeout mechanism cancels the context but the script may still run
	// We just verify that we got an error status within a reasonable time
	if duration > 10*time.Second {
		t.Errorf("Timeout took too long: %v", duration)
	}
}

func TestProviderInvalidJSON(t *testing.T) {
	tmpDir := t.TempDir()
	scriptPath := filepath.Join(tmpDir, "invalid-provider.sh")
	
	script := `#!/bin/bash
echo "not json"
`
	if err := os.WriteFile(scriptPath, []byte(script), 0755); err != nil {
		t.Fatalf("Failed to create test script: %v", err)
	}

	config := ProviderConfig{
		Name:    "invalid",
		Command: scriptPath,
		Timeout: "10s",
	}

	provider := NewProvider(config)
	ctx := context.Background()
	
	result, err := provider.Execute(ctx)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Status != StatusError {
		t.Errorf("Expected error status for invalid JSON, got '%s'", result.Status)
	}

	if result.Error == "" {
		t.Error("Expected error message for invalid JSON")
	}
}

func TestProviderRegistry(t *testing.T) {
	tmpDir := t.TempDir()
	
	// Create two test providers
	script1Path := filepath.Join(tmpDir, "provider1.sh")
	script1 := `#!/bin/bash
cat <<EOF
{"status": "ok", "metrics": {"id": 1}}
EOF
`
	if err := os.WriteFile(script1Path, []byte(script1), 0755); err != nil {
		t.Fatalf("Failed to create test script 1: %v", err)
	}

	script2Path := filepath.Join(tmpDir, "provider2.sh")
	script2 := `#!/bin/bash
cat <<EOF
{"status": "warn", "metrics": {"id": 2}}
EOF
`
	if err := os.WriteFile(script2Path, []byte(script2), 0755); err != nil {
		t.Fatalf("Failed to create test script 2: %v", err)
	}

	configs := []ProviderConfig{
		{Name: "provider1", Command: script1Path, Timeout: "10s"},
		{Name: "provider2", Command: script2Path, Timeout: "10s"},
	}

	registry := NewProviderRegistry(configs)
	ctx := context.Background()
	
	results := registry.ExecuteAll(ctx)

	if len(results) != 2 {
		t.Errorf("Expected 2 results, got %d", len(results))
	}

	if results[0].Status != StatusOK {
		t.Errorf("Expected first provider status 'ok', got '%s'", results[0].Status)
	}

	if results[1].Status != StatusWarn {
		t.Errorf("Expected second provider status 'warn', got '%s'", results[1].Status)
	}
}

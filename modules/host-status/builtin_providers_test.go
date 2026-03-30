package main

import (
	"context"
	"testing"
)

func TestCPUProvider(t *testing.T) {
	provider := &CPUProvider{}

	if provider.Name() != "cpu" {
		t.Errorf("Expected name 'cpu', got '%s'", provider.Name())
	}

	status, metrics, message, err := provider.Execute()
	if err != nil {
		t.Fatalf("CPU provider execution failed: %v", err)
	}

	if status == "" {
		t.Error("Status should not be empty")
	}

	if metrics == nil {
		t.Error("Metrics should not be nil")
	}

	// Check required metrics
	requiredMetrics := []string{"load_1min", "load_5min", "load_15min", "cpu_count", "load_percentage"}
	for _, key := range requiredMetrics {
		if _, ok := metrics[key]; !ok {
			t.Errorf("Missing metric: %s", key)
		}
	}

	if message == "" {
		t.Error("Message should not be empty")
	}
}

func TestMemoryProvider(t *testing.T) {
	provider := &MemoryProvider{}

	if provider.Name() != "memory" {
		t.Errorf("Expected name 'memory', got '%s'", provider.Name())
	}

	status, metrics, message, err := provider.Execute()
	if err != nil {
		t.Fatalf("Memory provider execution failed: %v", err)
	}

	if status == "" {
		t.Error("Status should not be empty")
	}

	if metrics == nil {
		t.Error("Metrics should not be nil")
	}

	// Check required metrics
	requiredMetrics := []string{"total_mb", "used_mb", "available_mb", "used_percentage"}
	for _, key := range requiredMetrics {
		if _, ok := metrics[key]; !ok {
			t.Errorf("Missing metric: %s", key)
		}
	}

	if message == "" {
		t.Error("Message should not be empty")
	}
}

func TestDiskProvider(t *testing.T) {
	provider := &DiskProvider{Path: "/"}

	if provider.Name() != "disk" {
		t.Errorf("Expected name 'disk', got '%s'", provider.Name())
	}

	status, metrics, message, err := provider.Execute()
	if err != nil {
		t.Fatalf("Disk provider execution failed: %v", err)
	}

	if status == "" {
		t.Error("Status should not be empty")
	}

	if metrics == nil {
		t.Error("Metrics should not be nil")
	}

	// Check required metrics
	requiredMetrics := []string{"path", "total_gb", "used_gb", "available_gb", "used_percentage"}
	for _, key := range requiredMetrics {
		if _, ok := metrics[key]; !ok {
			t.Errorf("Missing metric: %s", key)
		}
	}

	if message == "" {
		t.Error("Message should not be empty")
	}
}

func TestUptimeProvider(t *testing.T) {
	provider := &UptimeProvider{}

	if provider.Name() != "uptime" {
		t.Errorf("Expected name 'uptime', got '%s'", provider.Name())
	}

	status, metrics, message, err := provider.Execute()
	if err != nil {
		t.Fatalf("Uptime provider execution failed: %v", err)
	}

	if status != StatusOK {
		t.Errorf("Uptime status should always be 'ok', got '%s'", status)
	}

	if metrics == nil {
		t.Error("Metrics should not be nil")
	}

	// Check required metrics
	requiredMetrics := []string{"uptime_seconds", "days", "hours", "minutes"}
	for _, key := range requiredMetrics {
		if _, ok := metrics[key]; !ok {
			t.Errorf("Missing metric: %s", key)
		}
	}

	if message == "" {
		t.Error("Message should not be empty")
	}
}

func TestBuiltinProviderWrapper(t *testing.T) {
	config := ProviderConfig{
		Name:    "cpu",
		Timeout: "10s",
	}

	builtinProvider := &CPUProvider{}
	wrapper := NewBuiltinProviderWrapper(builtinProvider, config)

	ctx := context.Background()
	result, err := wrapper.Execute(ctx)

	if err != nil {
		t.Fatalf("Wrapper execution failed: %v", err)
	}

	if result == nil {
		t.Fatal("Result should not be nil")
	}

	if result.Name != "cpu" {
		t.Errorf("Expected name 'cpu', got '%s'", result.Name)
	}

	if result.Status == "" {
		t.Error("Status should not be empty")
	}

	if result.Metrics == nil {
		t.Error("Metrics should not be nil")
	}

	if result.Timestamp.IsZero() {
		t.Error("Timestamp should be set")
	}

	// Check that execution_time_ms was added
	if _, ok := result.Metrics["execution_time_ms"]; !ok {
		t.Error("Missing execution_time_ms metric")
	}
}

func TestGetBuiltinProvider(t *testing.T) {
	tests := []struct {
		name     string
		wantType string
	}{
		{"cpu", "*main.CPUProvider"},
		{"memory", "*main.MemoryProvider"},
		{"disk", "*main.DiskProvider"},
		{"uptime", "*main.UptimeProvider"},
		{"unknown", ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			config := ProviderConfig{Name: tt.name}
			provider := GetBuiltinProvider(tt.name, config)

			if tt.wantType == "" {
				if provider != nil {
					t.Errorf("Expected nil provider for '%s', got %T", tt.name, provider)
				}
			} else {
				if provider == nil {
					t.Errorf("Expected provider for '%s', got nil", tt.name)
				}
			}
		})
	}
}

func TestIsBuiltinProvider(t *testing.T) {
	tests := []struct {
		name string
		want bool
	}{
		{"cpu", true},
		{"memory", true},
		{"disk", true},
		{"uptime", true},
		{"custom", false},
		{"unknown", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := IsBuiltinProvider(tt.name)
			if got != tt.want {
				t.Errorf("IsBuiltinProvider(%s) = %v, want %v", tt.name, got, tt.want)
			}
		})
	}
}

func TestBuiltinProviderRegistry(t *testing.T) {
	configs := []ProviderConfig{
		{Name: "cpu", Timeout: "10s"},
		{Name: "memory", Timeout: "10s"},
		{Name: "disk", Timeout: "10s"},
		{Name: "uptime", Timeout: "10s"},
	}

	registry := NewProviderRegistry(configs)

	if len(registry.providers) != 4 {
		t.Errorf("Expected 4 providers, got %d", len(registry.providers))
	}

	ctx := context.Background()
	results := registry.ExecuteAll(ctx)

	if len(results) != 4 {
		t.Errorf("Expected 4 results, got %d", len(results))
	}

	for _, result := range results {
		if result.Status == StatusError {
			t.Errorf("Provider '%s' failed: %s", result.Name, result.Error)
		}
	}
}

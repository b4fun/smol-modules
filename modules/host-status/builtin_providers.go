package main

import (
	"context"
	"fmt"
	"runtime"
	"syscall"
	"time"
)

// BuiltinProvider represents a provider implemented in Go
type BuiltinProvider interface {
	Name() string
	Execute() (ProviderStatus, map[string]interface{}, string, error)
}

// CPUProvider monitors CPU load
type CPUProvider struct{}

func (p *CPUProvider) Name() string {
	return "cpu"
}

func (p *CPUProvider) Execute() (ProviderStatus, map[string]interface{}, string, error) {
	// Get load averages
	var si syscall.Sysinfo_t
	if err := syscall.Sysinfo(&si); err != nil {
		return StatusError, nil, "", fmt.Errorf("failed to get system info: %w", err)
	}

	// Load averages are provided as integers, need to divide by 65536.0
	load1 := float64(si.Loads[0]) / 65536.0
	load5 := float64(si.Loads[1]) / 65536.0
	load15 := float64(si.Loads[2]) / 65536.0

	cpuCount := runtime.NumCPU()
	loadPct := (load1 / float64(cpuCount)) * 100

	// Determine status
	status := StatusOK
	if loadPct > 80 {
		status = StatusError
	} else if loadPct > 60 {
		status = StatusWarn
	}

	metrics := map[string]interface{}{
		"load_1min":       load1,
		"load_5min":       load5,
		"load_15min":      load15,
		"cpu_count":       cpuCount,
		"load_percentage": loadPct,
	}

	message := fmt.Sprintf("CPU load: %.2f (%.2f%%)", load1, loadPct)
	return status, metrics, message, nil
}

// MemoryProvider monitors memory usage
type MemoryProvider struct{}

func (p *MemoryProvider) Name() string {
	return "memory"
}

func (p *MemoryProvider) Execute() (ProviderStatus, map[string]interface{}, string, error) {
	var si syscall.Sysinfo_t
	if err := syscall.Sysinfo(&si); err != nil {
		return StatusError, nil, "", fmt.Errorf("failed to get system info: %w", err)
	}

	// Convert to MB
	unit := uint64(si.Unit)
	totalMB := (si.Totalram * unit) / (1024 * 1024)
	freeMB := (si.Freeram * unit) / (1024 * 1024)
	buffersMB := (si.Bufferram * unit) / (1024 * 1024)

	// Calculate available memory (free + buffers is a simple approximation)
	availableMB := freeMB + buffersMB
	usedMB := totalMB - availableMB
	usedPct := (float64(usedMB) / float64(totalMB)) * 100

	// Determine status
	status := StatusOK
	if usedPct > 90 {
		status = StatusError
	} else if usedPct > 80 {
		status = StatusWarn
	}

	metrics := map[string]interface{}{
		"total_mb":        totalMB,
		"used_mb":         usedMB,
		"available_mb":    availableMB,
		"used_percentage": usedPct,
	}

	message := fmt.Sprintf("Memory usage: %dMB / %dMB (%.2f%%)", usedMB, totalMB, usedPct)
	return status, metrics, message, nil
}

// DiskProvider monitors disk usage
type DiskProvider struct {
	Path string
}

func (p *DiskProvider) Name() string {
	return "disk"
}

func (p *DiskProvider) Execute() (ProviderStatus, map[string]interface{}, string, error) {
	path := p.Path
	if path == "" {
		path = "/"
	}

	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return StatusError, nil, "", fmt.Errorf("failed to get disk stats: %w", err)
	}

	// Calculate sizes in GB
	totalGB := float64(stat.Blocks*uint64(stat.Bsize)) / (1024 * 1024 * 1024)
	availableGB := float64(stat.Bavail*uint64(stat.Bsize)) / (1024 * 1024 * 1024)
	usedGB := totalGB - availableGB
	usedPct := (usedGB / totalGB) * 100

	// Determine status
	status := StatusOK
	if usedPct > 90 {
		status = StatusError
	} else if usedPct > 80 {
		status = StatusWarn
	}

	metrics := map[string]interface{}{
		"path":            path,
		"total_gb":        totalGB,
		"used_gb":         usedGB,
		"available_gb":    availableGB,
		"used_percentage": usedPct,
	}

	message := fmt.Sprintf("Disk usage (%s): %.2fGB / %.2fGB (%.2f%%)", path, usedGB, totalGB, usedPct)
	return status, metrics, message, nil
}

// UptimeProvider reports system uptime
type UptimeProvider struct{}

func (p *UptimeProvider) Name() string {
	return "uptime"
}

func (p *UptimeProvider) Execute() (ProviderStatus, map[string]interface{}, string, error) {
	var si syscall.Sysinfo_t
	if err := syscall.Sysinfo(&si); err != nil {
		return StatusError, nil, "", fmt.Errorf("failed to get system info: %w", err)
	}

	uptimeSeconds := si.Uptime
	days := uptimeSeconds / 86400
	hours := (uptimeSeconds % 86400) / 3600
	minutes := (uptimeSeconds % 3600) / 60

	metrics := map[string]interface{}{
		"uptime_seconds": uptimeSeconds,
		"days":           days,
		"hours":          hours,
		"minutes":        minutes,
	}

	message := fmt.Sprintf("System uptime: %dd %dh %dm", days, hours, minutes)
	return StatusOK, metrics, message, nil
}

// BuiltinProviderWrapper wraps a BuiltinProvider to match the Provider interface
type BuiltinProviderWrapper struct {
	provider BuiltinProvider
	config   ProviderConfig
}

func NewBuiltinProviderWrapper(provider BuiltinProvider, config ProviderConfig) *BuiltinProviderWrapper {
	return &BuiltinProviderWrapper{
		provider: provider,
		config:   config,
	}
}

func (w *BuiltinProviderWrapper) Execute(ctx context.Context) (*ProviderResult, error) {
	start := time.Now()

	// Execute the builtin provider
	status, metrics, message, err := w.provider.Execute()
	execTime := time.Since(start)

	result := &ProviderResult{
		Name:      w.config.Name,
		Timestamp: time.Now(),
	}

	if err != nil {
		result.Status = StatusError
		result.Error = err.Error()
		result.Metrics = map[string]interface{}{
			"execution_time_ms": execTime.Milliseconds(),
		}
		return result, nil
	}

	result.Status = status
	if metrics == nil {
		metrics = make(map[string]interface{})
	}
	metrics["execution_time_ms"] = execTime.Milliseconds()
	if message != "" {
		metrics["message"] = message
	}
	result.Metrics = metrics

	return result, nil
}

// GetBuiltinProvider returns a builtin provider by name
func GetBuiltinProvider(name string, config ProviderConfig) BuiltinProvider {
	switch name {
	case "cpu":
		return &CPUProvider{}
	case "memory":
		return &MemoryProvider{}
	case "disk":
		// Check if a path is provided in args
		path := "/"
		if len(config.Args) > 0 {
			path = config.Args[0]
		}
		return &DiskProvider{Path: path}
	case "uptime":
		return &UptimeProvider{}
	default:
		return nil
	}
}

// IsBuiltinProvider checks if a provider name is a builtin
func IsBuiltinProvider(name string) bool {
	switch name {
	case "cpu", "memory", "disk", "uptime":
		return true
	default:
		return false
	}
}

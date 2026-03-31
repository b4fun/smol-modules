package host

import (
	"context"
	"fmt"
	"runtime"
	"syscall"
	"time"
)

// ProviderStatus represents the status of a provider result
type ProviderStatus string

const (
	StatusOK    ProviderStatus = "ok"
	StatusWarn  ProviderStatus = "warn"
	StatusError ProviderStatus = "error"
)

// Result represents the result from a provider execution
type Result struct {
	Name      string                 `json:"name"`
	Status    ProviderStatus         `json:"status"`
	Metrics   map[string]interface{} `json:"metrics"`
	Error     string                 `json:"error,omitempty"`
	Timestamp time.Time              `json:"timestamp"`
}

// Provider represents a builtin provider
type Provider interface {
	Name() string
	Execute(ctx context.Context) (*Result, error)
}

// CPUProvider monitors CPU load
type CPUProvider struct{}

func (p *CPUProvider) Name() string {
	return "cpu"
}

func (p *CPUProvider) Execute(ctx context.Context) (*Result, error) {
	start := time.Now()

	// Get load averages
	var si syscall.Sysinfo_t
	if err := syscall.Sysinfo(&si); err != nil {
		return &Result{
			Name:      p.Name(),
			Status:    StatusError,
			Error:     fmt.Sprintf("failed to get system info: %v", err),
			Timestamp: time.Now(),
		}, nil
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
		"load_1min":         load1,
		"load_5min":         load5,
		"load_15min":        load15,
		"cpu_count":         cpuCount,
		"load_percentage":   loadPct,
		"execution_time_ms": time.Since(start).Milliseconds(),
		"message":           fmt.Sprintf("CPU load: %.2f (%.2f%%)", load1, loadPct),
	}

	return &Result{
		Name:      p.Name(),
		Status:    status,
		Metrics:   metrics,
		Timestamp: time.Now(),
	}, nil
}

// MemoryProvider monitors memory usage
type MemoryProvider struct{}

func (p *MemoryProvider) Name() string {
	return "memory"
}

func (p *MemoryProvider) Execute(ctx context.Context) (*Result, error) {
	start := time.Now()

	var si syscall.Sysinfo_t
	if err := syscall.Sysinfo(&si); err != nil {
		return &Result{
			Name:      p.Name(),
			Status:    StatusError,
			Error:     fmt.Sprintf("failed to get system info: %v", err),
			Timestamp: time.Now(),
		}, nil
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
		"total_mb":          totalMB,
		"used_mb":           usedMB,
		"available_mb":      availableMB,
		"used_percentage":   usedPct,
		"execution_time_ms": time.Since(start).Milliseconds(),
		"message":           fmt.Sprintf("Memory usage: %dMB / %dMB (%.2f%%)", usedMB, totalMB, usedPct),
	}

	return &Result{
		Name:      p.Name(),
		Status:    status,
		Metrics:   metrics,
		Timestamp: time.Now(),
	}, nil
}

// DiskProvider monitors disk usage
type DiskProvider struct {
	Path string
}

func (p *DiskProvider) Name() string {
	return "disk"
}

func (p *DiskProvider) Execute(ctx context.Context) (*Result, error) {
	start := time.Now()

	path := p.Path
	if path == "" {
		path = "/"
	}

	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return &Result{
			Name:      p.Name(),
			Status:    StatusError,
			Error:     fmt.Sprintf("failed to get disk stats: %v", err),
			Timestamp: time.Now(),
		}, nil
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
		"path":              path,
		"total_gb":          totalGB,
		"used_gb":           usedGB,
		"available_gb":      availableGB,
		"used_percentage":   usedPct,
		"execution_time_ms": time.Since(start).Milliseconds(),
		"message":           fmt.Sprintf("Disk usage (%s): %.2fGB / %.2fGB (%.2f%%)", path, usedGB, totalGB, usedPct),
	}

	return &Result{
		Name:      p.Name(),
		Status:    status,
		Metrics:   metrics,
		Timestamp: time.Now(),
	}, nil
}

// UptimeProvider reports system uptime
type UptimeProvider struct{}

func (p *UptimeProvider) Name() string {
	return "uptime"
}

func (p *UptimeProvider) Execute(ctx context.Context) (*Result, error) {
	start := time.Now()

	var si syscall.Sysinfo_t
	if err := syscall.Sysinfo(&si); err != nil {
		return &Result{
			Name:      p.Name(),
			Status:    StatusError,
			Error:     fmt.Sprintf("failed to get system info: %v", err),
			Timestamp: time.Now(),
		}, nil
	}

	uptimeSeconds := si.Uptime
	days := uptimeSeconds / 86400
	hours := (uptimeSeconds % 86400) / 3600
	minutes := (uptimeSeconds % 3600) / 60

	metrics := map[string]interface{}{
		"uptime_seconds":    uptimeSeconds,
		"days":              days,
		"hours":             hours,
		"minutes":           minutes,
		"execution_time_ms": time.Since(start).Milliseconds(),
		"message":           fmt.Sprintf("System uptime: %dd %dh %dm", days, hours, minutes),
	}

	return &Result{
		Name:      p.Name(),
		Status:    StatusOK,
		Metrics:   metrics,
		Timestamp: time.Now(),
	}, nil
}

// New returns a provider by name
func New(name string, args []string) Provider {
	switch name {
	case "cpu":
		return &CPUProvider{}
	case "memory":
		return &MemoryProvider{}
	case "disk":
		path := "/"
		if len(args) > 0 {
			path = args[0]
		}
		return &DiskProvider{Path: path}
	case "uptime":
		return &UptimeProvider{}
	default:
		return nil
	}
}

// IsBuiltin checks if a provider name is builtin
func IsBuiltin(name string) bool {
	switch name {
	case "cpu", "memory", "disk", "uptime":
		return true
	default:
		return false
	}
}

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"time"
)

// ProviderStatus represents the status reported by a provider
type ProviderStatus string

const (
	StatusOK    ProviderStatus = "ok"
	StatusWarn  ProviderStatus = "warn"
	StatusError ProviderStatus = "error"
)

// ProviderResult represents the output from a provider
type ProviderResult struct {
	Name      string                 `json:"name"`
	Status    ProviderStatus         `json:"status"`
	Metrics   map[string]interface{} `json:"metrics"`
	Timestamp time.Time              `json:"timestamp"`
	Error     string                 `json:"error,omitempty"`
}

// Provider executes and manages status providers
type Provider struct {
	config ProviderConfig
}

// NewProvider creates a new Provider instance
func NewProvider(config ProviderConfig) *Provider {
	return &Provider{config: config}
}

// Execute runs the provider command and returns the result
func (p *Provider) Execute(ctx context.Context) (*ProviderResult, error) {
	timeout, err := p.config.GetParsedTimeout()
	if err != nil {
		return nil, fmt.Errorf("invalid timeout: %w", err)
	}

	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, p.config.Command, p.config.Args...)

	// Set environment variables
	if len(p.config.Env) > 0 {
		for k, v := range p.config.Env {
			cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
		}
	}

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	start := time.Now()
	err = cmd.Run()
	execTime := time.Since(start)

	result := &ProviderResult{
		Name:      p.config.Name,
		Timestamp: time.Now(),
	}

	if err != nil {
		result.Status = StatusError
		result.Error = fmt.Sprintf("execution failed: %v (stderr: %s)", err, stderr.String())
		result.Metrics = map[string]interface{}{
			"execution_time_ms": execTime.Milliseconds(),
		}
		return result, nil
	}

	// Parse stdout as JSON
	var providerOutput struct {
		Status  string                 `json:"status"`
		Metrics map[string]interface{} `json:"metrics"`
		Message string                 `json:"message"`
	}

	if err := json.Unmarshal(stdout.Bytes(), &providerOutput); err != nil {
		result.Status = StatusError
		result.Error = fmt.Sprintf("invalid JSON output: %v", err)
		result.Metrics = map[string]interface{}{
			"execution_time_ms": execTime.Milliseconds(),
			"raw_output":        stdout.String(),
		}
		return result, nil
	}

	// Populate result from provider output
	result.Status = ProviderStatus(providerOutput.Status)
	if result.Status == "" {
		result.Status = StatusOK
	}

	result.Metrics = providerOutput.Metrics
	if result.Metrics == nil {
		result.Metrics = make(map[string]interface{})
	}
	result.Metrics["execution_time_ms"] = execTime.Milliseconds()

	if providerOutput.Message != "" {
		result.Metrics["message"] = providerOutput.Message
	}

	return result, nil
}

// ProviderExecutor is the interface for anything that can execute and return provider results
type ProviderExecutor interface {
	Execute(ctx context.Context) (*ProviderResult, error)
}

// ProviderRegistry manages multiple providers
type ProviderRegistry struct {
	providers []ProviderExecutor
}

// NewProviderRegistry creates a new provider registry
func NewProviderRegistry(configs []ProviderConfig) *ProviderRegistry {
	providers := make([]ProviderExecutor, 0, len(configs))
	for _, config := range configs {
		// Check if this is a builtin provider
		if config.Command == "" && IsBuiltinProvider(config.Name) {
			// Use builtin provider
			builtinProvider := GetBuiltinProvider(config.Name, config)
			if builtinProvider != nil {
				providers = append(providers, NewBuiltinProviderWrapper(builtinProvider, config))
				continue
			}
		}
		// Use external command provider
		providers = append(providers, NewProvider(config))
	}
	return &ProviderRegistry{providers: providers}
}

// ExecuteAll runs all providers and returns their results
func (r *ProviderRegistry) ExecuteAll(ctx context.Context) []*ProviderResult {
	results := make([]*ProviderResult, 0, len(r.providers))

	for _, provider := range r.providers {
		result, err := provider.Execute(ctx)
		if err != nil {
			// Create generic error result
			result = &ProviderResult{
				Name:      "unknown",
				Status:    StatusError,
				Timestamp: time.Now(),
				Error:     err.Error(),
				Metrics:   make(map[string]interface{}),
			}
		}
		results = append(results, result)
	}

	return results
}

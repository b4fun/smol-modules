package main

import "time"

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

// StatusResponse represents the aggregated status response
type StatusResponse struct {
	Hostname  string            `json:"hostname"`
	Timestamp time.Time         `json:"timestamp"`
	Providers []*ProviderResult `json:"providers"`
	Overall   ProviderStatus    `json:"overall"`
}

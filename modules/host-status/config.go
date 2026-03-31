package main

import (
	"time"

	"github.com/BurntSushi/toml"
)

// Config represents the host-status configuration
type Config struct {
	Pull      PullConfig       `toml:"pull"`
	Push      PushConfig       `toml:"push"`
	Providers []ProviderConfig `toml:"providers"`
}

// PullConfig configures the pull-based HTTP server
type PullConfig struct {
	Enabled bool   `toml:"enabled"`
	Port    int    `toml:"port"`
	Host    string `toml:"host"`
}

// PushConfig configures the push-based reporting
type PushConfig struct {
	Enabled      bool              `toml:"enabled"`
	Interval     string            `toml:"interval"`
	Destinations []PushDestination `toml:"destinations"`
}

// PushDestination represents a push target
type PushDestination struct {
	URL     string            `toml:"url"`
	Auth    string            `toml:"auth"`
	Headers map[string]string `toml:"headers"`
}

// ProviderConfig defines a status provider
type ProviderConfig struct {
	Name    string            `toml:"name"`
	Command string            `toml:"command"`
	Args    []string          `toml:"args"`
	Timeout string            `toml:"timeout"`
	Env     map[string]string `toml:"env"`
}

// GetParsedInterval returns the push interval as time.Duration
func (p *PushConfig) GetParsedInterval() (time.Duration, error) {
	if p.Interval == "" {
		return 5 * time.Minute, nil // Default to 5 minutes
	}
	return time.ParseDuration(p.Interval)
}

// GetParsedTimeout returns the provider timeout as time.Duration
func (p *ProviderConfig) GetParsedTimeout() (time.Duration, error) {
	if p.Timeout == "" {
		return 30 * time.Second, nil // Default to 30 seconds
	}
	return time.ParseDuration(p.Timeout)
}

// LoadConfig reads and parses the configuration file
func LoadConfig(path string) (*Config, error) {
	var config Config
	if _, err := toml.DecodeFile(path, &config); err != nil {
		return nil, err
	}
	return &config, nil
}

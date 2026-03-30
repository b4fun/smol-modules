package main

import (
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

// Config represents the host-status configuration
type Config struct {
	Pull      PullConfig       `yaml:"pull"`
	Push      PushConfig       `yaml:"push"`
	Providers []ProviderConfig `yaml:"providers"`
}

// PullConfig configures the pull-based HTTP server
type PullConfig struct {
	Enabled bool   `yaml:"enabled"`
	Port    int    `yaml:"port"`
	Host    string `yaml:"host"`
}

// PushConfig configures the push-based reporting
type PushConfig struct {
	Enabled      bool              `yaml:"enabled"`
	Interval     string            `yaml:"interval"`
	Destinations []PushDestination `yaml:"destinations"`
}

// PushDestination represents a push target
type PushDestination struct {
	URL     string            `yaml:"url"`
	Auth    string            `yaml:"auth"`
	Headers map[string]string `yaml:"headers"`
}

// ProviderConfig defines a status provider
type ProviderConfig struct {
	Name    string            `yaml:"name"`
	Command string            `yaml:"command"`
	Args    []string          `yaml:"args"`
	Timeout string            `yaml:"timeout"`
	Env     map[string]string `yaml:"env"`
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
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var config Config
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, err
	}

	return &config, nil
}

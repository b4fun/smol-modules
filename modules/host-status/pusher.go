package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"
)

// Pusher handles periodic status pushing
type Pusher struct {
	config   *PushConfig
	registry *ProviderRegistry
	stopChan chan struct{}
}

// NewPusher creates a new pusher instance
func NewPusher(config *PushConfig, registry *ProviderRegistry) *Pusher {
	return &Pusher{
		config:   config,
		registry: registry,
		stopChan: make(chan struct{}),
	}
}

// Start begins the periodic push cycle
func (p *Pusher) Start(ctx context.Context) error {
	interval, err := p.config.GetParsedInterval()
	if err != nil {
		return fmt.Errorf("invalid push interval: %w", err)
	}

	log.Printf("Starting pusher with interval: %v", interval)

	// Push immediately on start
	p.push(ctx)

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-p.stopChan:
			return nil
		case <-ticker.C:
			p.push(ctx)
		}
	}
}

// Stop halts the pusher
func (p *Pusher) Stop() {
	close(p.stopChan)
}

// push executes providers and sends results to all destinations
func (p *Pusher) push(ctx context.Context) {
	results := p.registry.ExecuteAll(ctx)

	// Determine overall status
	overall := StatusOK
	for _, result := range results {
		if result.Status == StatusError {
			overall = StatusError
			break
		} else if result.Status == StatusWarn && overall != StatusError {
			overall = StatusWarn
		}
	}

	hostname, _ := getHostname()
	payload := StatusResponse{
		Hostname:  hostname,
		Timestamp: time.Now(),
		Providers: results,
		Overall:   overall,
	}

	// Send to all destinations
	for _, dest := range p.config.Destinations {
		if err := p.sendToDestination(ctx, dest, payload); err != nil {
			log.Printf("Failed to push to %s: %v", dest.URL, err)
		} else {
			log.Printf("Successfully pushed to %s", dest.URL)
		}
	}
}

// sendToDestination sends the payload to a specific destination with retry logic
func (p *Pusher) sendToDestination(ctx context.Context, dest PushDestination, payload StatusResponse) error {
	data, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal payload: %w", err)
	}

	maxRetries := 3
	for attempt := 0; attempt < maxRetries; attempt++ {
		if attempt > 0 {
			time.Sleep(time.Second * time.Duration(attempt))
		}

		req, err := http.NewRequestWithContext(ctx, http.MethodPost, dest.URL, bytes.NewReader(data))
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		req.Header.Set("Content-Type", "application/json")
		if dest.Auth != "" {
			req.Header.Set("Authorization", dest.Auth)
		}
		for k, v := range dest.Headers {
			req.Header.Set(k, v)
		}

		client := &http.Client{Timeout: 30 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			if attempt < maxRetries-1 {
				log.Printf("Push attempt %d failed: %v, retrying...", attempt+1, err)
				continue
			}
			return fmt.Errorf("all retry attempts failed: %w", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			return nil
		}

		if attempt < maxRetries-1 {
			log.Printf("Push attempt %d returned status %d, retrying...", attempt+1, resp.StatusCode)
			continue
		}
		return fmt.Errorf("received status code %d after all retries", resp.StatusCode)
	}

	return fmt.Errorf("unexpected error in retry loop")
}

package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/b4fun/smol-modules/modules/host-status/internal/server"
)

func main() {
	configPath := flag.String("config", "config.toml", "Path to configuration file")
	flag.Parse()

	if err := run(*configPath); err != nil {
		log.Fatalf("Error: %v", err)
	}
}

func run(configPath string) error {
	// Load configuration
	config, err := LoadConfig(configPath)
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	log.Printf("Loaded configuration from %s", configPath)
	log.Printf("Pull enabled: %v, Push enabled: %v, Providers: %d",
		config.Pull.Enabled, config.Push.Enabled, len(config.Providers))

	// Create provider registry
	registry := NewProviderRegistry(config.Providers)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Setup signal handling
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	errChan := make(chan error, 2)

	// Start pull server if enabled
	var srv *server.Server
	if config.Pull.Enabled {
		srvConfig := &server.Config{
			Enabled: config.Pull.Enabled,
			Port:    config.Pull.Port,
			Host:    config.Pull.Host,
		}
		adapter := &RegistryAdapter{registry: registry}
		srv = server.New(srvConfig, adapter)
		go func() {
			if err := srv.Start(); err != nil {
				errChan <- fmt.Errorf("server error: %w", err)
			}
		}()
	}

	// Start pusher if enabled
	var pusher *Pusher
	if config.Push.Enabled {
		pusher = NewPusher(&config.Push, registry)
		go func() {
			if err := pusher.Start(ctx); err != nil && err != context.Canceled {
				errChan <- fmt.Errorf("pusher error: %w", err)
			}
		}()
	}

	// Wait for shutdown signal or error
	select {
	case <-sigChan:
		log.Println("Received shutdown signal")
	case err := <-errChan:
		log.Printf("Error occurred: %v", err)
	}

	// Graceful shutdown
	log.Println("Shutting down...")
	cancel()

	if pusher != nil {
		pusher.Stop()
	}

	if srv != nil {
		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer shutdownCancel()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			log.Printf("Server shutdown error: %v", err)
		}
	}

	log.Println("Shutdown complete")
	return nil
}

// RegistryAdapter adapts ProviderRegistry to server.ProviderExecutor
type RegistryAdapter struct {
	registry *ProviderRegistry
}

func (a *RegistryAdapter) ExecuteAll(ctx context.Context) []*server.ProviderResult {
	results := a.registry.ExecuteAll(ctx)
	serverResults := make([]*server.ProviderResult, len(results))
	for i, r := range results {
		serverResults[i] = &server.ProviderResult{
			Name:      r.Name,
			Status:    server.ProviderStatus(r.Status),
			Metrics:   r.Metrics,
			Timestamp: r.Timestamp,
			Error:     r.Error,
		}
	}
	return serverResults
}

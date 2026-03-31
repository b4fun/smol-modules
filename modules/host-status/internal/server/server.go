package server

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
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

// ProviderExecutor is the interface for anything that can execute and return provider results
type ProviderExecutor interface {
	ExecuteAll(ctx context.Context) []*ProviderResult
}

// Config holds server configuration
type Config struct {
	Enabled bool
	Port    int
	Host    string
}

// Response represents the aggregated status response
type Response struct {
	Hostname  string            `json:"hostname"`
	Timestamp time.Time         `json:"timestamp"`
	Providers []*ProviderResult `json:"providers"`
	Overall   ProviderStatus    `json:"overall"`
}

// Server handles HTTP requests for status
type Server struct {
	config   *Config
	executor ProviderExecutor
	server   *http.Server
}

// New creates a new HTTP server
func New(config *Config, executor ProviderExecutor) *Server {
	return &Server{
		config:   config,
		executor: executor,
	}
}

// Start begins serving HTTP requests
func (s *Server) Start() error {
	mux := http.NewServeMux()
	mux.HandleFunc("/status", s.handleStatus)
	mux.HandleFunc("/health", s.handleHealth)

	addr := fmt.Sprintf("%s:%d", s.config.Host, s.config.Port)
	s.server = &http.Server{
		Addr:    addr,
		Handler: mux,
	}

	log.Printf("Starting HTTP server on %s", addr)
	return s.server.ListenAndServe()
}

// Shutdown gracefully stops the server
func (s *Server) Shutdown(ctx context.Context) error {
	if s.server != nil {
		return s.server.Shutdown(ctx)
	}
	return nil
}

// handleStatus processes /status requests
func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	ctx := r.Context()
	results := s.executor.ExecuteAll(ctx)

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

	hostname, _ := os.Hostname()
	response := Response{
		Hostname:  hostname,
		Timestamp: time.Now(),
		Providers: results,
		Overall:   overall,
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("Error encoding response: %v", err)
	}
}

// handleHealth processes /health requests
func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"status": "ok",
	})
}

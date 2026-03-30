package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"
)

// StatusResponse represents the aggregated status response
type StatusResponse struct {
	Hostname  string            `json:"hostname"`
	Timestamp time.Time         `json:"timestamp"`
	Providers []*ProviderResult `json:"providers"`
	Overall   ProviderStatus    `json:"overall"`
}

// Server handles HTTP requests for status
type Server struct {
	config   *PullConfig
	registry *ProviderRegistry
	server   *http.Server
}

// NewServer creates a new HTTP server
func NewServer(config *PullConfig, registry *ProviderRegistry) *Server {
	return &Server{
		config:   config,
		registry: registry,
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
	results := s.registry.ExecuteAll(ctx)

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
	response := StatusResponse{
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

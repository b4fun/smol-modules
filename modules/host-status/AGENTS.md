# host-status — Agent Guidance

## Architecture Overview

The host-status module is designed around three core components:

1. **Provider System**: Executes external programs to collect metrics
2. **Pull Model**: HTTP server for on-demand status queries
3. **Push Model**: Periodic scheduler that sends status to remote endpoints

## Design Principles

- **Simplicity**: Providers are just executables that output JSON
- **Flexibility**: Both pull and push can be enabled independently or together
- **Robustness**: Timeouts, retries, and error handling at every layer
- **Observability**: Comprehensive logging and metrics in responses

## Provider Contract

Providers MUST:
- Output valid JSON to stdout with fields: `status`, `metrics`, `message`
- Use status values: `ok`, `warn`, or `error`
- Exit with code 0 on success
- Complete within the configured timeout

Providers MAY:
- Read environment variables for configuration
- Accept command-line arguments
- Write logs to stderr (captured separately)
- Return empty metrics object

## Code Organization

- `main.go`: Entry point, signal handling, graceful shutdown
- `config.go`: Configuration parsing and validation
- `provider.go`: Provider execution and registry
- `pusher.go`: Periodic scheduler for push model
- `internal/server`: HTTP server for pull model
- `internal/providers/host`: Built-in system metrics providers
- `examples/`: Example configuration and reference providers

## Development Guidelines

### Adding New Features

1. Update configuration structs in `config.go` if needed
2. Add validation logic for new config fields
3. Update example config in `examples/config.yaml`
4. Document in `README.md`

### Testing

```bash
# Run tests
go test -v ./...

# Test with module
go run . -config examples/config.toml
curl http://localhost:8080/status
```

### Error Handling

- Provider failures should not crash the service
- Failed providers return error status, not panic
- Push failures are logged but don't stop the scheduler
- HTTP errors return appropriate status codes

### Logging

Use `log.Printf()` for important events:
- Configuration loading
- Server start/stop
- Provider execution errors
- Push success/failure
- Shutdown events

Avoid verbose logging for normal operations.

## Extending the Module

### Adding Provider Types

No code changes needed! Just create a new executable that follows the provider contract.

### New Push Destinations

The current HTTP POST implementation should work for most cases. For special protocols (e.g., MQTT, gRPC), consider:
1. Adding a `type` field to `PushDestination`
2. Implementing destination-specific clients
3. Maintaining backward compatibility

### Authentication Methods

Currently supports:
- Bearer tokens via `auth` field
- Custom headers via `headers` map

For OAuth2 or other flows, consider:
- Adding auth configuration section
- Token refresh logic
- Credential management

## Performance Considerations

- Providers execute serially by design (predictable timing)
- Consider parallel execution for many providers (future enhancement)
- HTTP server handles requests concurrently
- Push scheduler runs in separate goroutine

## Security Notes

- Providers execute with service permissions (principle of least privilege)
- No shell expansion in command execution (security)
- Authentication tokens in config (consider vault integration)
- HTTP server has no built-in auth (use reverse proxy)

## Future Enhancements

Potential improvements:
- [ ] Parallel provider execution with semaphore
- [ ] Provider result caching
- [ ] Metrics persistence (time-series data)
- [ ] WebSocket support for real-time updates
- [ ] Built-in authentication for HTTP server
- [ ] gRPC support for push destinations
- [ ] Provider health checks and auto-disable
- [ ] Configuration hot-reload
- [ ] Prometheus metrics endpoint

## References

- Provider interface design inspired by Nagios/Icinga plugin API
- Push/pull patterns common in monitoring systems (Prometheus, Telegraf)
- Configuration format follows standard YAML conventions

# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /build

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source
COPY *.go ./

# Build binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o host-status .

# Runtime stage
FROM alpine:latest

# Install runtime dependencies
RUN apk --no-cache add ca-certificates bc bash coreutils

# Create non-root user
RUN addgroup -g 1000 hoststatus && \
    adduser -D -u 1000 -G hoststatus hoststatus

WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/host-status .

# Copy examples
COPY examples/ ./examples/
RUN chmod +x ./examples/providers/*.sh

# Copy example config as default
COPY examples/config.yaml ./config.yaml

# Set ownership
RUN chown -R hoststatus:hoststatus /app

# Switch to non-root user
USER hoststatus

# Expose default port
EXPOSE 8080

# Run the binary
CMD ["./host-status", "-config", "config.yaml"]

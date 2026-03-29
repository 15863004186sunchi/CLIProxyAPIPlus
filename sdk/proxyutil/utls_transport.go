// Package proxyutil provides utility functions for working with proxies and networking.
// This file implements a custom HTTP transport using utls to bypass TLS fingerprinting.
package proxyutil

import (
	"net"
	"net/http"
	"strings"
	"sync"

	utls "github.com/refraction-networking/utls"
	"github.com/router-for-me/CLIProxyAPI/v6/sdk/config"
	log "github.com/sirupsen/logrus"
	"golang.org/x/net/http2"
	"golang.org/x/net/proxy"
)

// utlsRoundTripper implements http.RoundTripper using utls with Chrome fingerprint
// to bypass TLS fingerprinting on AI service domains.
type utlsRoundTripper struct {
	// mu protects the connections map and pending map
	mu sync.Mutex
	// connections caches HTTP/2 client connections per host
	connections map[string]*http2.ClientConn
	// pending tracks hosts that are currently being connected to (prevents race condition)
	pending map[string]*sync.Cond
	// dialer is used to create network connections, supporting proxies
	dialer proxy.Dialer
}

// NewUtlsRoundTripper creates a new utls-based round tripper with optional proxy support
func NewUtlsRoundTripper(cfg *config.SDKConfig) http.RoundTripper {
	var dialer proxy.Dialer = proxy.Direct
	if cfg != nil {
		proxyDialer, mode, errBuild := BuildDialer(cfg.ProxyURL)
		if errBuild != nil {
			log.Errorf("failed to configure proxy dialer for %q: %v", cfg.ProxyURL, errBuild)
		} else if mode != ModeInherit && proxyDialer != nil {
			dialer = proxyDialer
		}
	}

	return &utlsRoundTripper{
		connections: make(map[string]*http2.ClientConn),
		pending:     make(map[string]*sync.Cond),
		dialer:      dialer,
	}
}

// getOrCreateConnection gets an existing connection or creates a new one.
// It uses a per-host locking mechanism to prevent multiple goroutines from
// creating connections to the same host simultaneously.
func (t *utlsRoundTripper) getOrCreateConnection(host, addr string) (*http2.ClientConn, error) {
	t.mu.Lock()

	// Check if connection exists and is usable
	if h2Conn, ok := t.connections[host]; ok && h2Conn.CanTakeNewRequest() {
		t.mu.Unlock()
		return h2Conn, nil
	}

	// Check if another goroutine is already creating a connection
	if cond, ok := t.pending[host]; ok {
		// Wait for the other goroutine to finish
		cond.Wait()
		// Check if connection is now available
		if h2Conn, ok := t.connections[host]; ok && h2Conn.CanTakeNewRequest() {
			t.mu.Unlock()
			return h2Conn, nil
		}
		// Connection still not available, we'll create one
	}

	// Mark this host as pending
	cond := sync.NewCond(&t.mu)
	t.pending[host] = cond
	t.mu.Unlock()

	// Create connection outside the lock
	h2Conn, err := t.createConnection(host, addr)

	t.mu.Lock()
	defer t.mu.Unlock()

	// Remove pending marker and wake up waiting goroutines
	delete(t.pending, host)
	cond.Broadcast()

	if err != nil {
		return nil, err
	}

	// Store the new connection
	t.connections[host] = h2Conn
	return h2Conn, nil
}

// createConnection creates a new HTTP/2 connection with Chrome TLS fingerprint.
func (t *utlsRoundTripper) createConnection(host, addr string) (*http2.ClientConn, error) {
	conn, err := t.dialer.Dial("tcp", addr)
	if err != nil {
		return nil, err
	}

	tlsConfig := &utls.Config{ServerName: host}
	tlsConn := utls.UClient(conn, tlsConfig, utls.HelloChrome_Auto)

	if errHandshake := tlsConn.Handshake(); errHandshake != nil {
		conn.Close()
		return nil, errHandshake
	}

	tr := &http2.Transport{}
	h2Conn, errH2 := tr.NewClientConn(tlsConn)
	if errH2 != nil {
		tlsConn.Close()
		return nil, errH2
	}

	return h2Conn, nil
}

// RoundTrip implements http.RoundTripper
func (t *utlsRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	host := req.URL.Host
	addr := host
	if !strings.Contains(addr, ":") {
		addr += ":443"
	}

	// Get hostname without port for TLS ServerName
	hostname := req.URL.Hostname()

	h2Conn, err := t.getOrCreateConnection(hostname, addr)
	if err != nil {
		return nil, err
	}

	resp, errRoundTrip := h2Conn.RoundTrip(req)
	if errRoundTrip != nil {
		// Connection failed, remove it from cache
		t.mu.Lock()
		if cached, ok := t.connections[hostname]; ok && cached == h2Conn {
			delete(t.connections, hostname)
		}
		t.mu.Unlock()
		return nil, errRoundTrip
	}

	return resp, nil
}

// NewUtlsHttpClient creates an HTTP client that bypasses TLS fingerprinting.
func NewUtlsHttpClient(cfg *config.SDKConfig) *http.Client {
	return &http.Client{
		Transport: NewUtlsRoundTripper(cfg),
	}
}

// UtlsDialer provides a websocket dialer that uses utls for TLS fingerprinting.
func UtlsDialer(parent proxy.Dialer, host string) func(network, addr string) (net.Conn, error) {
	return func(network, addr string) (net.Conn, error) {
		conn, err := parent.Dial(network, addr)
		if err != nil {
			return nil, err
		}

		tlsConfig := &utls.Config{ServerName: host}
		tlsConn := utls.UClient(conn, tlsConfig, utls.HelloChrome_Auto)

		if errH := tlsConn.Handshake(); errH != nil {
			conn.Close()
			return nil, errH
		}

		return tlsConn, nil
	}
}

package proxyutil

import (
	"net/http"
	"strings"
)

const (
	// Chrome 133 on Windows 10/11
	ChromeUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"
)

// ApplyStandardBrowserHeaders applies a set of modern Chrome headers to an outgoing request.
// This ensures that the TLS fingerprint (uTLS) matches the HTTP application layer.
func ApplyStandardBrowserHeaders(req *http.Request) {
	if req == nil {
		return
	}

	headers := req.Header

	// Basic Identity
	headers.Set("User-Agent", ChromeUserAgent)
	headers.Set("Accept", "application/json, text/plain, */*")
	headers.Set("Accept-Language", "en-US,en;q=0.9")

	// Client Hints (Sec-Ch-Ua) - Critical for modern Chrome mimicry
	headers.Set("Sec-Ch-Ua", `"Not(A:Brand";v="99", "Google Chrome";v="133", "Chromium";v="133"`)
	headers.Set("Sec-Ch-Ua-Mobile", "?0")
	headers.Set("Sec-Ch-Ua-Platform", `"Windows"`)

	// Fetch Metadata
	headers.Set("Sec-Fetch-Dest", "empty")
	headers.Set("Sec-Fetch-Mode", "cors")
	headers.Set("Sec-Fetch-Site", "same-site")

	// Origin/Referer Logic
	host := strings.ToLower(req.URL.Host)
	if strings.Contains(host, "openai.com") || strings.Contains(host, "chatgpt.com") {
		headers.Set("Origin", "https://chatgpt.com")
		if headers.Get("Referer") == "" {
			headers.Set("Referer", "https://chatgpt.com/")
		}
	} else if strings.Contains(host, "anthropic.com") || strings.Contains(host, "claude.ai") {
		headers.Set("Origin", "https://claude.ai")
		if headers.Get("Referer") == "" {
			headers.Set("Referer", "https://claude.ai/")
		}
	}
}

// ApplyStandardBrowserHeadersToMap applies the same headers to a raw http.Header map.
func ApplyStandardBrowserHeadersToMap(headers http.Header, targetHost string) {
	if headers == nil {
		return
	}

	headers.Set("User-Agent", ChromeUserAgent)
	headers.Set("Accept", "application/json, text/plain, */*")
	headers.Set("Accept-Language", "en-US,en;q=0.9")

	headers.Set("Sec-Ch-Ua", `"Not(A:Brand";v="99", "Google Chrome";v="133", "Chromium";v="133"`)
	headers.Set("Sec-Ch-Ua-Mobile", "?0")
	headers.Set("Sec-Ch-Ua-Platform", `"Windows"`)

	headers.Set("Sec-Fetch-Dest", "empty")
	headers.Set("Sec-Fetch-Mode", "cors")
	headers.Set("Sec-Fetch-Site", "same-site")

	targetHost = strings.ToLower(targetHost)
	if strings.Contains(targetHost, "openai.com") || strings.Contains(targetHost, "chatgpt.com") {
		headers.Set("Origin", "https://chatgpt.com")
		if headers.Get("Referer") == "" {
			headers.Set("Referer", "https://chatgpt.com/")
		}
	} else if strings.Contains(targetHost, "anthropic.com") || strings.Contains(targetHost, "claude.ai") {
		headers.Set("Origin", "https://claude.ai")
		if headers.Get("Referer") == "" {
			headers.Set("Referer", "https://claude.ai/")
		}
	}
}

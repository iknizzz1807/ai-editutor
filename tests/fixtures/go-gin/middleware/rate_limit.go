// middleware/rate_limit.go - Rate limiting middleware

package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

type RateLimiter struct {
	requests map[string]*clientRequests
	mu       sync.RWMutex
	limit    int
	window   time.Duration
}

type clientRequests struct {
	count    int
	lastReset time.Time
}

func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	rl := &RateLimiter{
		requests: make(map[string]*clientRequests),
		limit:    limit,
		window:   window,
	}

	// Start cleanup goroutine
	go rl.cleanup()

	return rl
}

func (rl *RateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		identifier := rl.getIdentifier(c)

		if !rl.allow(identifier) {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": "rate limit exceeded",
				"code":  "RATE_LIMITED",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

func (rl *RateLimiter) getIdentifier(c *gin.Context) string {
	// Use user ID if authenticated
	if userID, exists := c.Get("user_id"); exists {
		return "user:" + userID.(string)
	}

	// Fall back to IP address
	ip := c.ClientIP()
	return "ip:" + ip
}

func (rl *RateLimiter) allow(identifier string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()

	client, exists := rl.requests[identifier]
	if !exists {
		rl.requests[identifier] = &clientRequests{
			count:     1,
			lastReset: now,
		}
		return true
	}

	// Reset if window has passed
	if now.Sub(client.lastReset) >= rl.window {
		client.count = 1
		client.lastReset = now
		return true
	}

	// Check limit
	if client.count >= rl.limit {
		return false
	}

	client.count++
	return true
}

func (rl *RateLimiter) cleanup() {
	ticker := time.NewTicker(rl.window)
	for range ticker.C {
		rl.mu.Lock()
		now := time.Now()
		for identifier, client := range rl.requests {
			if now.Sub(client.lastReset) > rl.window*2 {
				delete(rl.requests, identifier)
			}
		}
		rl.mu.Unlock()
	}
}

// IPRateLimiter provides IP-based rate limiting with different limits per endpoint
type IPRateLimiter struct {
	limiters map[string]*RateLimiter
	defaults *RateLimiter
	mu       sync.RWMutex
}

func NewIPRateLimiter(defaultLimit int, defaultWindow time.Duration) *IPRateLimiter {
	return &IPRateLimiter{
		limiters: make(map[string]*RateLimiter),
		defaults: NewRateLimiter(defaultLimit, defaultWindow),
	}
}

func (rl *IPRateLimiter) SetEndpointLimit(path string, limit int, window time.Duration) {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	rl.limiters[path] = NewRateLimiter(limit, window)
}

func (rl *IPRateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.FullPath()

		rl.mu.RLock()
		limiter, exists := rl.limiters[path]
		rl.mu.RUnlock()

		if !exists {
			limiter = rl.defaults
		}

		identifier := "ip:" + c.ClientIP()

		if !limiter.allow(identifier) {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": "rate limit exceeded",
				"code":  "RATE_LIMITED",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// SlidingWindowRateLimiter uses sliding window algorithm for more accurate limiting
type SlidingWindowRateLimiter struct {
	requests map[string][]time.Time
	mu       sync.RWMutex
	limit    int
	window   time.Duration
}

func NewSlidingWindowRateLimiter(limit int, window time.Duration) *SlidingWindowRateLimiter {
	return &SlidingWindowRateLimiter{
		requests: make(map[string][]time.Time),
		limit:    limit,
		window:   window,
	}
}

// Q: What are the tradeoffs between fixed window vs sliding window rate limiting?
func (rl *SlidingWindowRateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		identifier := "ip:" + c.ClientIP()
		if userID, exists := c.Get("user_id"); exists {
			identifier = "user:" + userID.(string)
		}

		if !rl.allow(identifier) {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": "rate limit exceeded",
				"code":  "RATE_LIMITED",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

func (rl *SlidingWindowRateLimiter) allow(identifier string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	windowStart := now.Add(-rl.window)

	// Get existing timestamps
	timestamps, exists := rl.requests[identifier]
	if !exists {
		timestamps = []time.Time{}
	}

	// Filter out old timestamps
	var validTimestamps []time.Time
	for _, ts := range timestamps {
		if ts.After(windowStart) {
			validTimestamps = append(validTimestamps, ts)
		}
	}

	// Check if over limit
	if len(validTimestamps) >= rl.limit {
		rl.requests[identifier] = validTimestamps
		return false
	}

	// Add current timestamp
	validTimestamps = append(validTimestamps, now)
	rl.requests[identifier] = validTimestamps

	return true
}

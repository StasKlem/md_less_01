package ratelimit

import (
	"testing"
	"time"
)

func TestFixedWindowLimiter(t *testing.T) {
	limiter := NewFixedWindowLimiter(2, time.Minute)
	now := time.Unix(1, 0)

	if !limiter.Allow("a", now) {
		t.Fatal("first request should be allowed")
	}
	if !limiter.Allow("a", now.Add(time.Second)) {
		t.Fatal("second request should be allowed")
	}
	if limiter.Allow("a", now.Add(2*time.Second)) {
		t.Fatal("third request should be blocked")
	}
	if !limiter.Allow("a", now.Add(time.Minute)) {
		t.Fatal("window reset should allow request")
	}
}

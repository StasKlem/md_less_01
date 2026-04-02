package ratelimit

import (
	"sync"
	"time"
)

type FixedWindowLimiter struct {
	limit  int
	window time.Duration
	mu     sync.Mutex
	items  map[string]*windowState
}

type windowState struct {
	start time.Time
	count int
}

func NewFixedWindowLimiter(limit int, window time.Duration) *FixedWindowLimiter {
	return &FixedWindowLimiter{
		limit:  limit,
		window: window,
		items:  make(map[string]*windowState),
	}
}

func (l *FixedWindowLimiter) Allow(key string, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	state, ok := l.items[key]
	if !ok || now.Sub(state.start) >= l.window {
		l.items[key] = &windowState{start: now, count: 1}
		return true
	}

	if state.count >= l.limit {
		return false
	}

	state.count++
	return true
}

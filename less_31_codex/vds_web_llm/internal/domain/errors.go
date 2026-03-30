package domain

import "errors"

var (
	ErrUnauthorized    = errors.New("unauthorized")
	ErrRateLimited     = errors.New("rate limited")
	ErrContextExceeded = errors.New("context limit exceeded")
	ErrUpstreamFailure = errors.New("upstream failure")
	ErrInvalidRequest  = errors.New("invalid request")
)

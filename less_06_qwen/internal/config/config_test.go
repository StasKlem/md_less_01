package config_test

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/stasklem/kbju-bot/internal/config"
)

func TestAccessControlConfig_IsWhitelistMode(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		mode     config.AccessMode
		expected bool
	}{
		{
			name:     "whitelist mode",
			mode:     config.AccessModeWhitelist,
			expected: true,
		},
		{
			name:     "public mode",
			mode:     config.AccessModePublic,
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			cfg := config.AccessControlConfig{Mode: tt.mode}
			assert.Equal(t, tt.expected, cfg.IsWhitelistMode())
		})
	}
}

func TestAccessControlConfig_IsUserAllowed_PublicMode(t *testing.T) {
	t.Parallel()

	cfg := config.AccessControlConfig{
		Mode:           config.AccessModePublic,
		AllowedUserIDs: []int64{},
	}

	// В public режиме все пользователи разрешены
	assert.True(t, cfg.IsUserAllowed(123456789))
	assert.True(t, cfg.IsUserAllowed(999999999))
}

func TestAccessControlConfig_IsUserAllowed_WhitelistMode(t *testing.T) {
	t.Parallel()

	cfg := config.AccessControlConfig{
		Mode:           config.AccessModeWhitelist,
		AllowedUserIDs: []int64{111, 222, 333},
	}

	tests := []struct {
		name     string
		userID   int64
		expected bool
	}{
		{
			name:     "user in whitelist",
			userID:   111,
			expected: true,
		},
		{
			name:     "user in whitelist middle",
			userID:   222,
			expected: true,
		},
		{
			name:     "user not in whitelist",
			userID:   444,
			expected: false,
		},
		{
			name:     "user not in whitelist negative",
			userID:   -1,
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			assert.Equal(t, tt.expected, cfg.IsUserAllowed(tt.userID))
		})
	}
}

func TestAccessControlConfig_IsUserAllowed_EmptyWhitelist(t *testing.T) {
	t.Parallel()

	cfg := config.AccessControlConfig{
		Mode:           config.AccessModeWhitelist,
		AllowedUserIDs: []int64{},
	}

	// В whitelist режиме с пустым списком все пользователи запрещены
	assert.False(t, cfg.IsUserAllowed(123456789))
}

package domain

import "unicode/utf8"

func EstimateTokens(messages []Message) int {
	totalRunes := 0
	for _, msg := range messages {
		totalRunes += utf8.RuneCountInString(msg.Role)
		totalRunes += utf8.RuneCountInString(msg.Content)
	}
	if totalRunes == 0 {
		return 0
	}
	// Approximate 1 token ~= 4 runes for mixed-language text.
	return (totalRunes + 3) / 4
}

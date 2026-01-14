// Package config handles application configuration
package config

import (
	"os"
	"time"
)

// Config holds all configuration values
type Config struct {
	// Database
	DatabaseURL string

	// JWT
	JWTSecret           string
	AccessTokenDuration time.Duration

	// Server
	Port string
}

// Load loads configuration from environment
func Load() *Config {
	return &Config{
		DatabaseURL:         getEnv("DATABASE_URL", "postgres://localhost/myapp?sslmode=disable"),
		JWTSecret:           getEnv("JWT_SECRET", "your-secret-key"),
		AccessTokenDuration: 30 * time.Minute,
		Port:                getEnv("PORT", "8080"),
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

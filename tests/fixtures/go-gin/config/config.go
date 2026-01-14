// config/config.go - Application configuration

package config

import (
	"os"
	"strconv"
	"time"
)

type Config struct {
	App      AppConfig
	Database DatabaseConfig
	Auth     AuthConfig
	Email    EmailConfig
	Cache    CacheConfig
}

type AppConfig struct {
	Name        string
	Environment string
	Port        int
	BaseURL     string
	Debug       bool
}

type DatabaseConfig struct {
	Host     string
	Port     int
	Name     string
	User     string
	Password string
	SSLMode  string
}

type AuthConfig struct {
	JWTSecret          string
	RefreshSecret      string
	AccessTokenExpiry  int64 // seconds
	RefreshTokenExpiry int64 // seconds
	BCryptCost         int
}

type EmailConfig struct {
	SMTPHost       string
	SMTPPort       int
	Username       string
	Password       string
	FromAddress    string
	SupportAddress string
	UseTLS         bool
}

type CacheConfig struct {
	RedisURL    string
	DefaultTTL  time.Duration
	MaxSize     int
}

func Load() *Config {
	return &Config{
		App: AppConfig{
			Name:        getEnv("APP_NAME", "MyApp"),
			Environment: getEnv("APP_ENV", "development"),
			Port:        getEnvInt("APP_PORT", 8080),
			BaseURL:     getEnv("APP_BASE_URL", "http://localhost:8080"),
			Debug:       getEnvBool("APP_DEBUG", true),
		},
		Database: DatabaseConfig{
			Host:     getEnv("DB_HOST", "localhost"),
			Port:     getEnvInt("DB_PORT", 5432),
			Name:     getEnv("DB_NAME", "myapp"),
			User:     getEnv("DB_USER", "postgres"),
			Password: getEnv("DB_PASSWORD", ""),
			SSLMode:  getEnv("DB_SSLMODE", "disable"),
		},
		Auth: AuthConfig{
			JWTSecret:          getEnv("JWT_SECRET", "change-me-in-production"),
			RefreshSecret:      getEnv("REFRESH_SECRET", "change-me-in-production"),
			AccessTokenExpiry:  getEnvInt64("ACCESS_TOKEN_EXPIRY", 900),    // 15 minutes
			RefreshTokenExpiry: getEnvInt64("REFRESH_TOKEN_EXPIRY", 604800), // 7 days
			BCryptCost:         getEnvInt("BCRYPT_COST", 10),
		},
		Email: EmailConfig{
			SMTPHost:       getEnv("SMTP_HOST", "localhost"),
			SMTPPort:       getEnvInt("SMTP_PORT", 587),
			Username:       getEnv("SMTP_USERNAME", ""),
			Password:       getEnv("SMTP_PASSWORD", ""),
			FromAddress:    getEnv("EMAIL_FROM", "noreply@example.com"),
			SupportAddress: getEnv("EMAIL_SUPPORT", "support@example.com"),
			UseTLS:         getEnvBool("SMTP_TLS", true),
		},
		Cache: CacheConfig{
			RedisURL:   getEnv("REDIS_URL", "redis://localhost:6379"),
			DefaultTTL: time.Duration(getEnvInt("CACHE_TTL", 3600)) * time.Second,
			MaxSize:    getEnvInt("CACHE_MAX_SIZE", 10000),
		},
	}
}

func (c *Config) DSN() string {
	return "host=" + c.Database.Host +
		" port=" + strconv.Itoa(c.Database.Port) +
		" user=" + c.Database.User +
		" password=" + c.Database.Password +
		" dbname=" + c.Database.Name +
		" sslmode=" + c.Database.SSLMode
}

func (c *Config) IsProduction() bool {
	return c.App.Environment == "production"
}

func (c *Config) IsDevelopment() bool {
	return c.App.Environment == "development"
}

func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value, exists := os.LookupEnv(key); exists {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
	}
	return defaultValue
}

func getEnvInt64(key string, defaultValue int64) int64 {
	if value, exists := os.LookupEnv(key); exists {
		if intVal, err := strconv.ParseInt(value, 10, 64); err == nil {
			return intVal
		}
	}
	return defaultValue
}

func getEnvBool(key string, defaultValue bool) bool {
	if value, exists := os.LookupEnv(key); exists {
		if boolVal, err := strconv.ParseBool(value); err == nil {
			return boolVal
		}
	}
	return defaultValue
}

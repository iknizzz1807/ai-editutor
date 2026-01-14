// main.go - Application entry point

package main

import (
	"fmt"
	"log"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"myapp/config"
	"myapp/handler"
	"myapp/middleware"
	"myapp/models"
	"myapp/repository"
	"myapp/service"
)

func main() {
	// Load configuration
	cfg := config.Load()

	// Set Gin mode
	if cfg.IsProduction() {
		gin.SetMode(gin.ReleaseMode)
	}

	// Initialize database
	db, err := initDatabase(cfg)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	// Auto migrate
	if err := db.AutoMigrate(
		&models.User{},
		&models.UserProfile{},
		&models.UserAddress{},
		&models.UserPreferences{},
	); err != nil {
		log.Fatalf("Failed to migrate database: %v", err)
	}

	// Initialize repositories
	userRepo := repository.NewUserRepository(db)

	// Initialize services
	emailService := service.NewEmailService(cfg)
	userService := service.NewUserService(userRepo, emailService)

	// Initialize handlers
	userHandler := handler.NewUserHandler(userService)

	// Initialize middleware
	authMiddleware := middleware.NewAuthMiddleware(cfg)
	rateLimiter := middleware.NewRateLimiter(100, time.Minute)

	// Create router
	router := gin.Default()

	// Global middleware
	router.Use(rateLimiter.Middleware())

	// Public routes
	public := router.Group("/api/v1")
	{
		public.POST("/register", userHandler.CreateUser)
		public.POST("/login", func(c *gin.Context) {
			// Login handler would go here
		})
		public.POST("/refresh-token", authMiddleware.RefreshToken())
	}

	// Protected routes
	protected := router.Group("/api/v1")
	protected.Use(authMiddleware.Authenticate())
	{
		userHandler.RegisterRoutes(protected)
	}

	// Admin routes
	admin := router.Group("/api/v1/admin")
	admin.Use(authMiddleware.Authenticate())
	admin.Use(authMiddleware.RequireAdmin())
	{
		admin.GET("/users/stats", userHandler.GetStats)
	}

	// Start server
	addr := fmt.Sprintf(":%d", cfg.App.Port)
	log.Printf("Server starting on %s", addr)
	if err := router.Run(addr); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func initDatabase(cfg *config.Config) (*gorm.DB, error) {
	db, err := gorm.Open(postgres.Open(cfg.DSN()), &gorm.Config{})
	if err != nil {
		return nil, err
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, err
	}

	// Connection pool settings
	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetMaxOpenConns(100)
	sqlDB.SetConnMaxLifetime(time.Hour)

	return db, nil
}

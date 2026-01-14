// Package handlers contains HTTP handlers
package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"myapp/internal/models"
	"myapp/internal/services"
)

// UserHandler handles user-related HTTP requests
type UserHandler struct {
	userService *services.UserService
	authService *services.AuthService
}

// NewUserHandler creates a new user handler
func NewUserHandler(userService *services.UserService, authService *services.AuthService) *UserHandler {
	return &UserHandler{
		userService: userService,
		authService: authService,
	}
}

// List returns a paginated list of users
// @Summary List users
// @Tags users
// @Accept json
// @Produce json
// @Param role query string false "Filter by role"
// @Param search query string false "Search by name or email"
// @Param page query int false "Page number" default(1)
// @Param limit query int false "Items per page" default(20)
// @Success 200 {object} services.PaginatedResult
// @Router /users [get]
func (h *UserHandler) List(c *gin.Context) {
	var filters models.UserFilters
	if err := c.ShouldBindQuery(&filters); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	result, err := h.userService.List(filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list users"})
		return
	}

	c.JSON(http.StatusOK, result)
}

// GetByID returns a user by ID
// @Summary Get user by ID
// @Tags users
// @Accept json
// @Produce json
// @Param id path string true "User ID"
// @Success 200 {object} models.User
// @Router /users/{id} [get]
func (h *UserHandler) GetByID(c *gin.Context) {
	id := c.Param("id")

	user, err := h.userService.GetByID(id)
	if err != nil {
		if err == services.ErrUserNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get user"})
		return
	}

	c.JSON(http.StatusOK, user)
}

// Q: What happens if validation fails for the create input?
// Create creates a new user
// @Summary Create user
// @Tags users
// @Accept json
// @Produce json
// @Param input body models.CreateUserInput true "User data"
// @Success 201 {object} models.User
// @Router /users [post]
func (h *UserHandler) Create(c *gin.Context) {
	// Get current user from context (set by auth middleware)
	currentUser, exists := c.Get("user")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	// Check admin role
	if !h.authService.HasRole(currentUser.(*models.User), models.RoleAdmin) {
		c.JSON(http.StatusForbidden, gin.H{"error": "Admin role required"})
		return
	}

	var input models.CreateUserInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.userService.Create(input)
	if err != nil {
		if err == services.ErrEmailExists {
			c.JSON(http.StatusConflict, gin.H{"error": "Email already exists"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user"})
		return
	}

	c.JSON(http.StatusCreated, user)
}

// Update updates an existing user
func (h *UserHandler) Update(c *gin.Context) {
	id := c.Param("id")

	currentUser, exists := c.Get("user")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	user := currentUser.(*models.User)

	// Allow self-update or admin update
	if user.ID != id && !h.authService.HasRole(user, models.RoleAdmin) {
		c.JSON(http.StatusForbidden, gin.H{"error": "Forbidden"})
		return
	}

	var input models.UpdateUserInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	updated, err := h.userService.Update(id, input)
	if err != nil {
		if err == services.ErrUserNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}
		if err == services.ErrEmailExists {
			c.JSON(http.StatusConflict, gin.H{"error": "Email already exists"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update user"})
		return
	}

	c.JSON(http.StatusOK, updated)
}

// Delete deletes a user
func (h *UserHandler) Delete(c *gin.Context) {
	id := c.Param("id")

	currentUser, exists := c.Get("user")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	if !h.authService.HasRole(currentUser.(*models.User), models.RoleAdmin) {
		c.JSON(http.StatusForbidden, gin.H{"error": "Admin role required"})
		return
	}

	if err := h.userService.Delete(id); err != nil {
		if err == services.ErrUserNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete user"})
		return
	}

	c.Status(http.StatusNoContent)
}

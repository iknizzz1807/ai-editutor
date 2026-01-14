// src/main/java/com/myapp/controller/UserController.java - User REST controller

package com.myapp.controller;

import com.myapp.dto.*;
import com.myapp.model.User;
import com.myapp.model.UserRole;
import com.myapp.service.UserService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/v1/users")
@RequiredArgsConstructor
@Tag(name = "Users", description = "User management endpoints")
public class UserController {

    private final UserService userService;

    @GetMapping
    @PreAuthorize("hasRole('ADMIN') or hasRole('MODERATOR')")
    @Operation(summary = "List all users")
    public ResponseEntity<PagedResponse<UserResponse>> listUsers(
            @RequestParam(required = false) UserRole role,
            Pageable pageable) {

        Page<User> users;
        if (role != null) {
            users = userService.listUsersByRole(role, pageable);
        } else {
            users = userService.listUsers(pageable);
        }

        List<UserResponse> content = users.getContent().stream()
            .map(UserResponse::from)
            .collect(Collectors.toList());

        return ResponseEntity.ok(PagedResponse.<UserResponse>builder()
            .content(content)
            .page(users.getNumber())
            .pageSize(users.getSize())
            .totalElements(users.getTotalElements())
            .totalPages(users.getTotalPages())
            .build());
    }

    @GetMapping("/{id}")
    @Operation(summary = "Get user by ID")
    public ResponseEntity<UserDetailResponse> getUser(@PathVariable UUID id) {
        User user = userService.getUser(id);
        return ResponseEntity.ok(UserDetailResponse.from(user));
    }

    // Q: How should we handle validation errors and return structured error responses?
    @PostMapping
    @Operation(summary = "Create new user")
    public ResponseEntity<UserResponse> createUser(@Valid @RequestBody CreateUserRequest request) {
        User user = userService.createUser(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(UserResponse.from(user));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN') or @userSecurity.isOwner(#id)")
    @Operation(summary = "Update user")
    public ResponseEntity<UserResponse> updateUser(
            @PathVariable UUID id,
            @Valid @RequestBody UpdateUserRequest request) {
        User user = userService.updateUser(id, request);
        return ResponseEntity.ok(UserResponse.from(user));
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN') or @userSecurity.isOwner(#id)")
    @Operation(summary = "Delete user")
    public ResponseEntity<Void> deleteUser(@PathVariable UUID id) {
        userService.deleteUser(id);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/me")
    @Operation(summary = "Get current user")
    public ResponseEntity<UserDetailResponse> getCurrentUser(@AuthenticationPrincipal UserPrincipal principal) {
        User user = userService.getUser(principal.getId());
        return ResponseEntity.ok(UserDetailResponse.from(user));
    }

    @PatchMapping("/me/profile")
    @Operation(summary = "Update current user's profile")
    public ResponseEntity<UserDetailResponse> updateProfile(
            @AuthenticationPrincipal UserPrincipal principal,
            @Valid @RequestBody UpdateProfileRequest request) {
        // Would implement profile update
        User user = userService.getUser(principal.getId());
        return ResponseEntity.ok(UserDetailResponse.from(user));
    }

    @PostMapping("/me/change-password")
    @Operation(summary = "Change password")
    public ResponseEntity<MessageResponse> changePassword(
            @AuthenticationPrincipal UserPrincipal principal,
            @Valid @RequestBody ChangePasswordRequest request) {
        userService.changePassword(principal.getId(), request.getCurrentPassword(), request.getNewPassword());
        return ResponseEntity.ok(new MessageResponse("Password changed successfully"));
    }

    @PostMapping("/{id}/activate")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Activate user")
    public ResponseEntity<UserResponse> activateUser(@PathVariable UUID id) {
        User user = userService.activateUser(id);
        return ResponseEntity.ok(UserResponse.from(user));
    }

    @PostMapping("/{id}/suspend")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Suspend user")
    public ResponseEntity<UserResponse> suspendUser(
            @PathVariable UUID id,
            @Valid @RequestBody SuspendUserRequest request) {
        User user = userService.suspendUser(id, request.getReason(), request.getDurationDays());
        return ResponseEntity.ok(UserResponse.from(user));
    }

    @GetMapping("/stats")
    @PreAuthorize("hasRole('ADMIN')")
    @Operation(summary = "Get user statistics")
    public ResponseEntity<UserStats> getStats() {
        return ResponseEntity.ok(userService.getStats());
    }

    @GetMapping("/search")
    @Operation(summary = "Search users")
    public ResponseEntity<List<UserResponse>> searchUsers(
            @RequestParam String q,
            Pageable pageable) {
        List<UserResponse> users = userService.searchUsers(q, pageable).stream()
            .map(UserResponse::from)
            .collect(Collectors.toList());
        return ResponseEntity.ok(users);
    }
}

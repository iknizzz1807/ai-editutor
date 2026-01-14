// src/main/java/com/myapp/service/UserService.java - User service

package com.myapp.service;

import com.myapp.dto.CreateUserRequest;
import com.myapp.dto.UpdateUserRequest;
import com.myapp.dto.UserStats;
import com.myapp.exception.ConflictException;
import com.myapp.exception.NotFoundException;
import com.myapp.exception.UnauthorizedException;
import com.myapp.model.User;
import com.myapp.model.UserProfile;
import com.myapp.model.UserPreferences;
import com.myapp.model.UserRole;
import com.myapp.model.UserStatus;
import com.myapp.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final EmailService emailService;

    @Transactional
    public User createUser(CreateUserRequest request) {
        // Check email uniqueness
        if (userRepository.existsByEmailAndDeletedAtIsNull(request.getEmail())) {
            throw new ConflictException("Email already registered");
        }

        // Check username uniqueness
        if (userRepository.existsByUsernameAndDeletedAtIsNull(request.getUsername())) {
            throw new ConflictException("Username already taken");
        }

        // Create user
        User user = User.builder()
            .email(request.getEmail())
            .username(request.getUsername())
            .passwordHash(passwordEncoder.encode(request.getPassword()))
            .role(UserRole.USER)
            .status(UserStatus.PENDING)
            .build();

        user = userRepository.save(user);

        // Create profile
        UserProfile profile = UserProfile.builder()
            .user(user)
            .firstName(request.getFirstName())
            .lastName(request.getLastName())
            .build();
        user.setProfile(profile);

        // Create preferences
        UserPreferences preferences = UserPreferences.builder()
            .user(user)
            .build();
        user.setPreferences(preferences);

        // Send verification email
        if (request.isSendVerification()) {
            emailService.sendVerificationEmail(user);
        }

        return userRepository.save(user);
    }

    public User getUser(UUID id) {
        return userRepository.findByIdAndDeletedAtIsNull(id)
            .orElseThrow(() -> new NotFoundException("User not found"));
    }

    public User getUserByEmail(String email) {
        return userRepository.findByEmailAndDeletedAtIsNull(email)
            .orElseThrow(() -> new NotFoundException("User not found"));
    }

    // Q: What's the best approach for implementing optimistic locking to handle concurrent updates?
    @Transactional
    public User updateUser(UUID id, UpdateUserRequest request) {
        User user = getUser(id);

        if (request.getUsername() != null && !request.getUsername().equals(user.getUsername())) {
            if (userRepository.existsByUsernameAndDeletedAtIsNull(request.getUsername())) {
                throw new ConflictException("Username already taken");
            }
            user.setUsername(request.getUsername());
        }

        if (request.getRole() != null) {
            user.setRole(request.getRole());
        }

        if (request.getStatus() != null) {
            user.setStatus(request.getStatus());
        }

        return userRepository.save(user);
    }

    @Transactional
    public User activateUser(UUID id) {
        User user = getUser(id);
        user.setStatus(UserStatus.ACTIVE);
        user.setEmailVerified(true);
        return userRepository.save(user);
    }

    @Transactional
    public User suspendUser(UUID id, String reason, Integer durationDays) {
        User user = getUser(id);
        user.setStatus(UserStatus.SUSPENDED);
        user = userRepository.save(user);

        emailService.sendSuspensionNotice(user, reason, durationDays);

        return user;
    }

    @Transactional
    public void deleteUser(UUID id) {
        User user = getUser(id);
        user.softDelete();
        userRepository.save(user);
    }

    public Page<User> listUsers(Pageable pageable) {
        return userRepository.findAllByDeletedAtIsNull(pageable);
    }

    public Page<User> listUsersByRole(UserRole role, Pageable pageable) {
        return userRepository.findByRoleAndDeletedAtIsNull(role, pageable);
    }

    public List<User> searchUsers(String query, Pageable pageable) {
        return userRepository.search(query, pageable);
    }

    @Transactional
    public void changePassword(UUID userId, String currentPassword, String newPassword) {
        User user = getUser(userId);

        if (!passwordEncoder.matches(currentPassword, user.getPasswordHash())) {
            throw new UnauthorizedException("Invalid current password");
        }

        user.setPasswordHash(passwordEncoder.encode(newPassword));
        userRepository.save(user);
    }

    public User authenticate(String email, String password) {
        User user = userRepository.findByEmailAndDeletedAtIsNull(email)
            .orElseThrow(() -> new UnauthorizedException("Invalid credentials"));

        if (!passwordEncoder.matches(password, user.getPasswordHash())) {
            throw new UnauthorizedException("Invalid credentials");
        }

        if (user.getStatus() == UserStatus.SUSPENDED) {
            throw new UnauthorizedException("Account suspended");
        }

        return user;
    }

    @Transactional
    public void updateLastLogin(UUID userId, String ip) {
        userRepository.updateLastLogin(userId, LocalDateTime.now(), ip);
    }

    public UserStats getStats() {
        LocalDateTime monthAgo = LocalDateTime.now().minusDays(30);

        Map<String, Long> byRole = new HashMap<>();
        for (Object[] result : userRepository.countByRole()) {
            byRole.put(result[0].toString(), (Long) result[1]);
        }

        Map<String, Long> byStatus = new HashMap<>();
        for (Object[] result : userRepository.countByStatus()) {
            byStatus.put(result[0].toString(), (Long) result[1]);
        }

        return UserStats.builder()
            .total(userRepository.countActive())
            .active(userRepository.countByStatusActive())
            .verified(userRepository.countVerified())
            .newThisMonth(userRepository.countNewSince(monthAgo))
            .byRole(byRole)
            .byStatus(byStatus)
            .build();
    }

    public List<User> getInactiveUsers(int days) {
        LocalDateTime cutoff = LocalDateTime.now().minusDays(days);
        return userRepository.findInactiveUsers(cutoff);
    }

    @Transactional
    public int bulkUpdateStatus(List<UUID> userIds, UserStatus status) {
        return userRepository.bulkUpdateStatus(userIds, status);
    }
}

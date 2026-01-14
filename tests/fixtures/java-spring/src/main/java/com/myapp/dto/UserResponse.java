// src/main/java/com/myapp/dto/UserResponse.java - User DTOs

package com.myapp.dto;

import com.myapp.model.*;
import lombok.*;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class UserResponse {
    private UUID id;
    private String email;
    private String username;
    private UserRole role;
    private UserStatus status;
    private boolean emailVerified;
    private String fullName;
    private LocalDateTime createdAt;

    public static UserResponse from(User user) {
        return UserResponse.builder()
            .id(user.getId())
            .email(user.getEmail())
            .username(user.getUsername())
            .role(user.getRole())
            .status(user.getStatus())
            .emailVerified(user.isEmailVerified())
            .fullName(user.getFullName())
            .createdAt(user.getCreatedAt())
            .build();
    }
}

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
class UserDetailResponse {
    private UUID id;
    private String email;
    private String username;
    private UserRole role;
    private UserStatus status;
    private boolean emailVerified;
    private String fullName;
    private LocalDateTime lastLoginAt;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
    private ProfileResponse profile;
    private PreferencesResponse preferences;
    private List<AddressResponse> addresses;

    public static UserDetailResponse from(User user) {
        return UserDetailResponse.builder()
            .id(user.getId())
            .email(user.getEmail())
            .username(user.getUsername())
            .role(user.getRole())
            .status(user.getStatus())
            .emailVerified(user.isEmailVerified())
            .fullName(user.getFullName())
            .lastLoginAt(user.getLastLoginAt())
            .createdAt(user.getCreatedAt())
            .updatedAt(user.getUpdatedAt())
            .profile(user.getProfile() != null ? ProfileResponse.from(user.getProfile()) : null)
            .preferences(user.getPreferences() != null ? PreferencesResponse.from(user.getPreferences()) : null)
            .addresses(user.getAddresses().stream().map(AddressResponse::from).collect(Collectors.toList()))
            .build();
    }
}

@Data
@Builder
class ProfileResponse {
    private String firstName;
    private String lastName;
    private String avatar;
    private String bio;
    private String phone;

    public static ProfileResponse from(UserProfile profile) {
        return ProfileResponse.builder()
            .firstName(profile.getFirstName())
            .lastName(profile.getLastName())
            .avatar(profile.getAvatar())
            .bio(profile.getBio())
            .phone(profile.getPhone())
            .build();
    }
}

@Data
@Builder
class PreferencesResponse {
    private String theme;
    private String language;
    private String timezone;
    private boolean emailNotifications;
    private boolean pushNotifications;
    private boolean smsNotifications;

    public static PreferencesResponse from(UserPreferences preferences) {
        return PreferencesResponse.builder()
            .theme(preferences.getTheme())
            .language(preferences.getLanguage())
            .timezone(preferences.getTimezone())
            .emailNotifications(preferences.isEmailNotifications())
            .pushNotifications(preferences.isPushNotifications())
            .smsNotifications(preferences.isSmsNotifications())
            .build();
    }
}

@Data
@Builder
class AddressResponse {
    private UUID id;
    private String label;
    private String street;
    private String city;
    private String state;
    private String country;
    private String zipCode;
    private boolean isDefault;

    public static AddressResponse from(UserAddress address) {
        return AddressResponse.builder()
            .id(address.getId())
            .label(address.getLabel())
            .street(address.getStreet())
            .city(address.getCity())
            .state(address.getState())
            .country(address.getCountry())
            .zipCode(address.getZipCode())
            .isDefault(address.isDefault())
            .build();
    }
}

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
class PagedResponse<T> {
    private List<T> content;
    private int page;
    private int pageSize;
    private long totalElements;
    private int totalPages;
}

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
class UserStats {
    private long total;
    private long active;
    private long verified;
    private long newThisMonth;
    private Map<String, Long> byRole;
    private Map<String, Long> byStatus;
}

@Data
@NoArgsConstructor
@AllArgsConstructor
class MessageResponse {
    private String message;
}

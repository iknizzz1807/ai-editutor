// include/models/user.hpp - User model definitions

#ifndef MODELS_USER_HPP
#define MODELS_USER_HPP

#include <string>
#include <optional>
#include <chrono>
#include <vector>
#include <memory>

namespace myapp {
namespace models {

enum class UserRole {
    Admin,
    Moderator,
    User,
    Guest
};

enum class UserStatus {
    Active,
    Inactive,
    Suspended,
    Pending
};

struct UserProfile {
    std::string first_name;
    std::string last_name;
    std::optional<std::string> avatar;
    std::optional<std::string> bio;
    std::optional<std::string> phone;

    std::string get_full_name() const {
        return first_name + " " + last_name;
    }
};

struct UserPreferences {
    std::string theme = "system";
    std::string language = "en";
    std::string timezone = "UTC";
    bool email_notifications = true;
    bool push_notifications = true;
    bool sms_notifications = false;
};

struct UserAddress {
    int64_t id;
    std::string label;
    std::string street;
    std::string city;
    std::string state;
    std::string country;
    std::string zip_code;
    bool is_default = false;
};

class User {
public:
    User() = default;
    User(const std::string& email, const std::string& username);

    // Getters
    int64_t get_id() const { return id_; }
    const std::string& get_email() const { return email_; }
    const std::string& get_username() const { return username_; }
    UserRole get_role() const { return role_; }
    UserStatus get_status() const { return status_; }
    bool is_email_verified() const { return email_verified_; }

    // Setters
    void set_email(const std::string& email) { email_ = email; }
    void set_username(const std::string& username) { username_ = username; }
    void set_role(UserRole role) { role_ = role; }
    void set_status(UserStatus status) { status_ = status; }
    void set_email_verified(bool verified) { email_verified_ = verified; }
    void set_password_hash(const std::string& hash) { password_hash_ = hash; }

    // Profile management
    void set_profile(std::unique_ptr<UserProfile> profile) { profile_ = std::move(profile); }
    const UserProfile* get_profile() const { return profile_.get(); }

    // Preferences management
    void set_preferences(std::unique_ptr<UserPreferences> prefs) { preferences_ = std::move(prefs); }
    const UserPreferences* get_preferences() const { return preferences_.get(); }

    // Address management
    void add_address(const UserAddress& address);
    const std::vector<UserAddress>& get_addresses() const { return addresses_; }

    // Utility methods
    std::string get_full_name() const;
    bool is_active() const;
    bool is_admin() const;
    bool verify_password(const std::string& password) const;

    // Timestamps
    std::chrono::system_clock::time_point created_at;
    std::chrono::system_clock::time_point updated_at;
    std::optional<std::chrono::system_clock::time_point> last_login_at;
    std::optional<std::string> last_login_ip;

private:
    int64_t id_ = 0;
    std::string email_;
    std::string username_;
    std::string password_hash_;
    UserRole role_ = UserRole::User;
    UserStatus status_ = UserStatus::Pending;
    bool email_verified_ = false;

    std::unique_ptr<UserProfile> profile_;
    std::unique_ptr<UserPreferences> preferences_;
    std::vector<UserAddress> addresses_;
};

// DTOs
struct CreateUserDTO {
    std::string email;
    std::string username;
    std::string password;
    std::optional<std::string> first_name;
    std::optional<std::string> last_name;
};

struct UpdateUserDTO {
    std::optional<std::string> username;
    std::optional<UserRole> role;
    std::optional<UserStatus> status;
};

struct UserResponseDTO {
    int64_t id;
    std::string email;
    std::string username;
    UserRole role;
    UserStatus status;
    bool email_verified;
    std::string full_name;

    static UserResponseDTO from_user(const User& user);
};

} // namespace models
} // namespace myapp

#endif // MODELS_USER_HPP

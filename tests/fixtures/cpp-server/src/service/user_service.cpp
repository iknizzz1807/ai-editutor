// src/service/user_service.cpp - User service implementation

#include "service/user_service.hpp"
#include "service/email_service.hpp"
#include "utils/validation.hpp"
#include <stdexcept>
#include <bcrypt/bcrypt.h>  // Would use actual bcrypt library

namespace myapp {
namespace service {

UserService::UserService(
    std::shared_ptr<repository::IUserRepository> user_repo,
    std::shared_ptr<EmailService> email_service
) : user_repo_(std::move(user_repo)), email_service_(std::move(email_service)) {}

UserService::~UserService() = default;

models::User UserService::create_user(const models::CreateUserDTO& dto, bool send_verification) {
    // Validate input
    auto email_result = utils::Validator::validate_email(dto.email);
    if (!email_result) {
        throw std::invalid_argument("Invalid email: " + email_result.errors[0]);
    }

    auto username_result = utils::Validator::validate_username(dto.username);
    if (!username_result) {
        throw std::invalid_argument("Invalid username: " + username_result.errors[0]);
    }

    auto password_result = utils::Validator::validate_password(dto.password);
    if (!password_result) {
        throw std::invalid_argument("Invalid password: " + password_result.errors[0]);
    }

    // Check uniqueness
    if (user_repo_->find_by_email(dto.email)) {
        throw std::runtime_error("Email already registered");
    }
    if (user_repo_->find_by_username(dto.username)) {
        throw std::runtime_error("Username already taken");
    }

    // Create user
    models::User user(dto.email, dto.username);
    user.set_password_hash(hash_password(dto.password));
    user.set_role(models::UserRole::User);
    user.set_status(models::UserStatus::Pending);

    // Create profile
    auto profile = std::make_unique<models::UserProfile>();
    if (dto.first_name) profile->first_name = *dto.first_name;
    if (dto.last_name) profile->last_name = *dto.last_name;
    user.set_profile(std::move(profile));

    // Create preferences
    user.set_preferences(std::make_unique<models::UserPreferences>());

    // Save
    auto created_user = user_repo_->create(user);

    // Send verification email
    if (send_verification) {
        email_service_->send_verification_email(created_user);
    }

    return created_user;
}

models::User UserService::get_user(int64_t id) {
    auto user = user_repo_->find_by_id(id);
    if (!user) {
        throw std::runtime_error("User not found");
    }
    return *user;
}

std::optional<models::User> UserService::get_user_by_email(const std::string& email) {
    return user_repo_->find_by_email(email);
}

// Q: How should we implement optimistic locking to prevent lost updates?
models::User UserService::update_user(int64_t id, const models::UpdateUserDTO& dto) {
    auto user = get_user(id);

    if (dto.username) {
        if (*dto.username != user.get_username()) {
            if (user_repo_->find_by_username(*dto.username)) {
                throw std::runtime_error("Username already taken");
            }
            user.set_username(*dto.username);
        }
    }

    if (dto.role) {
        user.set_role(*dto.role);
    }

    if (dto.status) {
        user.set_status(*dto.status);
    }

    return user_repo_->update(user);
}

void UserService::delete_user(int64_t id) {
    get_user(id);  // Verify exists
    user_repo_->remove(id);
}

models::User UserService::activate_user(int64_t id) {
    auto user = get_user(id);
    user.set_status(models::UserStatus::Active);
    user.set_email_verified(true);
    return user_repo_->update(user);
}

models::User UserService::suspend_user(int64_t id, const std::string& reason, int duration_days) {
    auto user = get_user(id);
    user.set_status(models::UserStatus::Suspended);
    auto updated_user = user_repo_->update(user);

    std::optional<int> duration = duration_days > 0 ? std::make_optional(duration_days) : std::nullopt;
    email_service_->send_suspension_notice(updated_user, reason, duration);

    return updated_user;
}

models::User UserService::deactivate_user(int64_t id) {
    auto user = get_user(id);
    user.set_status(models::UserStatus::Inactive);
    return user_repo_->update(user);
}

repository::PaginatedResult UserService::list_users(const repository::ListOptions& options) {
    return user_repo_->list(options);
}

std::vector<models::User> UserService::search_users(const std::string& query, int limit) {
    return user_repo_->search(query, limit);
}

void UserService::change_password(int64_t user_id, const std::string& current_password,
                                  const std::string& new_password) {
    auto user = get_user(user_id);

    if (!verify_password(current_password, user.get_email())) {  // Would use actual hash
        throw std::runtime_error("Invalid current password");
    }

    auto password_result = utils::Validator::validate_password(new_password);
    if (!password_result) {
        throw std::invalid_argument("Invalid new password: " + password_result.errors[0]);
    }

    user.set_password_hash(hash_password(new_password));
    user_repo_->update(user);
}

void UserService::reset_password(int64_t user_id, const std::string& new_password) {
    auto user = get_user(user_id);

    auto password_result = utils::Validator::validate_password(new_password);
    if (!password_result) {
        throw std::invalid_argument("Invalid password: " + password_result.errors[0]);
    }

    user.set_password_hash(hash_password(new_password));
    user_repo_->update(user);
}

std::optional<models::User> UserService::authenticate(const std::string& email,
                                                       const std::string& password) {
    auto user = user_repo_->find_by_email(email);
    if (!user) {
        return std::nullopt;
    }

    if (!user->verify_password(password)) {
        return std::nullopt;
    }

    if (user->get_status() == models::UserStatus::Suspended) {
        throw std::runtime_error("Account suspended");
    }

    return user;
}

void UserService::update_last_login(int64_t user_id, const std::string& ip) {
    user_repo_->update_last_login(user_id, ip);
}

repository::UserStats UserService::get_stats() {
    return user_repo_->get_stats();
}

int UserService::cleanup_unverified_users(int days) {
    // Would implement actual cleanup
    return 0;
}

std::string UserService::hash_password(const std::string& password) {
    // Would use actual bcrypt
    return "hashed_" + password;
}

bool UserService::verify_password(const std::string& password, const std::string& hash) {
    // Would use actual bcrypt verification
    return hash_password(password) == hash;
}

} // namespace service
} // namespace myapp

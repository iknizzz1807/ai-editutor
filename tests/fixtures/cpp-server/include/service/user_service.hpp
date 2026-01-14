// include/service/user_service.hpp - User service interface

#ifndef SERVICE_USER_SERVICE_HPP
#define SERVICE_USER_SERVICE_HPP

#include <memory>
#include <string>
#include <optional>
#include "models/user.hpp"
#include "repository/user_repository.hpp"

namespace myapp {
namespace service {

class EmailService;  // Forward declaration

class UserService {
public:
    UserService(
        std::shared_ptr<repository::IUserRepository> user_repo,
        std::shared_ptr<EmailService> email_service
    );
    ~UserService();

    // User CRUD
    models::User create_user(const models::CreateUserDTO& dto, bool send_verification = true);
    models::User get_user(int64_t id);
    std::optional<models::User> get_user_by_email(const std::string& email);
    models::User update_user(int64_t id, const models::UpdateUserDTO& dto);
    void delete_user(int64_t id);

    // User status management
    models::User activate_user(int64_t id);
    models::User suspend_user(int64_t id, const std::string& reason, int duration_days = 0);
    models::User deactivate_user(int64_t id);

    // List and search
    repository::PaginatedResult list_users(const repository::ListOptions& options);
    std::vector<models::User> search_users(const std::string& query, int limit = 20);

    // Password management
    void change_password(int64_t user_id, const std::string& current_password,
                        const std::string& new_password);
    void reset_password(int64_t user_id, const std::string& new_password);

    // Authentication
    // Q: How should we handle memory safety when storing sensitive data like passwords?
    std::optional<models::User> authenticate(const std::string& email, const std::string& password);
    void update_last_login(int64_t user_id, const std::string& ip);

    // Statistics
    repository::UserStats get_stats();

    // Cleanup
    int cleanup_unverified_users(int days = 7);

private:
    std::string hash_password(const std::string& password);
    bool verify_password(const std::string& password, const std::string& hash);

    std::shared_ptr<repository::IUserRepository> user_repo_;
    std::shared_ptr<EmailService> email_service_;
};

} // namespace service
} // namespace myapp

#endif // SERVICE_USER_SERVICE_HPP

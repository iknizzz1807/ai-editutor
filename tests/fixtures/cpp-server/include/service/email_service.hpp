// include/service/email_service.hpp - Email service interface

#ifndef SERVICE_EMAIL_SERVICE_HPP
#define SERVICE_EMAIL_SERVICE_HPP

#include <string>
#include <vector>
#include <optional>
#include <functional>
#include "models/user.hpp"

namespace myapp {
namespace service {

struct EmailConfig {
    std::string smtp_host;
    int smtp_port;
    std::string username;
    std::string password;
    std::string from_address;
    std::string support_address;
    bool use_tls = true;
};

struct BulkEmailResult {
    int sent = 0;
    int failed = 0;
    std::vector<std::pair<std::string, std::string>> errors;  // email -> error
};

enum class NotificationType {
    NewLogin,
    PasswordChanged,
    ProfileUpdated,
    SecurityAlert
};

class EmailService {
public:
    explicit EmailService(const EmailConfig& config);
    ~EmailService();

    // Verification emails
    bool send_verification_email(const models::User& user);
    bool send_password_reset_email(const models::User& user, const std::string& token);
    bool send_welcome_email(const models::User& user);

    // Notification emails
    bool send_suspension_notice(const models::User& user, const std::string& reason,
                               std::optional<int> duration_days = std::nullopt);
    bool send_notification(const models::User& user, NotificationType type,
                          const std::map<std::string, std::string>& data = {});

    // Q: What's the best approach for implementing async email sending with retry logic in C++?
    BulkEmailResult send_bulk_email(
        const std::vector<models::User>& users,
        const std::string& subject,
        const std::string& template_name,
        const std::map<std::string, std::string>& extra_data = {}
    );

    // Async sending (with callback)
    void send_async(
        const std::string& to,
        const std::string& subject,
        const std::string& body,
        std::function<void(bool success, const std::string& error)> callback
    );

private:
    bool send_email(const std::string& to, const std::string& subject, const std::string& body);
    std::string render_template(const std::string& template_name,
                               const std::map<std::string, std::string>& variables);
    std::string generate_verification_token(const models::User& user);

    EmailConfig config_;
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace service
} // namespace myapp

#endif // SERVICE_EMAIL_SERVICE_HPP

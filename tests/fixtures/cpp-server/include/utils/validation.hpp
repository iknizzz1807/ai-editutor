// include/utils/validation.hpp - Input validation utilities

#ifndef UTILS_VALIDATION_HPP
#define UTILS_VALIDATION_HPP

#include <string>
#include <vector>
#include <regex>
#include <optional>

namespace myapp {
namespace utils {

struct ValidationResult {
    bool valid = true;
    std::vector<std::string> errors;

    void add_error(const std::string& error) {
        valid = false;
        errors.push_back(error);
    }

    operator bool() const { return valid; }
};

class Validator {
public:
    // Email validation
    static ValidationResult validate_email(const std::string& email);

    // Username validation
    static ValidationResult validate_username(const std::string& username);

    // Q: Should we implement password entropy calculation for better security feedback?
    // Password validation
    static ValidationResult validate_password(const std::string& password);

    // Phone validation
    static ValidationResult validate_phone(const std::string& phone,
                                          const std::optional<std::string>& country_code = std::nullopt);

    // Generic validators
    static bool is_empty(const std::string& value);
    static bool matches_regex(const std::string& value, const std::string& pattern);
    static bool is_length_between(const std::string& value, size_t min, size_t max);

    // Common patterns
    static const std::regex EMAIL_PATTERN;
    static const std::regex USERNAME_PATTERN;
    static const std::regex PHONE_PATTERN;
    static const std::regex SLUG_PATTERN;

    // Reserved words
    static const std::vector<std::string> RESERVED_USERNAMES;
    static const std::vector<std::string> COMMON_PASSWORDS;
};

// Password strength
enum class PasswordStrength {
    Weak,
    Fair,
    Strong,
    VeryStrong
};

struct PasswordStrengthResult {
    PasswordStrength strength;
    int score;
    std::string feedback;
    std::vector<std::string> suggestions;
};

PasswordStrengthResult check_password_strength(const std::string& password);

// Sanitization
class Sanitizer {
public:
    // HTML escaping
    static std::string escape_html(const std::string& input);

    // SQL escaping (for logging only - use parameterized queries!)
    static std::string escape_sql(const std::string& input);

    // Trim whitespace
    static std::string trim(const std::string& input);
    static std::string trim_left(const std::string& input);
    static std::string trim_right(const std::string& input);

    // Normalize
    static std::string normalize_email(const std::string& email);
    static std::string normalize_phone(const std::string& phone);
    static std::string to_slug(const std::string& input);
};

} // namespace utils
} // namespace myapp

#endif // UTILS_VALIDATION_HPP
